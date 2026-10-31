pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Colours follow wallust through ~/.config/quickshell/qml_color.json (read only).
// That file contains malformed values such as "##E5C2BB", so every value is
// sanitised and falls back to a built-in palette.
Singleton {
    id: root

    property var pal: ({})

    function col(key, fallback) {
        const v = pal[key];
        if (!v)
            return fallback;
        const s = String(v).replace(/^#+/, "#");
        return /^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(s) ? s : fallback;
    }

    readonly property color bg: col("windowBackground", "#14141c")
    readonly property color fg: col("surfaceText", "#eae0e7")
    readonly property color fgDim: col("secondaryText", "#a9a1b0")
    readonly property color accent: col("accentPrimary", "#e5c2bb")
    readonly property color track: Qt.rgba(1, 1, 1, 0.18)
    readonly property color hairline: Qt.rgba(1, 1, 1, 0.07)

    readonly property color running: Config.cfg.colors.running
    readonly property color needsInput: Config.cfg.colors.needsInput
    readonly property color done: Config.cfg.colors.done

    readonly property string font: Config.cfg.font.family
    readonly property int fontSize: Config.cfg.font.size

    FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/qml_color.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                root.pal = JSON.parse(text());
            } catch (e) {
                root.pal = {};
            }
        }
        onLoadFailed: root.pal = ({})
    }
}
