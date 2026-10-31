import QtQuick
import Quickshell

// The clock. It is not part of the island: it is always there, in the middle
// of the bar when the island is idle, and slides to the right of the island
// while the island is showing something. It stays a plain time; right-click
// opens Settings. It hides while a window is fullscreen on this workspace.
Item {
    id: root

    readonly property var cfg: Config.cfg.clock
    visible: cfg.enabled === true && !(cfg.hideInFullscreen === true && Windows.workspaceFullscreen)

    SystemClock {
        id: sc
        enabled: root.visible
        precision: String(root.cfg.format).indexOf("s") >= 0 ? SystemClock.Seconds : SystemClock.Minutes
    }

    implicitWidth: Math.ceil(label.implicitWidth) + 16
    implicitHeight: Config.cfg.sizes.collapsedHeight
    width: implicitWidth
    height: implicitHeight

    Text {
        id: label
        anchors.centerIn: parent
        text: Qt.formatDateTime(sc.date, String(root.cfg.format))
        color: Theme.fg
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
        font.weight: Font.Medium
    }

    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: UiBus.settingsRequested("")
    }
}
