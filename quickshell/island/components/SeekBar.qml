import QtQuick
import "../core"

// Thin progress bar. When `seekable`, click or drag to seek: seekTo(fraction)
// is emitted on release so the player is only asked once.
Item {
    id: root

    property real value: 0
    property bool seekable: false
    property bool indeterminate: false
    property color color: Theme.accent
    readonly property bool dragging: mouse.pressed
    property real scrub: 0
    signal seekTo(real fraction)

    readonly property real shown: dragging ? scrub : Math.max(0, Math.min(1, value))

    implicitHeight: 14

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: mouse.containsMouse || root.dragging ? 6 : 4
        radius: height / 2
        color: Theme.track
        Behavior on height {
            NumberAnimation {
                duration: 120
            }
        }

        Rectangle {
            width: root.indeterminate ? parent.width : parent.width * root.shown
            height: parent.height
            radius: parent.radius
            color: root.color
            opacity: root.indeterminate ? 0.35 : 1
            // Smooths the 1 Hz position ticks; off while scrubbing.
            Behavior on width {
                enabled: !root.dragging
                NumberAnimation {
                    duration: 900
                    easing.type: Easing.Linear
                }
            }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.seekable
        cursorShape: root.seekable ? Qt.PointingHandCursor : Qt.ArrowCursor
        function frac() {
            return Math.max(0, Math.min(1, mouseX / width));
        }
        onPressed: root.scrub = frac()
        onPositionChanged: if (pressed)
            root.scrub = frac()
        onReleased: root.seekTo(frac())
    }
}
