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
    // The window sits at the very top of the screen so the expanded island
    // can be flush with the edge; the pill itself is offset by window.marginTop.
    margins.top: 0
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
    // Set when the side bubble was clicked: that activity stays in front
    // until it ends or something urgent arrives.
    property var pinned: null
    readonly property var wanted: pinned !== null && pinned.live ? pinned : primary

    function sync() {
        if (wanted === null) {
            current = null;
            mode = "collapsed";
            return;
        }
        if (current === null || !current.live) {
            current = wanted;
            mode = "collapsed";
        } else if (mode === "collapsed" || (wanted.urgent && current !== wanted)) {
            current = wanted;
        }
    }

    // The runner-up, shown as a bubble. The ambient clock never is one.
    readonly property var bubbleAct: {
        const l = selector.sorted;
        for (let i = 0; i < l.length; i++) {
            if (l[i] !== current && !l[i].ambient)
                return l[i];
        }
        return null;
    }

    property var _prev: null
    onCurrentChanged: {
        if (_prev && _prev !== current) {
            _prev.hostMode = "collapsed";
            _prev.hostHovered = false;
        }
        if (_prev && _prev !== current)
            _prev.hostPresented = false;
        if (current) {
            current.hostMode = mode;
            current.hostHovered = hovered;
            current.hostPresented = true;
            Events.emit("island.primary", { activity: current.moduleId });
        }
        _prev = current;
    }

    property var _prevBubble: null
    onBubbleActChanged: {
        if (_prevBubble && _prevBubble !== bubbleAct)
            _prevBubble.hostBubble = false;
        if (bubbleAct)
            bubbleAct.hostBubble = true;
        _prevBubble = bubbleAct;
    }
    onPrimaryChanged: {
        if (primary !== null && primary.urgent)
            pinned = null;
        sync();
    }
    onWantedChanged: sync()

    function swapToBubble() {
        if (bubbleAct === null)
            return;
        pinned = bubbleAct === primary ? null : bubbleAct;
        mode = "collapsed";
        current = wanted;
    }
    onModeChanged: {
        sync();
        if (current) {
            current.hostMode = mode;
            Events.emit("island.mode", { mode: mode, activity: current.moduleId });
        }
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
        function onSwapRequested() {
            win.swapToBubble();
        }
    }

    readonly property bool hovered: pill.hovered
    onHoveredChanged: {
        if (current)
            current.hostHovered = hovered;
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
        height: Math.ceil(pill.visible ? pill.y + pill.height : 0)

        // the two flares beside an attached pill
        Region {
            x: Math.max(0, Math.floor(pill.x - pill.flareExtent))
            y: 0
            width: Math.ceil(pill.visible ? pill.flareExtent : 0)
            height: Math.ceil(pill.visible ? pill.flareExtent : 0)
        }
        Region {
            x: Math.max(0, Math.floor(pill.x + pill.width))
            y: 0
            width: Math.ceil(pill.visible ? pill.flareExtent : 0)
            height: Math.ceil(pill.visible ? pill.flareExtent : 0)
        }
        Region {
            x: Math.max(0, Math.floor(bubble.x))
            y: Math.max(0, Math.floor(bubble.y))
            width: bubble.visible ? Math.ceil(bubble.width) : 0
            height: bubble.visible ? Math.ceil(bubble.height) : 0
        }
        Region {
            x: Math.max(0, Math.floor(clock.x))
            y: Math.max(0, Math.floor(clock.y))
            width: clock.visible ? Math.ceil(clock.width) : 0
            height: clock.visible ? Math.ceil(clock.height) : 0
        }
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

    Bubble {
        id: bubble
        act: win.bubbleAct
        shown: win.bubbleAct !== null && win.mode !== "expanded"
        x: pill.x + pill.width + pill.flareExtent + 8
        y: pill.y
        onClicked: win.swapToBubble()
    }

    // The clock is never part of the island. Idle: centered in the bar.
    // With the island showing something: to the right of it (and its bubble).
    ClockWidget {
        id: clock
        readonly property real islandEdge: bubble.visible ? bubble.x + bubble.width : pill.x + pill.width + pill.flareExtent
        x: pill.visible ? Math.round(islandEdge + Config.cfg.clock.gap) : Math.round((win.width - width) / 2)
        y: Math.round(Config.cfg.window.marginTop + (Config.cfg.sizes.collapsedHeight - height) / 2)
        Behavior on x {
            enabled: !pill.visible || Math.abs(pill.width - pill.target.width) < 2
            NumberAnimation {
                duration: 260
                easing.type: Easing.OutCubic
            }
        }
    }
}
