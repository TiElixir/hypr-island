import QtQuick
import Quickshell.Widgets
import "../core"

// Round album art with an optional progress ring around it.
Item {
    id: root

    property string source: ""
    property real progress: 0
    property bool showRing: true
    property color ringColor: Theme.accent
    property real ring: 2

    implicitWidth: 24
    implicitHeight: 24

    ProgressRing {
        anchors.fill: parent
        visible: root.showRing
        progress: root.progress
        lineWidth: root.ring
        color: root.ringColor
    }

    ClippingRectangle {
        anchors.fill: parent
        anchors.margins: root.showRing ? root.ring + 1.5 : 0
        radius: width / 2
        color: Theme.track

        Image {
            anchors.fill: parent
            source: root.source
            asynchronous: true
            fillMode: Image.PreserveAspectCrop
            sourceSize: Qt.size(128, 128)
        }
    }
}
