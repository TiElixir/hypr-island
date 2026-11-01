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
    // The window is only as big as what is on screen: small while collapsed or
    // hovered, and just tall enough for the expanded view while expanded. Every
    // pixel of it is drawn, composited and (with a layer blur rule) blurred by
    // the compositor on every frame of an animation, so less area is smoother
    // on a 144 Hz display. Resizing happens on mode changes, never per frame.
    property bool tall: false
    property real tallHeight: 110
    implicitWidth: tall ? Math.min(Config.cfg.window.width, Math.max(760, Math.ceil(pill.target.width) + 360)) : Math.min(Config.cfg.window.width, 760)
    implicitHeight: tall ? tallHeight : 110
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
        if (mode === "expanded") {
            shrinkTimer.stop();
            // room for the expanded view, plus the spring's overshoot
            const design = current ? current.sizeFor("expanded").height : 0;
            tallHeight = Math.min(Config.cfg.window.height, Math.max(110, Math.ceil(design * Config.cfg.sizes.expandedScale) + 40));
            tall = true;
        } else if (tall) {
            shrinkTimer.restart();
        }
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

    // Shrink the window once the collapse animation has settled.
    Timer {
        id: shrinkTimer
        interval: 800
        onTriggered: if (win.mode !== "expanded")
            win.tall = false
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

    // ---- input mask: only the pill, its flares, bubble and clock take input ----
    // Computed from where things are going (the targets), not from the animated
    // geometry: the mask then changes only when the mode changes instead of
    // being recomputed and sent to the compositor on every frame.
    readonly property real tW: pill.target.width
    readonly property real tH: pill.target.height
    readonly property real tX: (win.width - tW) / 2
    readonly property real tAttach: mode === "collapsed" ? 0 : 1
    readonly property real tY: Config.cfg.window.marginTop * (1 - tAttach)
    readonly property real tRb: Math.min(tH / 2, Config.cfg.sizes.maxRadius)
    readonly property real tFlare: Math.min(Math.max(0, Number(Config.cfg.sizes.flare)), Math.max(0, tH - tRb - 2)) * tAttach
    readonly property real tBubbleX: tX + tW + tFlare + 8
    readonly property real tEdge: bubble.shown ? tBubbleX + bubble.width : tX + tW + tFlare
    readonly property real tClockX: pill.visible ? tEdge + Config.cfg.clock.gap : (win.width - clock.width) / 2

    mask: Region {
        x: Math.max(0, Math.floor(win.tX))
        y: 0
        width: Math.ceil(pill.visible ? win.tW : 0)
        height: Math.ceil(pill.visible ? win.tY + win.tH : 0)

        // the two flares beside an attached pill
        Region {
            x: Math.max(0, Math.floor(win.tX - win.tFlare))
            y: 0
            width: Math.ceil(pill.visible ? win.tFlare : 0)
            height: Math.ceil(pill.visible ? win.tFlare : 0)
        }
        Region {
            x: Math.max(0, Math.floor(win.tX + win.tW))
            y: 0
            width: Math.ceil(pill.visible ? win.tFlare : 0)
            height: Math.ceil(pill.visible ? win.tFlare : 0)
        }
        Region {
            x: Math.max(0, Math.floor(win.tBubbleX))
            y: Config.cfg.window.marginTop
            width: bubble.shown ? Math.ceil(bubble.width) : 0
            height: bubble.shown ? Math.ceil(bubble.height) : 0
        }
        Region {
            x: Math.max(0, Math.floor(win.tClockX))
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
            if (!win.current)
                return;
            // A click on the expanded island (not on one of its buttons, which
            // take the click themselves) collapses it.
            if (win.mode === "expanded") {
                win.mode = "collapsed";
                return;
            }
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
        y: Config.cfg.window.marginTop
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
