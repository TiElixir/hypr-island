import QtQuick
import Quickshell
import qs.core

TabPage {
    id: tab

    required property var manager
    property bool confirmReset: false

    Timer {
        id: confirmTimer
        interval: 4000
        onTriggered: tab.confirmReset = false
    }

    SSection {
        title: "Files"
    }
    Column {
        width: parent.width
        topPadding: 8
        bottomPadding: 8
        spacing: 6
        Repeater {
            model: [
                { k: "Config", v: Config.path },
                { k: "Your modules", v: manager.userDir },
                { k: "Built-in modules", v: manager.builtinDir },
                { k: "Hooks", v: Hooks.dir },
                { k: "State", v: Feed.stateDir }
            ]
            delegate: Row {
                required property var modelData
                spacing: 12
                Text {
                    width: 120
                    text: modelData.k
                    color: Theme.fgDim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 2
                }
                Text {
                    text: modelData.v
                    color: Theme.fg
                    font.family: "monospace"
                    font.pixelSize: Theme.fontSize - 3
                }
            }
        }
    }

    SSection {
        title: "Actions"
    }
    Flow {
        width: parent.width
        topPadding: 12
        bottomPadding: 12
        spacing: 8
        SButton {
            text: "Rescan modules and hooks"
            onClicked: {
                tab.manager.rescan();
                Hooks.rescan();
            }
        }
        SButton {
            text: "Open config in editor"
            onClicked: Quickshell.execDetached(["xdg-open", Config.path])
        }
        SButton {
            text: "Restart island"
            onClicked: Quickshell.execDetached([Feed.ctl, "restart"])
        }
        SButton {
            danger: tab.confirmReset
            text: tab.confirmReset ? "Click again to reset everything" : "Reset all settings"
            onClicked: {
                if (tab.confirmReset) {
                    Config.resetAll();
                    tab.confirmReset = false;
                } else {
                    tab.confirmReset = true;
                    confirmTimer.restart();
                }
            }
        }
    }
    Text {
        width: parent.width
        text: "Reset removes every override from config.json. Modules, hooks and your files are not touched."
        wrapMode: Text.WordWrap
        color: Theme.fgDim
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 3
    }
}
