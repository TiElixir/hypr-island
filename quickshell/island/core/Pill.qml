import QtQuick
import Quickshell.Widgets

// The visual pill. Width, height and corner radius are one spring-animated
// shape. Views are laid out at their *target* size and crossfaded inside a
// rounded clip, so text never reflows while the pill morphs.
Item {
    id: root

    property var act: null
    property string mode: "collapsed"

    readonly property bool hovered: hover.hovered
    signal clicked

    // What is actually rendered. Lags `act` by one fade-out when swapping.
    property var shown: null
    property real swapOpacity: 1

    readonly property size target: act ? act.sizeFor(mode) : Qt.size(0, 0)
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

    width: Math.max(10, animW)
    height: Math.max(10, animH)
    x: Math.round((parent.width - width) / 2)
    y: 0
    visible: act !== null

    readonly property bool blended: act !== null && act.ambient && mode === "collapsed"

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

    ClippingRectangle {
        id: body
        anchors.fill: parent
        radius: Math.min(height / 2, Config.cfg.sizes.maxRadius)
        color: root.blended ? "transparent" : Qt.alpha(Theme.bg, Config.cfg.colors.bgAlpha)
        border.width: root.blended ? 0 : 1
        border.color: Theme.hairline

        Behavior on color {
            ColorAnimation {
                duration: 220
            }
        }

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
                width: root.shown ? root.shown.sizeFor(modelData).width : 0
                height: root.shown ? root.shown.sizeFor(modelData).height : 0
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
