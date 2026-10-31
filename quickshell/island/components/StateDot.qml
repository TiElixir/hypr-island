import QtQuick
import "../core"

// Status dot. Bump `pulseKey` to play a short attention pulse (3 beats, then
// static, so it never keeps the GPU busy).
Item {
    id: root

    property color color: Theme.accent
    property real size: 10
    property int pulseKey: 0

    implicitWidth: size
    implicitHeight: size

    onPulseKeyChanged: pulse.restart()

    Rectangle {
        id: halo
        anchors.centerIn: parent
        width: root.size
        height: root.size
        radius: width / 2
        color: root.color
        opacity: 0
    }
    Rectangle {
        id: dot
        anchors.centerIn: parent
        width: root.size
        height: root.size
        radius: width / 2
        color: root.color
        Behavior on color {
            ColorAnimation {
                duration: 200
            }
        }
    }

    SequentialAnimation {
        id: pulse
        loops: 3
        ParallelAnimation {
            NumberAnimation {
                target: halo
                property: "scale"
                from: 1
                to: 2.4
                duration: 520
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: halo
                property: "opacity"
                from: 0.55
                to: 0
                duration: 520
            }
        }
    }
}
