import QtQuick
import qs.core

// One module in the Modules tab: enable, reorder, priority, status, and its
// generated options.
Item {
    id: card

    required property var rec          // record from ModuleManager.modules
    required property var manager
    property bool expanded: false
    signal expandToggled
    property bool isFirst: false
    property bool isLast: false

    readonly property bool broken: rec.error !== ""
    readonly property bool enabled: !broken && manager.enabledOf(rec.id)
    readonly property bool ambient: rec.manifest.ambient === true
    readonly property string status: broken ? "error" : manager.statusOf(rec.id)
    readonly property string sourceStatus: broken ? "" : manager.sourceStatusOf(rec.id)
    readonly property var schema: broken ? [] : (rec.manifest.options || [])

    width: parent ? parent.width : 400
    implicitHeight: head.height + (expanded ? body.implicitHeight + 8 : 0) + 10

    Rectangle {
        anchors.fill: parent
        anchors.bottomMargin: 8
        radius: 16
        color: Qt.rgba(1, 1, 1, card.enabled ? 0.05 : 0.025)
        border.width: 1
        border.color: Theme.hairline
    }

    // ---- header row -----------------------------------------------------------
    Item {
        id: head
        width: parent.width
        height: 62

        Column {
            id: arrows
            visible: !card.ambient && !card.broken
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            Repeater {
                model: [-1, 1]
                delegate: Item {
                    id: arrow
                    required property int modelData
                    readonly property bool usable: modelData < 0 ? !card.isFirst : !card.isLast
                    width: 24
                    height: 20
                    Text {
                        anchors.centerIn: parent
                        text: arrow.modelData < 0 ? "▲" : "▼"
                        font.pixelSize: 11
                        color: arrow.usable ? (am.containsMouse ? Theme.fg : Theme.fgDim) : Qt.rgba(1, 1, 1, 0.12)
                    }
                    MouseArea {
                        id: am
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: arrow.usable
                        cursorShape: Qt.PointingHandCursor
                        onClicked: card.manager.move(card.rec.id, arrow.modelData)
                    }
                }
            }
        }

        SToggle {
            id: toggle
            anchors.left: parent.left
            anchors.leftMargin: 48
            anchors.verticalCenter: parent.verticalCenter
            enabled: !card.broken
            opacity: card.broken ? 0.3 : 1
            checked: card.enabled
            onToggled: v => card.manager.setEnabled(card.rec.id, v)
        }

        Column {
            anchors.left: toggle.right
            anchors.leftMargin: 16
            anchors.right: right.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Row {
                spacing: 8
                Text {
                    text: card.rec.name
                    color: card.enabled ? Theme.fg : Theme.fgDim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                    font.weight: Font.DemiBold
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: tag.implicitWidth + 12
                    height: 17
                    radius: 8
                    color: Qt.rgba(1, 1, 1, 0.09)
                    Text {
                        id: tag
                        anchors.centerIn: parent
                        text: card.rec.builtin ? "built-in" : "yours"
                        color: Theme.fgDim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 5
                    }
                }
            }
            Text {
                width: parent.width
                text: card.broken ? card.rec.error : card.rec.description
                elide: Text.ElideRight
                color: card.broken ? Theme.needsInput : Theme.fgDim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 3
            }
        }

        Row {
            id: right
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                Row {
                    anchors.right: parent.right
                    spacing: 6
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 8
                        height: 8
                        radius: 4
                        color: card.status === "live" ? Theme.done : card.status === "error" ? Theme.needsInput : card.status === "idle" ? Theme.running : Qt.rgba(1, 1, 1, 0.25)
                    }
                    Text {
                        text: card.status
                        color: Theme.fgDim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 3
                    }
                }
                Text {
                    visible: card.sourceStatus !== ""
                    anchors.right: parent.right
                    text: "script: " + card.sourceStatus
                    color: card.sourceStatus.indexOf("error") === 0 ? Theme.needsInput : Theme.fgDim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 4
                }
            }

            Column {
                visible: !card.broken
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "priority"
                    color: Theme.fgDim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 5
                }
                STextField {
                    width: 58
                    height: 26
                    numeric: true
                    enabled: !card.ambient
                    opacity: card.ambient ? 0.5 : 1
                    text: String(card.manager.priorityOf(card.rec.id))
                    onCommitted: v => {
                        const n = Number(v);
                        if (!isNaN(n))
                            card.manager.setPriority(card.rec.id, n);
                    }
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: !card.broken && card.schema.length > 0
                text: card.expanded ? "⌃" : "⌄"
                color: Theme.fgDim
                font.pixelSize: 20
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -8
                    cursorShape: Qt.PointingHandCursor
                    onClicked: card.expandToggled()
                }
            }
        }
        MouseArea {
            z: -1
            anchors.fill: parent
            onClicked: if (!card.broken && card.schema.length > 0)
                card.expandToggled()
        }
    }

    // ---- generated options ----------------------------------------------------
    Column {
        id: body
        visible: card.expanded
        anchors.top: head.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 20
        anchors.rightMargin: 14
        Repeater {
            model: card.expanded ? card.schema : []
            delegate: SettingRow {
                id: opt
                required property var modelData
                width: body.width
                path: ["modules", card.rec.id, "options", modelData.key]
                title: modelData.label || modelData.key
                description: modelData.description || ""
                type: modelData.type || "string"
                min: modelData.min
                max: modelData.max
                step: modelData.step
                unit: modelData.unit || ""
                choices: modelData.choices || []
                fallback: modelData.default
            }
        }
        Item {
            width: 1
            height: 44
            SButton {
                anchors.verticalCenter: parent.verticalCenter
                text: "Reset module to defaults"
                onClicked: card.manager.resetModule(card.rec.id)
            }
        }
    }
}
