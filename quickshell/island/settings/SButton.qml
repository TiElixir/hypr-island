import QtQuick
import qs.core

Rectangle {
    id: root

    property string text: ""
    property bool danger: false
    property bool primary: false
    signal clicked

    implicitWidth: label.implicitWidth + 28
    implicitHeight: 30
    radius: 15
    color: {
        const base = danger ? Theme.needsInput : primary ? Theme.accent : Theme.fg;
        const a = primary || danger ? (ma.pressed ? 0.9 : ma.containsMouse ? 1 : 0.85) : (ma.pressed ? 0.22 : ma.containsMouse ? 0.16 : 0.1);
        return Qt.rgba(base.r, base.g, base.b, a);
    }
    Behavior on color {
        ColorAnimation {
            duration: 100
        }
    }
    Text {
        id: label
        anchors.centerIn: parent
        text: root.text
        color: root.primary || root.danger ? Theme.bg : Theme.fg
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 2
        font.weight: Font.Medium
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
