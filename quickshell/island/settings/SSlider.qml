import QtQuick
import qs.core

// Numeric slider with a value readout. Emits moved(v) while dragging;
// the value is snapped to `step`.
Item {
    id: root

    property real from: 0
    property real to: 100
    property real step: 1
    property real value: 0
    property string unit: ""
    property bool integer: true
    signal moved(real v)

    implicitWidth: 240
    implicitHeight: 28

    readonly property real frac: to > from ? Math.max(0, Math.min(1, (value - from) / (to - from))) : 0

    function snap(v) {
        const s = step > 0 ? step : 1;
        const n = Math.round((v - from) / s) * s + from;
        const c = Math.max(from, Math.min(to, n));
        return integer ? Math.round(c) : Math.round(c * 1000) / 1000;
    }
    function format(v) {
        return (integer ? String(Math.round(v)) : String(Math.round(v * 100) / 100)) + (unit ? " " + unit : "");
    }

    Text {
        id: label
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 64
        horizontalAlignment: Text.AlignRight
        text: root.format(root.value)
        color: Theme.fg
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 2
    }
    Item {
        id: area
        anchors.left: parent.left
        anchors.right: label.left
        anchors.rightMargin: 12
        height: parent.height
        Rectangle {
            id: track
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 4
            radius: 2
            color: Qt.rgba(1, 1, 1, 0.16)
            Rectangle {
                width: parent.width * root.frac
                height: parent.height
                radius: 2
                color: Theme.accent
            }
        }
        Rectangle {
            width: mouse.pressed ? 16 : 14
            height: width
            radius: width / 2
            color: Theme.fg
            anchors.verticalCenter: parent.verticalCenter
            x: track.width * root.frac - width / 2
        }
        MouseArea {
            id: mouse
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            function update() {
                const v = root.snap(root.from + (root.to - root.from) * Math.max(0, Math.min(1, mouseX / width)));
                if (v !== root.value)
                    root.moved(v);
            }
            onPressed: update()
            onPositionChanged: if (pressed)
                update()
        }
    }
}
