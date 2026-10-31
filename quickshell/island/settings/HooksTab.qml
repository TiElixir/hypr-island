import QtQuick
import Quickshell
import qs.core

TabPage {
    id: tab

    // Record events only while this tab is on screen.
    Component.onCompleted: Events.recording = true
    Component.onDestruction: Events.recording = false

    SSection {
        title: "Event hooks"
        subtitle: "Executables in " + Config.tilde(Hooks.dir) + "/<event>/ run whenever that event fires. They get the payload as JSON on stdin, in $ISLAND_DATA, and as flat $ISLAND_<FIELD> variables."
    }
    SettingRow {
        path: ["hooks", "enabled"]
        title: "Run hooks"
        type: "bool"
    }
    SettingRow {
        path: ["hooks", "timeoutSec"]
        title: "Timeout"
        description: "A hook is killed after this long."
        type: "int"
        min: 1
        max: 120
        unit: "s"
    }
    SettingRow {
        path: ["hooks", "minIntervalMs"]
        title: "Minimum gap per script"
        description: "The same script is not started again inside this window."
        type: "int"
        min: 0
        max: 5000
        step: 50
        unit: "ms"
    }
    Item {
        width: 1
        height: 48
        SButton {
            anchors.verticalCenter: parent.verticalCenter
            text: "Rescan hooks"
            onClicked: Hooks.rescan()
        }
    }

    Text {
        visible: Hooks.scripts.length === 0
        width: parent.width
        bottomPadding: 12
        text: "No hook scripts found. Example: " + Config.tilde(Hooks.dir) + "/claude.state/10-notify.sh (chmod +x)."
        wrapMode: Text.WordWrap
        color: Theme.fgDim
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 2
    }
    Repeater {
        model: Hooks.scripts
        delegate: Item {
            id: hook
            required property var modelData
            width: tab.width - 22
            height: 50
            readonly property string failure: Hooks.failures[modelData.key] || ""
            SToggle {
                id: ht
                anchors.verticalCenter: parent.verticalCenter
                checked: !hook.modelData.disabled
                onToggled: v => {
                    const off = (Config.cfg.hooks.disabled || []).filter(k => k !== hook.modelData.key);
                    if (!v)
                        off.push(hook.modelData.key);
                    Config.set(["hooks", "disabled"], off);
                }
            }
            Column {
                anchors.left: ht.right
                anchors.leftMargin: 14
                anchors.right: test.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Text {
                    width: parent.width
                    text: hook.modelData.event + "  ›  " + hook.modelData.name
                    elide: Text.ElideRight
                    color: hook.modelData.disabled ? Theme.fgDim : Theme.fg
                    font.family: "monospace"
                    font.pixelSize: Theme.fontSize - 2
                }
                Text {
                    visible: hook.failure !== ""
                    width: parent.width
                    text: "last run failed: " + hook.failure
                    elide: Text.ElideRight
                    color: Theme.needsInput
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 4
                }
            }
            SButton {
                id: test
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "Test"
                onClicked: Hooks.test(hook.modelData)
            }
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Theme.hairline
                opacity: 0.6
            }
        }
    }

    SSection {
        title: "Events you can hook"
        subtitle: "Name a folder after one of these. Modules add their own (manifest \"emits\")."
    }
    Repeater {
        model: Object.keys(Events.catalog).sort()
        delegate: Column {
            id: ev
            required property string modelData
            width: tab.width - 22
            topPadding: 7
            bottomPadding: 7
            spacing: 1
            Text {
                text: ev.modelData
                color: Theme.accent
                font.family: "monospace"
                font.pixelSize: Theme.fontSize - 2
            }
            Text {
                width: parent.width
                text: Events.catalog[ev.modelData].description + (Events.catalog[ev.modelData].fields ? "   ·   " + Events.catalog[ev.modelData].fields : "")
                wrapMode: Text.WordWrap
                color: Theme.fgDim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 3
            }
        }
    }

    SSection {
        title: "Live events"
        subtitle: "The latest events while this tab is open. Useful when writing a hook."
    }
    Text {
        visible: Events.recent.length === 0
        topPadding: 6
        text: "Waiting for events…"
        color: Theme.fgDim
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 2
    }
    Repeater {
        model: Events.recent.slice(-14).reverse()
        delegate: Text {
            required property var modelData
            width: tab.width - 22
            topPadding: 3
            text: Qt.formatTime(new Date(modelData.t), "HH:mm:ss") + "  " + modelData.name + "  " + JSON.stringify(modelData.data)
            elide: Text.ElideRight
            color: Theme.fgDim
            font.family: "monospace"
            font.pixelSize: Theme.fontSize - 3
        }
    }
}
