import QtQuick
import qs.core

// Single-line text box. Commits on Enter or when focus leaves; Esc reverts.
Item {
    id: root

    property string text: ""
    property string placeholder: ""
    property bool numeric: false
    property bool mono: false
    property color swatch: "transparent"
    signal committed(string value)

    implicitWidth: 240
    implicitHeight: 30

    Rectangle {
        anchors.fill: parent
        radius: 9
        color: Qt.rgba(1, 1, 1, input.activeFocus ? 0.1 : 0.06)
        border.width: 1
        border.color: input.activeFocus ? Theme.accent : Theme.hairline
        Rectangle {
            visible: root.swatch.a > 0
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: 14
            height: 14
            radius: 7
            color: root.swatch
            border.width: 1
            border.color: Theme.hairline
        }
        TextInput {
            id: input
            anchors.fill: parent
            anchors.leftMargin: root.swatch.a > 0 ? 30 : 10
            anchors.rightMargin: 10
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            selectByMouse: true
            color: Theme.fg
            selectionColor: Theme.accent
            selectedTextColor: Theme.bg
            font.family: root.mono ? "monospace" : Theme.font
            font.pixelSize: Theme.fontSize - 2
            inputMethodHints: root.numeric ? Qt.ImhFormattedNumbersOnly : Qt.ImhNone
            text: root.text
            onEditingFinished: {
                if (text !== root.text)
                    root.committed(text);
            }
            Keys.onEscapePressed: event => {
                text = root.text;
                focus = false;
                event.accepted = true;
            }
        }
        Text {
            visible: input.text === "" && !input.activeFocus
            anchors.left: parent.left
            anchors.leftMargin: root.swatch.a > 0 ? 30 : 10
            anchors.verticalCenter: parent.verticalCenter
            text: root.placeholder
            color: Theme.fgDim
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 2
        }
    }
    // Keep the box in step when the value changes from elsewhere.
    onTextChanged: if (!input.activeFocus)
        input.text = text
}
