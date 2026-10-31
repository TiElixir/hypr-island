import QtQuick
import "../core"

// An icon given as a string: an image path (starts with "/" or file://) or
// a Nerd Font glyph / emoji. Empty falls back to a plain dot.
Item {
    id: root

    property string source: ""
    property color color: Theme.fg
    property real size: 16

    readonly property bool isImage: source.indexOf("/") === 0 || source.indexOf("file://") === 0

    implicitWidth: size
    implicitHeight: size

    Image {
        anchors.fill: parent
        visible: root.isImage
        source: root.isImage ? (root.source.indexOf("/") === 0 ? "file://" + root.source : root.source) : ""
        asynchronous: true
        fillMode: Image.PreserveAspectFit
        sourceSize: Qt.size(root.size * 2, root.size * 2)
    }
    Text {
        anchors.centerIn: parent
        visible: !root.isImage && root.source !== ""
        text: root.source
        color: root.color
        font.family: Theme.font
        font.pixelSize: root.size
    }
    Rectangle {
        anchors.centerIn: parent
        visible: root.source === ""
        width: root.size * 0.6
        height: width
        radius: width / 2
        color: root.color
    }
}
