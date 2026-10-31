import QtQuick
import Quickshell
import "../core"

// Always-on ambient activity. Collapsed it is just text that blends into the
// bar where the Waybar clock used to be.
Activity {
    id: root

    activityId: "clock"
    priority: 0
    ambient: true
    active: true

    collapsedSize: Qt.size(Config.cfg.clock.collapsedWidth, Config.cfg.sizes.collapsedHeight)
    hoverSize: Qt.size(260, 46)
    expandedSize: Qt.size(340, 110)

    // Wake once a minute unless the format shows seconds.
    SystemClock {
        id: clock
        precision: Config.cfg.clock.format.indexOf("s") >= 0 ? SystemClock.Seconds : SystemClock.Minutes
    }
    readonly property string timeText: Qt.formatDateTime(clock.date, Config.cfg.clock.format)
    readonly property string dateText: Qt.formatDateTime(clock.date, Config.cfg.clock.dateFormat)

    collapsedView: Component {
        Item {
            Text {
                anchors.centerIn: parent
                text: root.timeText
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
                font.weight: Font.Medium
            }
        }
    }

    hoverView: Component {
        Column {
            anchors.centerIn: parent
            spacing: 1
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.timeText
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize + 1
                font.weight: Font.Medium
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.dateText
                color: Theme.fgDim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 2
            }
        }
    }

    expandedView: Component {
        Column {
            anchors.centerIn: parent
            spacing: 4
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.timeText
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: 34
                font.weight: Font.DemiBold
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.dateText
                color: Theme.fgDim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
            }
        }
    }
}
