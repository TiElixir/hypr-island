import QtQuick
import qs.core
import qs.components

// Shows which window just got focus, and lists every open window when expanded.
// Built on the Windows service, so it is event driven: no timers run until a
// focus change arrives, and only for the length of the flash.
Activity {
    id: root

    accent: "#7aa2f7"
    property var last: null
    property bool flashing: false
    active: flashing && last !== null

    collapsedSize: Qt.size(Math.min(300, Math.round(50 + metrics.width)), Config.cfg.sizes.collapsedHeight + 2)
    hoverSize: Qt.size(340, 50)
    expandedSize: Qt.size(400, Math.min(330, 56 + Math.max(1, Windows.count) * 30))

    TextMetrics {
        id: metrics
        text: root.summary
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 1
    }
    readonly property string summary: {
        if (!last)
            return "";
        const app = last["class"] || "window";
        return option("showTitle") === true && last.title ? app + " · " + last.title : app;
    }

    function flash(w) {
        if (!w || !w["class"])
            return;
        const ignore = option("ignoreClasses") || [];
        if (ignore.indexOf(String(w["class"]).toLowerCase()) >= 0)
            return;
        last = w;
        flashing = true;
        off.interval = Number(option("flashMs"));
        off.restart();
    }
    onEventReceived: (name, data) => flash(data)
    Timer {
        id: off
        onTriggered: root.flashing = false
    }

    collapsedView: Component {
        Item {
            Text {
                anchors.centerIn: parent
                width: parent.width - 24
                horizontalAlignment: Text.AlignHCenter
                text: root.summary
                elide: Text.ElideRight
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 1
            }
        }
    }
    hoverView: Component {
        Item {
            Column {
                anchors.centerIn: parent
                width: parent.width - 36
                spacing: 2
                Text {
                    width: parent.width
                    text: root.last ? root.last["class"] : ""
                    elide: Text.ElideRight
                    color: root.accent
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                    font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width
                    text: root.last ? root.last.title : ""
                    elide: Text.ElideRight
                    color: Theme.fgDim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 3
                }
            }
        }
    }
    expandedView: Component {
        Item {
            Text {
                x: 20
                y: 14
                text: "Windows · " + Windows.count
                color: Theme.fgDim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 3
                font.weight: Font.DemiBold
            }
            Column {
                x: 12
                y: 38
                width: parent.width - 24
                Repeater {
                    model: Windows.list.slice(0, 9)
                    delegate: Item {
                        id: row
                        required property var modelData
                        width: parent.width
                        height: 30
                        readonly property bool isFocused: Windows.focused !== null && Windows.focused.address === modelData.address
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 1
                            radius: 9
                            color: Theme.fg
                            opacity: row.isFocused ? 0.1 : 0
                        }
                        Text {
                            x: 12
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 70
                            text: row.modelData["class"] + " · " + row.modelData.title
                            elide: Text.ElideRight
                            color: row.isFocused ? Theme.fg : Theme.fgDim
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 2
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: "ws " + row.modelData.workspace
                            color: Theme.fgDim
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 3
                        }
                    }
                }
            }
        }
    }
}
