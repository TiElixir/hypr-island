pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// User config: ~/.config/island/config.json, deep-merged over `defaults`.
// Module settings live under modules.<id>.{enabled, priority, options.<key>};
// their defaults come from each module's manifest.json, not from here.
//
// The Settings panel edits through set()/reset(): the change is applied at
// once and saved (debounced) to the file. Edits made to the file by hand are
// hot-reloaded.
Singleton {
    id: root

    readonly property string path: Quickshell.env("HOME") + "/.config/island/config.json"

    readonly property var defaults: ({
        // "focused" | "primary" | "all"
        monitor: { policy: "focused", name: "" },
        // keepOnTop: true  -> overlay layer, island stays above fullscreen windows
        //            false -> top layer, fullscreen windows cover it
        layer: { keepOnTop: true },
        // The window is a fixed, invisible area the pill moves in; it must be
        // larger than the biggest expanded pill plus the clock beside it.
        window: { width: 920, height: 460, marginTop: 3 },
        sizes: {
            collapsedHeight: 24,
            maxRadius: 24,
            // Radius of the concave flares joining an expanded island to the top edge.
            flare: 22,
            // Expanded views are drawn this much larger than their design size.
            expandedScale: 1.2
        },
        // The standalone clock (not a module).
        clock: {
            enabled: true,
            // Qt format. Without an "s" the clock only wakes once a minute.
            format: "HH:mm:ss",
            dateFormat: "dddd, d MMMM yyyy",
            // Space between the island (or its bubble) and the clock.
            gap: 14
        },
        timings: {
            hoverInMs: 80,
            hoverOutMs: 250,
            expandedLeaveMs: 600,
            // Opened by keybind but the pointer never came near: collapse after this.
            expandedIdleMs: 5000,
            collapseOnLeave: true
        },
        behavior: {
            // Experimental. Grabs input while expanded so an outside click
            // collapses it, but on Hyprland 0.56 it stops the pill from seeing
            // hover, so leave-to-collapse stops working. Off by default.
            focusGrab: false
        },
        spring: { spring: 3.0, damping: 0.32, epsilon: 0.25 },
        colors: {
            bgAlpha: 0.9,
            running: "#FF9F0A",
            needsInput: "#FF453A",
            done: "#30D158"
        },
        font: { family: "JetBrainsMono Nerd Font", size: 13 },
        hooks: {
            enabled: true,
            timeoutSec: 10,
            // The same script is not started again within this window.
            minIntervalMs: 250,
            // "<event>/<script name>" entries switched off in Settings.
            disabled: []
        },
        modules: {}
    })

    property var user: ({})
    readonly property var cfg: merge(defaults, user)
    property bool loaded: false

    function isObj(v) {
        return v !== null && typeof v === "object" && !Array.isArray(v);
    }

    function merge(a, b) {
        if (!isObj(a) || !isObj(b))
            return b === undefined ? a : b;
        const out = {};
        for (const k in a)
            out[k] = a[k];
        for (const k in b)
            out[k] = isObj(a[k]) && isObj(b[k]) ? merge(a[k], b[k]) : b[k];
        return out;
    }

    function clone(v) {
        return JSON.parse(JSON.stringify(v));
    }

    // ---- reading ------------------------------------------------------------
    function get(path) {
        let o = cfg;
        for (const k of path) {
            if (o === undefined || o === null)
                return undefined;
            o = o[k];
        }
        return o;
    }

    // ---- writing ------------------------------------------------------------
    function set(path, value) {
        if (JSON.stringify(get(path)) === JSON.stringify(value) && hasUser(path))
            return;
        const u = clone(user);
        let o = u;
        for (let i = 0; i < path.length - 1; i++) {
            if (!isObj(o[path[i]]))
                o[path[i]] = {};
            o = o[path[i]];
        }
        o[path[path.length - 1]] = value;
        user = u;
        scheduleSave();
    }

    function hasUser(path) {
        let o = user;
        for (const k of path) {
            if (!isObj(o) || o[k] === undefined)
                return false;
            o = o[k];
        }
        return true;
    }

    // Back to the default: remove the override and prune empty parents.
    function reset(path) {
        if (!hasUser(path))
            return;
        const u = clone(user);
        const trail = [u];
        let o = u;
        for (let i = 0; i < path.length - 1; i++) {
            o = o[path[i]];
            trail.push(o);
        }
        delete o[path[path.length - 1]];
        for (let i = trail.length - 1; i > 0; i--) {
            if (Object.keys(trail[i]).length === 0)
                delete trail[i - 1][path[i - 1]];
            else
                break;
        }
        user = u;
        scheduleSave();
    }

    function resetAll() {
        user = ({});
        scheduleSave();
    }

    property double ignoreUntil: 0
    function scheduleSave() {
        saveTimer.restart();
    }
    Timer {
        id: saveTimer
        interval: 300
        onTriggered: {
            root.ignoreUntil = Date.now() + 1200;
            file.setText(JSON.stringify(root.user, null, 2) + "\n");
        }
    }
    Process {
        running: true
        command: ["mkdir", "-p", Quickshell.env("HOME") + "/.config/island"]
    }

    // ---- old flat keys (clock, spotify, claude, external, enabled, priorities) --
    // Configs written before modules had manifests keep working; saving rewrites
    // them in the modules.<id> layout.
    function normalize(u) {
        const legacy = ["spotify", "claude", "external", "enabled", "priorities"];
        const hasClockModule = isObj(u.modules) && u.modules.clock !== undefined;
        if (!legacy.some(k => u[k] !== undefined) && !hasClockModule)
            return u;
        const out = clone(u);
        for (const k of legacy)
            delete out[k];
        // The clock used to be a module; it is now the standalone clock.
        if (hasClockModule) {
            const old = out.modules.clock;
            delete out.modules.clock;
            out.clock = isObj(out.clock) ? out.clock : {};
            if (isObj(old.options))
                for (const k of ["format", "dateFormat"])
                    if (old.options[k] !== undefined)
                        out.clock[k] = old.options[k];
            if (old.enabled !== undefined)
                out.clock.enabled = old.enabled;
        }
        const mods = out.modules = isObj(out.modules) ? out.modules : {};
        const mod = id => (mods[id] = isObj(mods[id]) ? mods[id] : {});
        const opts = id => (mod(id).options = isObj(mod(id).options) ? mod(id).options : {});
        if (isObj(u.enabled))
            for (const id in u.enabled)
                mod(id).enabled = u.enabled[id] !== false;
        if (isObj(u.priorities)) {
            const p = u.priorities;
            for (const id of ["spotify", "external"])
                if (p[id] !== undefined)
                    mod(id).priority = p[id];
            if (p.claude_running !== undefined)
                mod("claude").priority = p.claude_running;
            if (p.claude_needs_input !== undefined)
                opts("claude").priorityNeedsInput = p.claude_needs_input;
            if (p.claude_done !== undefined)
                opts("claude").priorityDone = p.claude_done;
        }
        for (const id of ["spotify", "claude", "external"])
            if (isObj(u[id]))
                for (const k in u[id])
                    opts(id)[k] = u[id][k];
        return out;
    }

    FileView {
        id: file
        path: root.path
        watchChanges: true
        printErrors: false
        // In-place writes keep the file watch alive.
        atomicWrites: false
        onFileChanged: {
            if (Date.now() < root.ignoreUntil)
                return;
            reload();
        }
        onLoaded: {
            try {
                const parsed = JSON.parse(text());
                root.user = root.isObj(parsed) ? root.normalize(parsed) : {};
            } catch (e) {
                console.warn("island: ignoring invalid config.json:", e);
                root.user = {};
            }
            root.loaded = true;
        }
        onLoadFailed: {
            root.user = {};
            root.loaded = true;
        }
    }
}
