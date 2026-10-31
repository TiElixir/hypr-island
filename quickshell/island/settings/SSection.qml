import QtQuick
import qs.core

Item {
    id: root

    property string title: ""
    property string subtitle: ""

    width: parent ? parent.width : 400
    implicitHeight: col.implicitHeight + 14

    Column {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 4
        spacing: 3
        Text {
            text: root.title.toUpperCase()
            color: Theme.accent
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 3
            font.weight: Font.DemiBold
            font.letterSpacing: 1
        }
        Text {
            visible: root.subtitle !== ""
            width: parent.width
            text: root.subtitle
            wrapMode: Text.WordWrap
            color: Theme.fgDim
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 3
        }
        Rectangle {
            width: parent.width
            height: 1
            color: Theme.hairline
        }
    }
}
