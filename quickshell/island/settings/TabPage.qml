import QtQuick
import qs.core

// Scrollable page for a settings tab. Children are stacked in a column.
Flickable {
    id: page

    default property alias content: col.data

    clip: true
    contentWidth: width
    contentHeight: col.implicitHeight + 30
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick

    Column {
        id: col
        width: page.width - 22
        spacing: 0
    }

    // Slim scroll indicator.
    Rectangle {
        visible: page.contentHeight > page.height
        x: page.width - 6
        y: page.contentY / page.contentHeight * page.height
        width: 3
        height: page.height * page.height / page.contentHeight
        radius: 2
        color: Qt.rgba(1, 1, 1, 0.25)
    }
}
