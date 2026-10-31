pragma Singleton

import QtQuick
import Quickshell

// Commands from IPC / keybinds to every island window, plus runtime overrides.
Singleton {
    id: root

    signal toggleRequested
    signal expandRequested
    signal collapseRequested

    // null = follow config.json, otherwise a runtime override from island-ctl.
    property var keepOnTopOverride: null
    readonly property bool keepOnTop: keepOnTopOverride !== null ? keepOnTopOverride : Config.cfg.layer.keepOnTop
}
