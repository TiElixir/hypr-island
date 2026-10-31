pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Event hooks: executables dropped into ~/.config/island/hooks/<event>/ run
// whenever that event is emitted on the bus. They get the payload as JSON on
// stdin, in $ISLAND_DATA, and as flat $ISLAND_<FIELD> variables. They run with
// a timeout, in a small pool, rate-limited per script, and never block the island.
//
//   ~/.config/island/hooks/claude.state/10-lights.sh   (chmod +x)
Singleton {
    id: root

    readonly property string dir: Quickshell.env("HOME") + "/.config/island/hooks"
    readonly property var cfg: Config.cfg.hooks

    // [{ event, path, name, key, disabled }]
    property var scripts: []
    property var failures: ({})   // key -> last failure text
    property var lastRun: ({})    // key -> ms
    property int ran: 0

    readonly property var byEvent: {
        const m = {};
        for (const s of scripts) {
            if (s.disabled)
                continue;
            (m[s.event] = m[s.event] || []).push(s);
        }
        return m;
    }

    function rescan() {
        if (!lister.running)
            lister.running = true;
    }

    Process {
        id: lister
        command: ["sh", "-c", 'mkdir -p "$1"; for d in "$1"/*/; do [ -d "$d" ] || continue; ev=$(basename "$d"); ' + 'for f in "$d"*; do [ -f "$f" ] && [ -x "$f" ] && printf "%s\\t%s\\n" "$ev" "$f"; done; done; exit 0', "sh", root.dir]
        stdout: StdioCollector {
            onStreamFinished: {
                const off = root.cfg.disabled || [];
                const out = [];
                for (const line of text.split("\n")) {
                    const i = line.indexOf("\t");
                    if (i < 1)
                        continue;
                    const ev = line.slice(0, i);
                    const path = line.slice(i + 1);
                    const name = path.slice(path.lastIndexOf("/") + 1);
                    const key = ev + "/" + name;
                    out.push({ event: ev, path: path, name: name, key: key, disabled: off.indexOf(key) >= 0 });
                }
                out.sort((a, b) => a.event.localeCompare(b.event) || a.name.localeCompare(b.name));
                root.scripts = out;
            }
        }
    }

    // `disabled` lives in config; keep the discovered list in step with it.
    Connections {
        target: Config
        function onCfgChanged() {
            const off = root.cfg.disabled || [];
            let diff = false;
            const next = root.scripts.map(s => {
                const d = off.indexOf(s.key) >= 0;
                if (d !== s.disabled)
                    diff = true;
                return Object.assign({}, s, { disabled: d });
            });
            if (diff)
                root.scripts = next;
        }
    }

    // ---- dispatch -----------------------------------------------------------
    Connections {
        target: Events
        function onEvent(name, data) {
            root.dispatch(name, data);
        }
    }

    property var queue: []

    function dispatch(name, data) {
        if (!cfg.enabled)
            return;
        const list = byEvent[name];
        if (!list)
            return;
        const now = Date.now();
        for (const s of list) {
            if (now - (lastRun[s.key] || 0) < cfg.minIntervalMs)
                continue;
            lastRun[s.key] = now;
            if (queue.length >= 50)
                break;
            queue.push({ s: s, name: name, data: data });
        }
        pump();
    }

    // Fire one script by hand (Settings "test" button).
    function test(script) {
        queue.push({ s: script, name: script.event, data: { test: true } });
        pump();
    }

    function envFor(name, data) {
        const env = { ISLAND_EVENT: name, ISLAND_DATA: JSON.stringify(data), ISLAND_CTL: Feed.ctl };
        for (const k in data) {
            const v = data[k];
            if (v === null || typeof v === "object")
                continue;
            env["ISLAND_" + k.toUpperCase().replace(/[^A-Z0-9]/g, "_")] = String(v);
        }
        return env;
    }

    function pump() {
        for (let i = 0; i < slots.count && queue.length > 0; i++) {
            const slot = slots.objectAt(i);
            if (slot && !slot.busy) {
                const job = queue.shift();
                slot.start(job);
            }
        }
    }

    Instantiator {
        id: slots
        model: 4
        delegate: QtObject {
            id: slot
            property bool busy: false
            property var job: null

            function start(j) {
                job = j;
                busy = true;
                proc.environment = root.envFor(j.name, j.data);
                proc.command = ["sh", "-c", 'printf %s "$ISLAND_DATA" | exec timeout "$1" "$0"', j.s.path, String(root.cfg.timeoutSec)];
                proc.running = true;
            }

            property Process proc: Process {
                stderr: StdioCollector {
                    id: err
                }
                onExited: code => {
                    const f = Object.assign({}, root.failures);
                    if (code !== 0)
                        f[slot.job.s.key] = (code === 124 ? "timed out" : "exit " + code) + (err.text ? ": " + err.text.trim().slice(0, 200) : "");
                    else
                        delete f[slot.job.s.key];
                    root.failures = f;
                    root.ran++;
                    slot.busy = false;
                    root.pump();
                }
            }
        }
    }
}
