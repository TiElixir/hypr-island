pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Wake-up signal for every file-backed source (Claude sessions, island-ctl
// pushes). Producers write their state files atomically, then rewrite the
// 1-byte .tick file in place; that file is the only thing watched, because
// Quickshell can watch files but not directories. No polling anywhere.
Singleton {
    id: root

    readonly property string stateDir: Quickshell.env("XDG_RUNTIME_DIR") + "/island"
    readonly property string ctl: Quickshell.env("HOME") + "/.local/bin/island-ctl"

    signal changed

    Process {
        running: true
        command: ["sh", "-c", 'mkdir -p "$1/claude" "$1/push"; [ -e "$1/.tick" ] || : > "$1/.tick"', "sh", root.stateDir]
        onExited: {
            tick.path = root.stateDir + "/.tick";
            root.changed();
        }
    }
    FileView {
        id: tick
        watchChanges: true
        printErrors: false
        onFileChanged: {
            reload();
            root.changed();
        }
    }
}
