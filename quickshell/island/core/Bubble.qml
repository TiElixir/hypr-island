import QtQuick

// The runner-up activity as a small round bubble beside the pill (Apple's
// split island). Click swaps it with the main pill.
Item {
    id: root

    property var act: null
    property bool shown: false
    signal clicked

    readonly property real diameter: 26
    width: diameter
    height: diameter
    scale: shown ? 1 : 0.4
    opacity: shown ? 1 : 0
    visible: opacity > 0.01

    Behavior on scale {
        SpringAnimation {
            spring: Config.cfg.spring.spring
            damping: Config.cfg.spring.damping
            epsilon: 0.01
        }
    }
    Behavior on opacity {
        NumberAnimation {
            duration: 150
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: Qt.alpha(Theme.bg, Config.cfg.colors.bgAlpha)
        border.width: 1
        border.color: Theme.hairline
    }
    Loader {
        anchors.centerIn: parent
        width: root.diameter
        height: root.diameter
        sourceComponent: root.act ? root.act.bubbleView : null
    }
    HoverHandler {
        cursorShape: Qt.PointingHandCursor
    }
    TapHandler {
        onTapped: root.clicked()
    }
}
