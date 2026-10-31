import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.core
import qs.components

// The Settings panel: a centered, rounded overlay in the island's own style.
// It lives on the layer-shell overlay (no Hyprland window rules needed), is only
// mapped while open, and every change is written to config.json straight away.
// Open: `island-ctl settings [tab]`, SUPER+ALT+S, or the gear in the clock.
// Close: Esc, the close button, or a click outside the panel.
Scope {
    id: root

    property var screen: null
    required property var moduleManager

    property bool open: false
    property string tab: "general"
    property real reveal: open ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: 170
            easing.type: Easing.OutCubic
        }
    }

    readonly property var tabs: [
        { id: "general", label: "General" },
        { id: "modules", label: "Modules" },
        { id: "hooks", label: "Hooks" },
        { id: "appearance", label: "Appearance" },
        { id: "advanced", label: "Advanced" }
    ]

    Connections {
        target: UiBus
        function onSettingsRequested(t) {
            const known = root.tabs.some(x => x.id === t);
            if (root.open && (t === "" || t === root.tab)) {
                root.open = false;
                return;
            }
            if (known)
                root.tab = t;
            root.open = true;
        }
    }

    PanelWindow {
        id: win

        screen: root.screen
        visible: root.screen !== null && (root.open || root.reveal > 0.01)
        color: "transparent"
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "island-settings"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        // Dim the screen; a click outside the panel closes it.
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.4 * root.reveal)
            MouseArea {
                anchors.fill: parent
                onClicked: root.open = false
            }
        }

        FocusScope {
            id: keys
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: root.open = false

            Rectangle {
                id: panel
                anchors.centerIn: parent
                width: Math.min(960, win.width - 80)
                height: Math.min(660, win.height - 100)
                radius: 26
                color: Qt.alpha(Theme.bg, 0.97)
                border.width: 1
                border.color: Theme.hairline
                opacity: root.reveal
                scale: 0.96 + 0.04 * root.reveal

                // Swallow clicks so they don't reach the backdrop.
                MouseArea {
                    anchors.fill: parent
                }

                // ---- sidebar ----------------------------------------------------
                Item {
                    id: side
                    width: 210
                    height: parent.height

                    Text {
                        x: 28
                        y: 26
                        text: "Island"
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize + 6
                        font.weight: Font.DemiBold
                    }
                    Text {
                        x: 28
                        y: 54
                        text: "Settings"
                        color: Theme.fgDim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 2
                    }
                    Column {
                        x: 14
                        y: 96
                        width: parent.width - 28
                        spacing: 4
                        Repeater {
                            model: root.tabs
                            delegate: Rectangle {
                                id: tabBtn
                                required property var modelData
                                readonly property bool on: root.tab === modelData.id
                                width: parent.width
                                height: 38
                                radius: 12
                                color: on ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(1, 1, 1, tm.containsMouse ? 0.05 : 0)
                                Rectangle {
                                    visible: tabBtn.on
                                    x: 0
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 3
                                    height: 18
                                    radius: 2
                                    color: Theme.accent
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: 18
                                    text: tabBtn.modelData.label
                                    color: tabBtn.on ? Theme.fg : Theme.fgDim
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontSize
                                    font.weight: tabBtn.on ? Font.DemiBold : Font.Normal
                                }
                                MouseArea {
                                    id: tm
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.tab = tabBtn.modelData.id
                                }
                            }
                        }
                    }
                    Text {
                        x: 28
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 24
                        text: root.moduleManager.all.length + " modules active"
                        color: Theme.fgDim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 3
                    }
                }
                Rectangle {
                    x: side.width
                    width: 1
                    height: parent.height
                    color: Theme.hairline
                }

                // ---- content ----------------------------------------------------
                Text {
                    x: side.width + 32
                    y: 24
                    text: {
                        for (const t of root.tabs)
                            if (t.id === root.tab)
                                return t.label;
                        return "";
                    }
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize + 6
                    font.weight: Font.DemiBold
                }
                IconButton {
                    anchors.right: parent.right
                    anchors.rightMargin: 18
                    y: 18
                    size: 34
                    glyphSize: 18
                    glyph: String.fromCodePoint(0xF0156)
                    onClicked: root.open = false
                }
                Loader {
                    id: content
                    x: side.width + 32
                    y: 74
                    width: parent.width - side.width - 56
                    height: parent.height - 74 - 20
                    active: root.open
                    sourceComponent: root.tab === "modules" ? modulesC : root.tab === "hooks" ? hooksC : root.tab === "appearance" ? appearanceC : root.tab === "advanced" ? advancedC : generalC
                }
                Component {
                    id: generalC
                    GeneralTab {}
                }
                Component {
                    id: modulesC
                    ModulesTab {
                        manager: root.moduleManager
                    }
                }
                Component {
                    id: hooksC
                    HooksTab {}
                }
                Component {
                    id: appearanceC
                    AppearanceTab {}
                }
                Component {
                    id: advancedC
                    AdvancedTab {
                        manager: root.moduleManager
                    }
                }
            }
        }
    }
}
