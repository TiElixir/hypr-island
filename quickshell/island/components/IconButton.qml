import QtQuick
import "../core"

// Glyph button (Nerd Font icon) with a soft hover disc.
Item {
    id: root

    property string glyph: ""
    property real size: 32
    property real glyphSize: 18
    property color color: Theme.fg
    property bool enabled: true
    signal clicked

    implicitWidth: size
    implicitHeight: size

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: Theme.fg
        opacity: mouse.pressed ? 0.22 : mouse.containsMouse ? 0.12 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: 100
            }
        }
    }
    Text {
        anchors.centerIn: parent
        text: root.glyph
        color: root.color
        opacity: root.enabled ? 1 : 0.35
        font.family: Theme.font
        font.pixelSize: root.glyphSize
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
