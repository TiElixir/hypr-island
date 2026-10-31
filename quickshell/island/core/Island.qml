import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// One island window per target screen. The window has a fixed size so the
// compositor never reconfigures it while the pill animates; the input mask
// is the pill rectangle, so the rest of the top edge stays clickable.
PanelWindow {
    id: win

    required property var modelData
    required property Selector selector

    screen: modelData
    color: "transparent"

    anchors.top: true
    margins.top: Config.cfg.window.marginTop
    implicitWidth: Config.cfg.window.width
    implicitHeight: Config.cfg.window.height
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "island"
    WlrLayershell.layer: UiBus.keepOnTop ? WlrLayer.Overlay : WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // ---- state machine ----------------------------------------------------
    // mode: "collapsed" | "hover" | "expanded"
    property string mode: "collapsed"
    // The activity currently on screen. Follows selector.primary, but a
    // hover/expanded view is never swapped out from under the pointer.
    property var current: null
    readonly property var primary: selector.primary

    function sync() {
        if (primary === null) {
            current = null;
            mode = "collapsed";
            return;
        }
        if (current === null || !current.live) {
            current = primary;
            mode = "collapsed";
        } else if (mode === "collapsed") {
            current = primary;
        }
    }
    onPrimaryChanged: sync()
    onModeChanged: {
        sync();
        // Expanded without the pointer (keybind / IPC): don't linger forever.
        if (mode === "expanded" && !hovered && Config.cfg.timings.collapseOnLeave) {
            leaveTimer.interval = Config.cfg.timings.expandedIdleMs;
            leaveTimer.restart();
        }
    }
    Component.onCompleted: sync()

    Connections {
        target: win.current
        ignoreUnknownSignals: true
        function onLiveChanged() {
            win.sync();
        }
    }

    Connections {
        target: UiBus
        function onToggleRequested() {
            win.mode = win.mode === "expanded" ? "collapsed" : "expanded";
        }
        function onExpandRequested() {
            win.mode = "expanded";
        }
        function onCollapseRequested() {
            win.mode = "collapsed";
        }
    }

    readonly property bool hovered: pill.hovered
    onHoveredChanged: {
        if (hovered) {
            leaveTimer.stop();
            if (mode === "collapsed")
                hoverInTimer.restart();
        } else {
            hoverInTimer.stop();
            if (mode === "hover" || (mode === "expanded" && Config.cfg.timings.collapseOnLeave)) {
                leaveTimer.interval = mode === "expanded" ? Config.cfg.timings.expandedLeaveMs : Config.cfg.timings.hoverOutMs;
                leaveTimer.restart();
            }
        }
    }

    Timer {
        id: hoverInTimer
        interval: Config.cfg.timings.hoverInMs
        onTriggered: if (win.hovered && win.mode === "collapsed")
            win.mode = "hover"
    }
    Timer {
        id: leaveTimer
        onTriggered: if (!win.hovered && win.mode !== "collapsed")
            win.mode = "collapsed"
    }

    // Click outside collapses. Only grabbed while expanded.
    HyprlandFocusGrab {
        windows: [win]
        active: Config.cfg.behavior.focusGrab && win.mode === "expanded"
        onCleared: win.mode = "collapsed"
    }

    // ---- input mask: only the pill takes input ----------------------------
    mask: Region {
        x: Math.max(0, Math.floor(pill.x))
        y: 0
        width: Math.ceil(pill.visible ? pill.width : 0)
        height: Math.ceil(pill.visible ? pill.height : 0)
    }

    Pill {
        id: pill
        act: win.current
        mode: win.mode
        onClicked: {
            if (win.mode === "expanded" || !win.current)
                return;
            const expand = win.current.onActivated(win.mode);
            if (expand !== false)
                win.mode = "expanded";
        }
    }
}
