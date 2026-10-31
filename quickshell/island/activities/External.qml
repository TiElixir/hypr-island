import QtQuick
import Quickshell
import Quickshell.Io
import "../core"
import "../components"

// Temporary cards pushed by any script:
//     island-ctl push --id vol --title "Volume 40%" --icon 󰕾 --progress 40 --timeout 2
// island-ctl writes $XDG_RUNTIME_DIR/island/push/<id>.json (atomically) and
// nudges the tick file, so it also works while the island is not running.
// Expiry is one single-shot timer aimed at the next deadline, never a poll.
Activity {
    id: root

    activityId: "external"

    readonly property string pushDir: Feed.stateDir + "/push"

    property var items: []
    readonly property var top: items.length > 0 ? items[0] : null

    active: items.length > 0
    effectivePriority: top && top.priority !== undefined ? top.priority : Config.cfg.priorities.external
    accent: top ? colorOf(top) : Theme.accent

    function colorOf(it) {
        const c = String(it.color || "");
        if (/^#([0-9a-fA-F]{3,4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(c) || /^[a-zA-Z]{3,20}$/.test(c))
            return Qt.color(c);
        return Theme.accent;
    }
    function hasProgress(it) {
        return it && it.progress !== undefined && it.progress !== null && Number(it.progress) >= 0;
    }

    // ---- sizes (collapsed width follows the title) ---------------------------
    TextMetrics {
        id: tm
        text: root.top ? String(root.top.title || "") : ""
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 1
        font.weight: Font.Medium
    }
    readonly property real titleW: Math.min(230, tm.width)
    collapsedSize: Qt.size(Math.round(46 + titleW), Config.cfg.sizes.collapsedHeight + 2)
    hoverSize: Qt.size(Math.max(240, Math.min(380, Math.round(78 + titleW))), top && top.subtitle ? 56 : 46)
    expandedSize: Qt.size(340, hasProgress(top) ? 128 : 108)

    // ---- scanning ------------------------------------------------------------
    Connections {
        target: Feed
        function onChanged() {
            scanTimer.restart();
        }
    }
    Timer {
        id: scanTimer
        interval: 40
        onTriggered: {
            if (scan.running)
                root.rescan = true;
            else
                scan.running = true;
        }
    }
    property bool rescan: false
    Process {
        id: scan
        command: ["sh", "-c", 'for f in "$1"/*.json; do [ -f "$f" ] && { cat "$f"; echo; }; done; exit 0', "sh", root.pushDir]
        stdout: StdioCollector {
            onStreamFinished: root.ingest(text)
        }
        onExited: {
            if (root.rescan) {
                root.rescan = false;
                scan.running = true;
            }
        }
    }

    function safeId(id) {
        return /^[A-Za-z0-9._-]+$/.test(id) && id.charAt(0) !== ".";
    }

    function ingest(text) {
        const now = Date.now() / 1000;
        const out = [];
        const expired = [];
        let next = 0;
        for (const line of text.split("\n")) {
            if (!line.trim())
                continue;
            try {
                const o = JSON.parse(line);
                if (!o || !safeId(String(o.id)))
                    continue;
                const exp = Number(o.expires) || 0;
                if (exp > 0 && exp <= now) {
                    expired.push(o.id);
                    continue;
                }
                if (exp > 0 && (next === 0 || exp < next))
                    next = exp;
                o.created = Number(o.created) || 0;
                out.push(o);
            } catch (e) {}
        }
        out.sort((a, b) => (b.priority !== undefined ? b.priority : Config.cfg.priorities.external) - (a.priority !== undefined ? a.priority : Config.cfg.priorities.external) || b.created - a.created);
        items = out;
        if (expired.length > 0)
            removeIds(expired);
        if (next > 0) {
            expiryTimer.interval = Math.max(50, Math.ceil((next - now) * 1000) + 20);
            expiryTimer.restart();
        } else {
            expiryTimer.stop();
        }
    }
    Timer {
        id: expiryTimer
        onTriggered: scanTimer.restart()
    }

    Process {
        id: rmProc
        onExited: scanTimer.restart()
    }
    function removeIds(ids) {
        const safe = ids.filter(x => safeId(String(x)));
        if (safe.length === 0 || rmProc.running)
            return;
        rmProc.command = ["sh", "-c", 'd=$1; shift; for i; do rm -f "$d/$i.json"; done', "sh", pushDir].concat(safe);
        rmProc.running = true;
    }
    function dismiss() {
        if (top)
            removeIds([top.id]);
    }

    // ---- views ---------------------------------------------------------------
    collapsedView: Component {
        Item {
            Row {
                anchors.centerIn: parent
                spacing: 8
                GlyphIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    size: 14
                    source: root.top ? String(root.top.icon || "") : ""
                    color: root.accent
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(root.titleW + 2, 230)
                    text: root.top ? String(root.top.title || "") : ""
                    elide: Text.ElideRight
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                    font.weight: Font.Medium
                }
            }
        }
    }

    bubbleView: Component {
        Item {
            GlyphIcon {
                anchors.centerIn: parent
                size: 13
                source: root.top ? String(root.top.icon || "") : ""
                color: root.accent
            }
        }
    }

    hoverView: Component {
        Item {
            GlyphIcon {
                id: hi
                x: 18
                anchors.verticalCenter: parent.verticalCenter
                size: 20
                source: root.top ? String(root.top.icon || "") : ""
                color: root.accent
            }
            Column {
                anchors.left: hi.right
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.rightMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Text {
                    width: parent.width
                    text: root.top ? String(root.top.title || "") : ""
                    elide: Text.ElideRight
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                    font.weight: Font.DemiBold
                }
                Text {
                    visible: root.top && root.top.subtitle
                    width: parent.width
                    text: root.top && root.top.subtitle ? String(root.top.subtitle) : ""
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
            GlyphIcon {
                id: ei
                x: 24
                y: 22
                size: 34
                source: root.top ? String(root.top.icon || "") : ""
                color: root.accent
            }
            Column {
                anchors.left: ei.right
                anchors.leftMargin: 16
                anchors.right: parent.right
                anchors.rightMargin: 56
                y: 22
                spacing: 3
                Text {
                    width: parent.width
                    text: root.top ? String(root.top.title || "") : ""
                    elide: Text.ElideRight
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize + 3
                    font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width
                    text: root.top && root.top.subtitle ? String(root.top.subtitle) : ""
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    color: Theme.fgDim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                }
            }
            IconButton {
                anchors.right: parent.right
                anchors.rightMargin: 14
                y: 14
                size: 30
                glyphSize: 16
                glyph: String.fromCodePoint(0xF0156)
                onClicked: root.dismiss()
            }
            SeekBar {
                visible: root.hasProgress(root.top)
                x: 24
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 16
                width: parent.width - 48
                value: root.hasProgress(root.top) ? Number(root.top.progress) / 100 : 0
                color: root.accent
            }
        }
    }
}
