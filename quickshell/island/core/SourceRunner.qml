import QtQuick
import Quickshell
import Quickshell.Io

// Runs a module's script ("source" in manifest.json) and feeds the module.
//
//   "source": { "command": ["python3", "fetch.py"], "mode": "poll", "intervalSec": 30 }
//
// mode "stream" (default): one long-running process, restarted with back-off
//   when it exits. mode "poll": run the command every intervalSec (or the value
//   of the module option named by "intervalOption"), with a timeout.
// Every stdout line that is a JSON object becomes inst.sourceMessage(obj) and
// inst.sourceData. A line like {"_event":"lap","n":3} also emits "<module>.lap"
// on the event bus. Anything else on stdout arrives as {text: "..."}.
// The script runs in the module's directory with $ISLAND_OPT_<KEY> set from
// the module's options, and restarts when those options change. It only exists
// while the module is enabled.
QtObject {
    id: sr

    required property var inst
    required property var spec
    required property string moduleDir

    readonly property string mode: spec.mode === "poll" ? "poll" : "stream"
    property bool desired: true
    property int backoff: 0
    property int errLines: 0

    // Every module option, or only the keys listed in the source's "options"
    // (so changing a display-only setting does not restart the script).
    function allOptions() {
        const o = {};
        const list = inst.manifest.options || [];
        // spec reaches us through createObject, which turns its arrays into
        // Qt sequences: Array.isArray() is false for those.
        const keys = spec.options;
        const only = keys !== null && typeof keys === "object" && typeof keys.length === "number" ? Array.from(keys) : null;
        for (let i = 0; i < list.length; i++)
            if (only === null || only.indexOf(list[i].key) >= 0)
                o[list[i].key] = inst.option(list[i].key);
        return o;
    }
    function environmentNow() {
        const env = {
            ISLAND_MODULE_ID: inst.moduleId,
            ISLAND_MODULE_DIR: moduleDir,
            ISLAND_CTL: Feed.ctl
        };
        const opts = allOptions();
        for (const k in opts) {
            const v = opts[k];
            env["ISLAND_OPT_" + k.toUpperCase().replace(/[^A-Z0-9]/g, "_")] = Array.isArray(v) ? v.join(",") : String(v);
        }
        return env;
    }
    readonly property string optionSignature: JSON.stringify(allOptions())
    onOptionSignatureChanged: restartSoon.restart()
    // The options the running script was started with.
    property string launchedSignature: ""
    // Set while a restart waits for the old process to exit.
    property bool relaunch: false
    readonly property real pollSec: {
        const fromOption = spec.intervalOption ? Number(inst.option(spec.intervalOption)) : NaN;
        const v = isNaN(fromOption) ? Number(spec.intervalSec) : fromOption;
        return Math.max(1, isNaN(v) ? 30 : v);
    }

    function setStatus(s) {
        inst.sourceStatus = s;
    }

    function launch() {
        if (!desired || proc.running)
            return;
        errLines = 0;
        proc.environment = environmentNow();
        launchedSignature = optionSignature;
        const cmd = spec.command || [];
        if (cmd.length === 0) {
            setStatus("error: no command");
            return;
        }
        proc.command = mode === "poll" ? ["timeout", String(spec.timeoutSec || 20)].concat(cmd) : cmd;
        setStatus("running");
        proc.running = true;
    }

    function start() {
        restartTimer.stop();
        pollTimer.stop();
        desired = true;
        backoff = 0;
        if (proc.running) {
            // The old process takes a moment to go: start the new one when it
            // has exited, instead of reading that exit as a crash.
            relaunch = true;
            proc.running = false;
        } else {
            launch();
        }
        if (mode === "poll")
            pollTimer.restart();
    }

    function stopProc() {
        relaunch = false;
        restartTimer.stop();
        pollTimer.stop();
        if (proc.running)
            proc.running = false;
    }

    function stop() {
        desired = false;
        stopProc();
        setStatus("off");
    }

    function handle(line) {
        const t = line.trim();
        if (t === "")
            return;
        let msg;
        try {
            const p = JSON.parse(t);
            msg = p !== null && typeof p === "object" && !Array.isArray(p) ? p : { value: p };
        } catch (e) {
            msg = { text: t };
        }
        inst.sourceData = msg;
        inst.sourceMessage(msg);
        if (typeof msg._event === "string" && /^[A-Za-z0-9_.-]+$/.test(msg._event))
            inst.emit(msg._event, msg);
    }

    function exited(code) {
        if (relaunch) {
            relaunch = false;
            restartTimer.interval = 0;
            restartTimer.restart();
            return;
        }
        if (!desired)
            return;
        if (mode === "poll") {
            setStatus(code === 0 ? "ok" : (code === 124 ? "error: timed out" : "error: exit " + code));
            return;
        }
        backoff = code === 0 ? (spec.restartSec || 5) : Math.min(60, Math.max(backoff * 2, spec.restartSec || 5));
        setStatus("exited (" + code + "), restarting in " + backoff + "s");
        restartTimer.interval = backoff * 1000;
        restartTimer.restart();
    }

    property Process proc: Process {
        workingDirectory: sr.moduleDir
        stdout: SplitParser {
            onRead: line => sr.handle(line)
        }
        stderr: SplitParser {
            onRead: line => {
                if (sr.errLines++ < 20)
                    console.warn("island module " + sr.inst.moduleId + ":", line);
            }
        }
        onExited: code => sr.exited(code)
    }
    property Timer restartTimer: Timer {
        onTriggered: sr.launch()
    }
    property Timer pollTimer: Timer {
        interval: sr.pollSec * 1000
        repeat: true
        onTriggered: sr.launch()
    }
    property Timer restartSoon: Timer {
        interval: 600
        // Only when the options really differ from what the script runs with
        // (the signature also settles once while the module is created).
        onTriggered: if (sr.desired && sr.optionSignature !== sr.launchedSignature)
            sr.start()
    }

    Component.onCompleted: start()
    Component.onDestruction: {
        desired = false;
        if (proc.running)
            proc.running = false;
    }
}
