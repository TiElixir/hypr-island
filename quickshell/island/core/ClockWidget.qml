import QtQuick
import Quickshell

// The clock. It is not part of the island: it is always there, in the middle
// of the bar when the island is idle, and slides to the right of the island
// while the island is showing something. Hover shows the date; right-click
// opens Settings.
Item {
    id: root

    readonly property var cfg: Config.cfg.clock
    visible: cfg.enabled === true

    SystemClock {
        id: sc
        enabled: root.visible
        precision: String(root.cfg.format).indexOf("s") >= 0 ? SystemClock.Seconds : SystemClock.Minutes
    }
    readonly property string timeText: Qt.formatDateTime(sc.date, String(cfg.format))
    readonly property string dateText: Qt.formatDateTime(sc.date, String(cfg.dateFormat))

    readonly property bool hovered: hover.hovered
    implicitWidth: Math.ceil(label.implicitWidth) + 16
    implicitHeight: Config.cfg.sizes.collapsedHeight
    width: implicitWidth
    height: implicitHeight

    Text {
        id: label
        anchors.centerIn: parent
        text: root.hovered ? root.dateText : root.timeText
        color: Theme.fg
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
        font.weight: Font.Medium
    }

    HoverHandler {
        id: hover
    }
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: UiBus.settingsRequested("")
    }
}
