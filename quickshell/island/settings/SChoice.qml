import QtQuick
import qs.core

// Pick one of several values, shown as chips. model: ["a","b"] or
// [{ value: "a", label: "Nice A" }].
Item {
    id: root

    property var model: []
    property var current: ""
    signal picked(var value)

    implicitWidth: 240
    implicitHeight: flow.implicitHeight

    function valueOf(m) {
        return typeof m === "object" ? m.value : m;
    }
    function labelOf(m) {
        return typeof m === "object" ? (m.label !== undefined ? m.label : String(m.value)) : String(m);
    }

    Flow {
        id: flow
        anchors.right: parent.right
        width: parent.width
        layoutDirection: Qt.RightToLeft
        spacing: 6
        Repeater {
            model: root.model
            delegate: Rectangle {
                id: chip
                required property var modelData
                readonly property bool on: root.valueOf(modelData) === root.current
                height: 28
                width: txt.implicitWidth + 24
                radius: 14
                color: on ? Theme.accent : Qt.rgba(1, 1, 1, ma.containsMouse ? 0.14 : 0.08)
                Text {
                    id: txt
                    anchors.centerIn: parent
                    text: root.labelOf(chip.modelData)
                    color: chip.on ? Theme.bg : Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 2
                }
                MouseArea {
                    id: ma
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.picked(root.valueOf(chip.modelData))
                }
            }
        }
    }
}
