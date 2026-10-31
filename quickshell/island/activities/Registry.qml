import QtQuick
import "../core"

// The one place activities are registered: instantiate it, then list it in
// `all`. Everything else (selection, views, IPC status) follows from that.
QtObject {
    id: reg

    property QtObject clock: Clock {}
    property QtObject spotify: Spotify {}
    property QtObject claude: Claude {}

    readonly property var all: [clock, spotify, claude]
}
