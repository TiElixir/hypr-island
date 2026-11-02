import QtQuick
import qs.core

TabPage {
    id: tab

    required property var manager

    // Keep the list stable while options change: rebuild only when the order
    // or the set of modules actually changes, and remember which cards are open.
    property var orderIds: []
    property var openIds: ({})
    // Built-in modules the installer left out.
    readonly property var notInstalled: manager ? manager.skipped.map(s => s.name) : []

    function refresh() {
        const ids = manager.ordered.map(m => m.id);
        if (JSON.stringify(ids) !== JSON.stringify(orderIds))
            orderIds = ids;
    }
    Component.onCompleted: refresh()
    Connections {
        target: tab.manager
        function onOrderedChanged() {
            tab.refresh();
        }
    }

    SSection {
        title: "Modules"
        subtitle: "Switch modules on or off, and use the arrows (or the number) to set who wins the island when two are active: the top one takes the pill, the runner-up becomes the bubble."
    }
    Row {
        spacing: 8
        height: 44
        SButton {
            anchors.verticalCenter: parent.verticalCenter
            text: "Rescan modules"
            onClicked: tab.manager.rescan()
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Yours live in ~/.config/island/modules/<id>/"
            color: Theme.fgDim
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 3
        }
    }

    Repeater {
        model: tab.orderIds
        delegate: ModuleCard {
            id: card
            required property string modelData
            required property int index
            width: tab.width - 22
            manager: tab.manager
            rec: tab.manager.recordOf(modelData) || ({ id: modelData, name: modelData, description: "", builtin: false, error: "", manifest: {} })
            expanded: tab.openIds[modelData] === true
            isFirst: index === 0
            isLast: index === tab.orderIds.length - 1 || (tab.manager.recordOf(tab.orderIds[index + 1]) || { manifest: {} }).manifest.ambient === true
            onExpandToggled: {
                const o = Object.assign({}, tab.openIds);
                o[modelData] = !o[modelData];
                tab.openIds = o;
            }
        }
    }

    Repeater {
        model: tab.manager.broken
        delegate: ModuleCard {
            required property var modelData
            width: tab.width - 22
            manager: tab.manager
            rec: modelData
        }
    }

    Text {
        visible: tab.notInstalled.length > 0
        width: tab.width - 22
        topPadding: 10
        wrapMode: Text.Wrap
        text: "Not installed: " + tab.notInstalled.join(", ") + ". Add them with scripts/install.sh modules."
        color: Theme.fgDim
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 3
    }
}
