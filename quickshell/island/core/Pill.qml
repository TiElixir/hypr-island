import QtQuick

// The visual pill. Width, height and corner shape are one spring-animated
// silhouette, drawn by a single fragment shader (shaders/body.frag) as a
// signed distance field: cheap per frame, no path tessellation, no offscreen
// clipping pass. Collapsed it is a floating rounded pill; hovered and expanded
// it attaches to the top edge of the screen with concave flares that ease out
// of the edge, and the lower corners stay rounded.
// Views are laid out at their *target* size and crossfaded inside a clip, so
// text never reflows while the pill morphs.
Item {
    id: root

    property var act: null
    property string mode: "collapsed"

    readonly property bool hovered: hover.hovered
    signal clicked

    // What is actually rendered. Lags `act` by one fade-out when swapping.
    property var shown: null
    property real swapOpacity: 1

    // ---- size ------------------------------------------------------------------
    readonly property real expandedScale: Math.max(1, Number(Config.cfg.sizes.expandedScale))
    readonly property real hoverScale: Math.max(0.5, Number(Config.cfg.sizes.hoverScale))
    // Hover and expanded views are drawn at their design size times this.
    function scaleFor(m) {
        return m === "expanded" ? expandedScale : m === "hover" ? hoverScale : 1;
    }
    readonly property size target: {
        if (!act)
            return Qt.size(0, 0);
        const s = act.sizeFor(mode);
        const k = scaleFor(mode);
        return Qt.size(s.width * k, s.height * k);
    }
    property real animW: target.width
    property real animH: target.height

    Behavior on animW {
        SpringAnimation {
            spring: Config.cfg.spring.spring
            damping: Config.cfg.spring.damping
            epsilon: Config.cfg.spring.epsilon
        }
    }
    Behavior on animH {
        SpringAnimation {
            spring: Config.cfg.spring.spring
            damping: Config.cfg.spring.damping
            epsilon: Config.cfg.spring.epsilon
        }
    }

    // 0: floating pill in the bar (collapsed). 1: flush with the top edge,
    // with flares (hover and expanded).
    property real attach: mode === "collapsed" ? 0 : 1
    Behavior on attach {
        NumberAnimation {
            duration: 280
            easing.type: Easing.OutCubic
        }
    }

    width: Math.max(10, animW)
    height: Math.max(10, animH)
    x: Math.round((parent.width - width) / 2)
    y: Config.cfg.window.marginTop * (1 - attach)
    visible: act !== null

    // ---- silhouette geometry ---------------------------------------------------
    readonly property real flareMax: Math.max(0, Number(Config.cfg.sizes.flare))
    readonly property real rb: Math.min(height / 2, Config.cfg.sizes.maxRadius)
    // The flare may not be taller than the straight part of the side wall,
    // so a small (hover) pill gets a proportionally smaller flare.
    readonly property real flareUse: Math.min(flareMax, Math.max(0, height - rb - 2))
    // How far the flares currently reach outside the body.
    readonly property real flareExtent: flareUse * attach
    // Radius of the convex top corners while floating; they flatten out as the
    // pill attaches to the edge and the flares take over.
    readonly property real corner: Math.min(rb, height / 2 - 1)

    onActChanged: {
        if (shown === null || act === null)
            shown = act;
        else if (shown !== act)
            swapAnim.restart();
        if (act && act.pulseAt > Date.now() - 1500)
            startPulse();
    }

    // ---- pulse: a coloured ring requested with Activity.pulse() ---------------
    property color glowColor: "white"
    property real glow: 0
    property int glowBeats: 2
    function startPulse() {
        glowColor = act.pulseColor;
        glowBeats = act.pulseBeats;
        pulseAnim.restart();
    }
    Connections {
        target: root.act
        ignoreUnknownSignals: true
        function onPulseSerialChanged() {
            root.startPulse();
        }
    }
    SequentialAnimation {
        id: pulseAnim
        SequentialAnimation {
            loops: root.glowBeats
            NumberAnimation {
                target: root
                property: "glow"
                to: 1
                duration: 140
                easing.type: Easing.OutQuad
            }
            NumberAnimation {
                target: root
                property: "glow"
                to: 0.2
                duration: 420
                easing.type: Easing.InOutQuad
            }
        }
        NumberAnimation {
            target: root
            property: "glow"
            to: 0
            duration: 380
        }
    }

    SequentialAnimation {
        id: swapAnim
        NumberAnimation {
            target: root
            property: "swapOpacity"
            to: 0
            duration: 90
        }
        ScriptAction {
            script: root.shown = root.act
        }
        NumberAnimation {
            target: root
            property: "swapOpacity"
            to: 1
            duration: 160
        }
    }

    // The body. The item reaches flareMax beyond the pill on both sides so the
    // flares have room; the outline and fill are drawn by the shader.
    ShaderEffect {
        id: bodyShape
        x: -root.flareMax
        y: 0
        width: root.width + 2 * root.flareMax
        height: root.height
        blending: true

        property vector2d size: Qt.vector2d(width, height)
        property vector4d shape: Qt.vector4d(root.flareMax, root.width, root.height, root.rb)
        property vector4d shape2: Qt.vector4d(root.corner * (1 - root.attach), root.flareExtent, 0, 0)
        property vector4d tint: Qt.vector4d(Theme.bg.r, Theme.bg.g, Theme.bg.b, Config.cfg.colors.bgAlpha)
        property vector4d glow: Qt.vector4d(root.glowColor.r, root.glowColor.g, root.glowColor.b, root.glow)
        fragmentShader: Qt.resolvedUrl("shaders/body.frag.qsb")
    }

    // Content is clipped to the body rectangle (a plain scissor clip, far
    // cheaper than a rounded one; views keep clear of the corners).
    Item {
        id: body
        anchors.fill: parent
        clip: true

        Repeater {
            model: ["collapsed", "hover", "expanded"]

            delegate: Loader {
                id: ld
                required property string modelData

                readonly property bool on: root.mode === modelData
                property real vis: on ? 1 : 0
                Behavior on vis {
                    NumberAnimation {
                        duration: ld.on ? 200 : 80
                    }
                }

                anchors.centerIn: parent
                // Laid out at the design size, then scaled (hover smaller, expanded larger).
                width: root.shown ? root.shown.sizeFor(modelData).width : 0
                height: root.shown ? root.shown.sizeFor(modelData).height : 0
                scale: root.scaleFor(modelData)
                // Fade-in starts late so the old view is gone first.
                opacity: Math.max(0, (vis - 0.35) / 0.65) * root.swapOpacity
                visible: opacity > 0.01
                active: root.shown !== null && (on || vis > 0.01)
                sourceComponent: root.shown ? root.shown.viewFor(modelData) : null
            }
        }
    }

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }
    TapHandler {
        onTapped: root.clicked()
    }
}
