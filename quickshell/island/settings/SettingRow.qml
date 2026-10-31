import QtQuick
import qs.core

// One setting. Give it a config `path` and a schema; it renders the right
// control, reads the live value, writes through Config and offers a reset to
// default. Used for every module option (from manifest.json) and core setting.
//
//   SettingRow { path: ["layer", "keepOnTop"]; title: "Stay on top"; type: "bool" }
//
// type: bool | int | real | string | enum | color | list
Item {
    id: row

    property var path: []
    property string title: ""
    property string description: ""
    property string type: "string"
    property var min
    property var max
    property var step
    property string unit: ""
    property var choices: []
    // Shown when the config has no value (module options: the manifest default).
    property var fallback

    readonly property var value: {
        const v = Config.get(path);
        return v !== undefined ? v : fallback;
    }
    readonly property bool modified: {
        const _ = Config.user;
        return Config.hasUser(path);
    }
    function write(v) {
        Config.set(path, v);
    }

    width: parent ? parent.width : 400
    implicitHeight: Math.max(52, textCol.implicitHeight + 20, ctl.implicitHeight + 20)

    Column {
        id: textCol
        anchors.left: parent.left
        anchors.right: ctl.left
        anchors.rightMargin: 20
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Text {
            width: parent.width
            text: row.title
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 1
        }
        Text {
            visible: row.description !== ""
            width: parent.width
            text: row.description
            wrapMode: Text.WordWrap
            color: Theme.fgDim
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 3
        }
    }

    Loader {
        id: ctl
        anchors.right: resetBtn.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        width: 280
        sourceComponent: row.type === "bool" ? boolC : (row.type === "int" || row.type === "real") ? (row.min !== undefined && row.max !== undefined ? sliderC : numberC) : row.type === "enum" ? enumC : row.type === "color" ? colorC : row.type === "list" ? listC : textC
    }

    // Reset to default, only offered when the user changed it.
    Item {
        id: resetBtn
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 24
        height: 24
        opacity: row.modified ? 1 : 0
        visible: opacity > 0
        Behavior on opacity {
            NumberAnimation {
                duration: 120
            }
        }
        Text {
            anchors.centerIn: parent
            text: "↺"
            color: rma.containsMouse ? Theme.fg : Theme.fgDim
            font.family: Theme.font
            font.pixelSize: Theme.fontSize + 2
        }
        MouseArea {
            id: rma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Config.reset(row.path)
        }
    }

    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: Theme.hairline
        opacity: 0.6
    }

    Component {
        id: boolC
        SToggle {
            anchors.right: parent.right
            checked: row.value === true
            onToggled: v => row.write(v)
        }
    }
    Component {
        id: sliderC
        SSlider {
            width: parent.width
            from: Number(row.min)
            to: Number(row.max)
            step: row.step !== undefined ? Number(row.step) : (row.type === "int" ? 1 : (Number(row.max) - Number(row.min)) / 100)
            integer: row.type === "int"
            unit: row.unit
            value: Number(row.value)
            onMoved: v => row.write(v)
        }
    }
    Component {
        id: numberC
        STextField {
            width: 140
            anchors.right: parent.right
            numeric: true
            text: String(row.value)
            onCommitted: v => {
                const n = Number(v);
                if (!isNaN(n))
                    row.write(row.type === "int" ? Math.round(n) : n);
            }
        }
    }
    Component {
        id: textC
        STextField {
            width: parent.width
            text: row.value === undefined || row.value === null ? "" : String(row.value)
            onCommitted: v => row.write(v)
        }
    }
    Component {
        id: enumC
        SChoice {
            width: parent.width
            model: row.choices
            current: row.value
            onPicked: v => row.write(v)
        }
    }
    Component {
        id: colorC
        STextField {
            width: parent.width
            mono: true
            readonly property bool valid: /^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(String(row.value))
            text: String(row.value)
            swatch: valid ? Qt.color(String(row.value)) : "transparent"
            onCommitted: v => {
                if (/^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(v))
                    row.write(v);
            }
        }
    }
    Component {
        id: listC
        STextField {
            width: parent.width
            placeholder: "comma separated"
            text: Array.isArray(row.value) ? row.value.join(", ") : ""
            onCommitted: v => row.write(v.split(",").map(x => x.trim()).filter(x => x.length > 0))
        }
    }
}
