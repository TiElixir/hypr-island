import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.components

// Claude Code sessions. The truth lives in one JSON file per session under
// $XDG_RUNTIME_DIR/island/claude/, written atomically by the hook. The hook
// also rewrites .tick in place; that single file is what we watch (Quickshell
// cannot watch a directory), then a debounced rescan reads every session.
// Nothing here polls: the only timers run while there is something to time.
Activity {
    id: root


    readonly property string claudeDir: Feed.stateDir + "/claude"
    readonly property var cfg: ({
            staleTimeoutMin: Number(option("staleTimeoutMin")),
            sweepSec: Number(option("sweepSec")),
            hoverAckMs: Number(option("hoverAckMs")),
            doneFadeSec: Number(option("doneFadeSec")),
            focusOnClick: option("focusOnClick") === true
        })

    // ---- model --------------------------------------------------------------
    // All registered sessions, most important first.
    property var sessions: []
    property real nowSec: Date.now() / 1000
    property int pulseCount: 0
    property bool loadedOnce: false

    function rank(state) {
        return state === "needs_input" || state === "error" ? 3 : state === "running" ? 2 : state === "done" ? 1 : 0;
    }
    function colorFor(state) {
        return rank(state) === 3 ? Theme.needsInput : state === "running" ? Theme.running : state === "done" ? Theme.done : Theme.fgDim;
    }
    function labelFor(state) {
        return state === "needs_input" ? "needs you" : state === "running" ? "working" : state === "done" ? "done" : state === "error" ? "error" : "idle";
    }
    function fmtDur(sec) {
        const s = Math.max(0, Math.floor(sec));
        if (s < 60)
            return s + "s";
        if (s < 3600)
            return Math.floor(s / 60) + "m";
        return Math.floor(s / 3600) + "h " + Math.floor((s % 3600) / 60) + "m";
    }

    readonly property var lit: sessions.filter(s => s.state !== "idle")
    readonly property var top: lit.length > 0 ? lit[0] : null
    readonly property string topState: top ? top.state : "idle"
    readonly property bool anyDone: sessions.some(s => s.state === "done")

    active: lit.length > 0
    urgent: rank(topState) === 3
    accent: colorFor(topState)
    // Priority follows the state: red takes the island, then working, then done.
    effectivePriority: rank(topState) === 3 ? Number(option("priorityNeedsInput")) : topState === "running" ? basePriority : Number(option("priorityDone"))

    // ---- sizes --------------------------------------------------------------
    readonly property int rows: Math.max(1, Math.min(6, sessions.length))
    collapsedSize: Qt.size(lit.length > 1 ? 62 : 44, Config.cfg.sizes.collapsedHeight + 2)
    hoverSize: Qt.size(310, 46)
    expandedSize: Qt.size(390, 46 + rows * 34)

    // ---- watching + scanning ------------------------------------------------
    Connections {
        target: Feed
        function onChanged() {
            scanTimer.restart();
        }
    }
    Timer {
        id: scanTimer
        interval: 40
        onTriggered: {
            if (scan.running)
                root.rescan = true;
            else
                scan.running = true;
        }
    }
    property bool rescan: false
    Process {
        id: scan
        command: ["sh", "-c", 'for f in "$1"/*.json; do [ -f "$f" ] && { cat "$f"; echo; }; done; exit 0', "sh", root.claudeDir]
        stdout: StdioCollector {
            onStreamFinished: root.ingest(text)
        }
        onExited: {
            if (root.rescan) {
                root.rescan = false;
                scan.running = true;
            }
        }
    }

    function safeId(id) {
        return /^[A-Za-z0-9._-]+$/.test(id) && id.charAt(0) !== ".";
    }

    function ingest(text) {
        const prev = {};
        for (const s of sessions)
            prev[s.id] = s.state;
        const out = [];
        let alerted = false;
        for (const line of text.split("\n")) {
            if (!line.trim())
                continue;
            try {
                const o = JSON.parse(line);
                if (!o || !safeId(String(o.id)) || typeof o.state !== "string")
                    continue;
                o.tsSec = Number(o.ts) / 1e9;
                o.since = Number(o.since) || 0;
                out.push(o);
                if (loadedOnce && prev[o.id] !== o.state)
                    emit("state", { session: o.id, project: o.project, from: prev[o.id] || "none", to: o.state });
                if (loadedOnce && rank(o.state) === 3 && prev[o.id] !== o.state)
                    alerted = true;
            } catch (e) {}
        }
        if (loadedOnce) {
            const now = {};
            for (const o of out)
                now[o.id] = true;
            for (const id in prev)
                if (!now[id])
                    emit("state", { session: id, project: "", from: prev[id], to: "ended" });
        }
        out.sort((a, b) => rank(b.state) - rank(a.state) || b.since - a.since);
        sessions = out;
        loadedOnce = true;
        nowSec = Date.now() / 1000;
        if (alerted) {
            pulseCount++;
            attention();
        }
    }

    // ---- housekeeping: dead and stale sessions ------------------------------
    // Only runs while sessions exist; one tiny shell call per sweep.
    Timer {
        interval: Math.max(5, root.cfg.sweepSec) * 1000
        repeat: true
        running: root.sessions.length > 0
        onTriggered: root.sweep()
    }
    property var pendingDrop: []
    function sweep() {
        if (sweepProc.running)
            return;
        const now = Date.now() / 1000;
        const stale = root.cfg.staleTimeoutMin * 60;
        const args = [];
        const drop = [];
        for (const s of sessions) {
            const hasPid = Number(s.pid) > 0 && s.pid_start;
            if (hasPid)
                args.push(s.id, String(s.pid), String(s.pid_start));
            if ((s.state !== "running" || !hasPid) && now - s.tsSec > stale)
                drop.push(s.id);
        }
        pendingDrop = drop;
        sweepProc.command = ["sh", "-c", 'while [ $# -ge 3 ]; do id=$1; pid=$2; st=$3; shift 3; ' + 'cur=$(sed "s/^.*) //" "/proc/$pid/stat" 2>/dev/null | awk \'{print $20}\'); ' + '[ -n "$cur" ] && [ "$cur" = "$st" ] || echo "$id"; done; exit 0', "sh"].concat(args);
        sweepProc.running = true;
    }
    Process {
        id: sweepProc
        stdout: StdioCollector {
            onStreamFinished: {
                const dead = text.split("\n").filter(x => x.length > 0);
                const all = dead.concat(root.pendingDrop).filter(x => root.safeId(x));
                if (all.length > 0)
                    root.removeSessions(all);
            }
        }
    }
    Process {
        id: rmProc
        onExited: scanTimer.restart()
    }
    function removeSessions(ids) {
        if (rmProc.running)
            return;
        rmProc.command = ["sh", "-c", 'd=$1; shift; for i; do rm -f "$d/$i.json"; done', "sh", claudeDir].concat(ids);
        rmProc.running = true;
    }

    // ---- acknowledging green ------------------------------------------------
    // Writes state=idle into the session file, so it survives island restarts.
    Process {
        id: ackProc
        onExited: scanTimer.restart()
    }
    function ackSessions(ids) {
        if (ids.length === 0 || ackProc.running)
            return;
        ackProc.command = ["sh", "-c", 'd=$1; shift; n=$(date +%s); for i; do f="$d/$i.json"; [ -f "$f" ] || continue; ' + 'jq --argjson n "$n" \'if .state=="done" then .state="idle" | .since=$n else . end\' "$f" >"$f.ack.$$" && mv -f "$f.ack.$$" "$f"; done', "sh", claudeDir].concat(ids);
        ackProc.running = true;
    }
    function ackDone() {
        ackSessions(sessions.filter(s => s.state === "done").map(s => s.id));
    }
    function acknowledge() {
        ackDone();
    }
    function onActivated(mode) {
        // A lone green pill: the click means "seen it", not "open".
        if (topState === "done") {
            ackDone();
            return false;
        }
        return true;
    }

    // Focus the terminal window a session runs in (island-ctl walks the
    // process tree up to a Hyprland client).
    Process {
        id: focusProc
    }
    function focusSession(s) {
        if (!cfg.focusOnClick || !(Number(s.pid) > 0) || focusProc.running)
            return;
        focusProc.command = [Feed.ctl, "focus", String(s.pid)];
        focusProc.running = true;
    }

    // Hovering green for a cumulative hoverAckMs also acknowledges it.
    property int dwellMs: 0
    onTopStateChanged: dwellMs = 0
    Timer {
        interval: 250
        repeat: true
        running: root.topState === "done" && root.hostMode !== "collapsed" && root.hostHovered
        onTriggered: {
            root.dwellMs += 250;
            if (root.dwellMs >= root.cfg.hoverAckMs) {
                root.dwellMs = 0;
                root.ackDone();
            }
        }
    }
    // Optional: green also fades by itself after doneFadeSec (off by default).
    Timer {
        interval: 1000
        repeat: true
        running: root.cfg.doneFadeSec > 0 && root.anyDone
        onTriggered: {
            const now = Date.now() / 1000;
            root.ackSessions(root.sessions.filter(s => s.state === "done" && now - s.since > root.cfg.doneFadeSec).map(s => s.id));
        }
    }

    // Durations only tick while the pill shows them.
    Timer {
        interval: 1000
        repeat: true
        running: root.active && root.hostMode !== "collapsed"
        onTriggered: root.nowSec = Date.now() / 1000
    }
    onHostModeChanged: nowSec = Date.now() / 1000

    // ---- views --------------------------------------------------------------
    collapsedView: Component {
        Item {
            Row {
                anchors.centerIn: parent
                spacing: 7
                StateDot {
                    anchors.verticalCenter: parent.verticalCenter
                    size: 11
                    color: root.accent
                    pulseKey: root.pulseCount
                }
                Text {
                    visible: root.lit.length > 1
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.lit.length
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                    font.weight: Font.DemiBold
                }
            }
        }
    }

    bubbleView: Component {
        Item {
            StateDot {
                anchors.centerIn: parent
                size: 10
                color: root.accent
            }
        }
    }

    hoverView: Component {
        Item {
            StateDot {
                id: dot
                x: 18
                anchors.verticalCenter: parent.verticalCenter
                size: 12
                color: root.accent
            }
            Column {
                anchors.left: dot.right
                anchors.leftMargin: 12
                anchors.right: more.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                Text {
                    width: parent.width
                    text: root.top ? root.top.project : ""
                    elide: Text.ElideRight
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                    font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width
                    text: root.top ? root.labelFor(root.top.state) + " · " + root.fmtDur(root.nowSec - root.top.since) : ""
                    elide: Text.ElideRight
                    color: root.accent
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 3
                }
            }
            Text {
                id: more
                anchors.right: parent.right
                anchors.rightMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                visible: root.lit.length > 1
                text: "+" + (root.lit.length - 1)
                color: Theme.fgDim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 2
            }
        }
    }

    expandedView: Component {
        Item {
            Text {
                x: 20
                y: 14
                text: "Claude Code"
                color: Theme.fgDim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 3
                font.weight: Font.DemiBold
                font.letterSpacing: 0.6
            }
            Column {
                x: 8
                y: 38
                width: parent.width - 16
                Repeater {
                    model: root.sessions.slice(0, 6)
                    delegate: Item {
                        id: row
                        required property var modelData
                        width: parent.width
                        height: 34

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 1
                            radius: 10
                            color: Theme.fg
                            opacity: rowMouse.containsMouse ? 0.08 : 0
                        }
                        StateDot {
                            id: rd
                            x: 12
                            anchors.verticalCenter: parent.verticalCenter
                            size: 10
                            color: root.colorFor(row.modelData.state)
                        }
                        Text {
                            anchors.left: rd.right
                            anchors.leftMargin: 12
                            anchors.right: st.left
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.modelData.project
                            elide: Text.ElideRight
                            color: row.modelData.state === "idle" ? Theme.fgDim : Theme.fg
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 1
                        }
                        Text {
                            id: st
                            anchors.right: dur.left
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.labelFor(row.modelData.state)
                            color: root.colorFor(row.modelData.state)
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 2
                        }
                        Text {
                            id: dur
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            width: 48
                            horizontalAlignment: Text.AlignRight
                            text: root.fmtDur(root.nowSec - row.modelData.since)
                            color: Theme.fgDim
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 2
                        }
                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (row.modelData.state === "done")
                                    root.ackSessions([row.modelData.id]);
                                root.focusSession(row.modelData);
                            }
                        }
                    }
                }
            }
        }
    }
}
