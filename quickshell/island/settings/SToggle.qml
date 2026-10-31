import QtQuick
import qs.core

// On/off switch. Controlled: bind `checked`, react to toggled().
Item {
    id: root

    property bool checked: false
    signal toggled(bool value)

    implicitWidth: 42
    implicitHeight: 24

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.checked ? Theme.accent : Qt.rgba(1, 1, 1, 0.16)
        Behavior on color {
            ColorAnimation {
                duration: 140
            }
        }
        Rectangle {
            id: knob
            width: parent.height - 6
            height: width
            radius: width / 2
            y: 3
            x: root.checked ? parent.width - width - 3 : 3
            color: root.checked ? Theme.bg : Theme.fg
            Behavior on x {
                NumberAnimation {
                    duration: 140
                    easing.type: Easing.OutCubic
                }
            }
        }
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled(!root.checked)
    }
}
