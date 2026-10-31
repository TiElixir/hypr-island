import QtQuick
import QtQuick.Shapes
import Quickshell.Widgets

// The visual pill. Width, height and corner shape are one spring-animated
// silhouette. Collapsed and hover it is a floating rounded pill; expanded it
// attaches to the top edge of the screen: the upper corners turn into concave
// flares that ease out of the edge, and the lower corners stay rounded.
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
    readonly property size target: {
        if (!act)
            return Qt.size(0, 0);
        const s = act.sizeFor(mode);
        return mode === "expanded" ? Qt.size(s.width * expandedScale, s.height * expandedScale) : s;
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

    // 0: floating pill in the bar. 1: flush with the top edge, with flares.
    property real attach: mode === "expanded" ? 1 : 0
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
    // How far the flares currently reach outside the body.
    readonly property real flareExtent: flareMax * attach
    // Top corner: a convex round (radius rb) blends into a concave flare
    // (radius flareMax) as `attach` goes 0 -> 1.
    readonly property real corner: Math.min(rb, height / 2 - 1)
    readonly property real ca: corner * (1 - attach) - flareMax * attach   // x offset of the corner start from the body edge
    readonly property real cq: corner * (1 - attach) + flareMax * attach   // y extent of the corner
    readonly property real k1: 0.4477                                       // 1 - the usual bezier circle constant

    onActChanged: {
        if (shown === null || act === null)
            shown = act;
        else if (shown !== act)
            swapAnim.restart();
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

    // One path for the whole outline, so there are no seams and the
    // translucent fill is never composited twice.
    Shape {
        id: silhouette
        x: -root.flareMax
        y: 0
        width: root.width + 2 * root.flareMax
        height: root.height
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            id: outline
            readonly property real ox: root.flareMax
            readonly property real w: root.width
            readonly property real h: root.height
            readonly property real rb: root.rb
            readonly property real a: root.ca
            readonly property real q: root.cq
            readonly property real k: root.k1

            fillColor: Qt.alpha(Theme.bg, Config.cfg.colors.bgAlpha)
            strokeColor: Qt.rgba(1, 1, 1, 0.07 * (1 - root.attach))
            strokeWidth: 1

            startX: ox + a
            startY: 0
            PathLine {
                x: outline.ox + outline.w - outline.a
                y: 0
            }
            PathCubic {
                control1X: outline.ox + outline.w - outline.k * outline.a
                control1Y: 0
                control2X: outline.ox + outline.w
                control2Y: outline.k * outline.q
                x: outline.ox + outline.w
                y: outline.q
            }
            PathLine {
                x: outline.ox + outline.w
                y: outline.h - outline.rb
            }
            PathCubic {
                control1X: outline.ox + outline.w
                control1Y: outline.h - outline.k * outline.rb
                control2X: outline.ox + outline.w - outline.k * outline.rb
                control2Y: outline.h
                x: outline.ox + outline.w - outline.rb
                y: outline.h
            }
            PathLine {
                x: outline.ox + outline.rb
                y: outline.h
            }
            PathCubic {
                control1X: outline.ox + outline.k * outline.rb
                control1Y: outline.h
                control2X: outline.ox
                control2Y: outline.h - outline.k * outline.rb
                x: outline.ox
                y: outline.h - outline.rb
            }
            PathLine {
                x: outline.ox
                y: outline.q
            }
            PathCubic {
                control1X: outline.ox
                control1Y: outline.k * outline.q
                control2X: outline.ox + outline.k * outline.a
                control2Y: 0
                x: outline.ox + outline.a
                y: 0
            }
        }
    }

    // Content is clipped to the body: flat on top once attached, rounded below.
    ClippingRectangle {
        id: body
        anchors.fill: parent
        color: "transparent"
        topLeftRadius: root.corner * (1 - root.attach)
        topRightRadius: root.corner * (1 - root.attach)
        bottomLeftRadius: root.rb
        bottomRightRadius: root.rb

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
                // Laid out at the design size, scaled up when expanded.
                width: root.shown ? root.shown.sizeFor(modelData).width : 0
                height: root.shown ? root.shown.sizeFor(modelData).height : 0
                scale: modelData === "expanded" ? root.expandedScale : 1
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
