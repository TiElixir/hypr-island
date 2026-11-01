import QtQuick
import qs.core

// F1 live timing. f1feed.py streams the state of the selected driver from
// F1's live-timing hub; this file only draws it. Each feature (lap times,
// race status, pit, penalty, position) has its own switch in Settings.
//
//   collapsed   P3 HAM ▮▮▮ 1:21.345        (sector bars: purple / green / yellow)
//   hover       sector times, last lap, tyre, interval
//   expanded    minisectors, last / best, tyre, gaps, and the driver picker
//   popups      take the island for a few seconds (urgent) with a coloured pulse
Activity {
    id: root

    // ---- data from f1feed.py -------------------------------------------------
    property var st: null              // latest {"t":"state"} message
    property var drivers: []
    property string offline: ""
    readonly property var drv: st ? st.driver : null
    readonly property bool onAir: st !== null && st.live === true && offline === ""
    readonly property string trackCode: st ? st.track.code : "green"

    onSourceMessage: msg => {
        if (msg.t === "state") {
            st = msg;
            offline = "";
        } else if (msg.t === "drivers") {
            drivers = msg.list || [];
        } else if (msg.t === "offline") {
            offline = String(msg.error || "offline");
        } else if (msg._event) {
            handleEvent(msg);
        }
    }

    // ---- features --------------------------------------------------------------
    readonly property bool lapsOn: option("showLaps") === true
    readonly property bool statusOn: option("showStatus") === true
    readonly property bool pitOn: option("showPit") === true
    readonly property bool penaltyOn: option("showPenalty") === true
    readonly property bool positionOn: option("showPosition") === true
    readonly property int popupMs: Math.max(2, Number(option("popupSec")) || 6) * 1000

    readonly property bool statusShown: statusOn && onAir && trackCode !== "green"
    readonly property var pit: pitOn && onAir && st ? st.pit : null

    // A short-lived popup: {kind, color, title, sub}. Pit stops have their own,
    // fed live while the stop happens.
    property var popup: null
    readonly property bool popping: popup !== null || pit !== null

    active: onAir && (lapsOn || statusShown) || popping
    urgent: popping
    accent: popping ? (popup ? popup.color : col.pit) : statusShown ? statusColor(trackCode) : drv ? drv.color : "#E10600"

    function showPopup(p, ms) {
        popup = p;
        popupTimer.interval = ms;
        popupTimer.restart();
    }
    Timer {
        id: popupTimer
        onTriggered: root.popup = null
    }

    // Position gained / lost: a ring and a small ▲2 / ▼1 badge for a few seconds.
    property int posDelta: 0
    Timer {
        id: deltaTimer
        interval: 5000
        onTriggered: root.posDelta = 0
    }

    function handleEvent(e) {
        if (e._event === "status" && statusOn) {
            const c = statusColor(e.code);
            const sectors = e.sectors && e.sectors.length ? "Sector " + e.sectors.join(", ") : "";
            showPopup({ kind: "status", color: c, title: statusShort(e.code), sub: e.code === "yellow" ? sectors : e.label }, popupMs);
            pulse(c, e.code === "red" || e.code === "sc" ? 3 : 2);
        } else if (e._event === "penalty" && penaltyOn && (option("penaltyScope") === "all" || e.mine)) {
            showPopup({ kind: "penalty", color: col.penalty, title: (e.tla || "#" + e.driver) + "  " + e.summary, sub: e.message }, popupMs * 2);
            pulse(col.penalty, e.mine ? 3 : 2);
        } else if (e._event === "pit" && pitOn && e.phase === "in") {
            pulse(col.pit, 2);
        } else if (e._event === "position" && positionOn) {
            posDelta = e.gained;
            deltaTimer.restart();
            if (!popping)
                pulse(e.gained > 0 ? col.gain : col.loss, 2);
        }
    }

    // ---- colours ------------------------------------------------------------------
    readonly property QtObject col: QtObject {
        readonly property color purple: "#BF5AF2"
        readonly property color green: "#30D158"
        readonly property color yellow: "#FFD60A"
        readonly property color pitlane: "#64D2FF"
        readonly property color none: Qt.rgba(1, 1, 1, 0.16)
        readonly property color pit: "#64D2FF"
        readonly property color penalty: "#FF9F0A"
        readonly property color gain: "#30D158"
        readonly property color loss: "#FF453A"
    }
    function timingColor(c) {
        return c === "p" ? col.purple : c === "g" ? col.green : c === "y" ? col.yellow : c === "pit" ? col.pitlane : col.none;
    }
    function textColor(c) {
        return c === "" ? Theme.fg : timingColor(c);
    }
    function statusColor(code) {
        return ({ green: "#30D158", yellow: "#FFD60A", sc: "#FFB020", vsc: "#FFB020", vscending: "#FFB020", red: "#FF453A", chequered: "#F2F2F7" })[code] || Theme.accent;
    }
    function statusShort(code) {
        return ({ green: "GREEN FLAG", yellow: "YELLOW FLAG", sc: "SAFETY CAR", vsc: "VIRTUAL SC", vscending: "VSC ENDING", red: "RED FLAG", chequered: "CHEQUERED FLAG" })[code] || code.toUpperCase();
    }
    function statusChip(code) {
        return ({ yellow: "YEL", sc: "SC", vsc: "VSC", vscending: "VSC", red: "RED", chequered: "FIN" })[code] || "";
    }
    function tyreColor(c) {
        return ({ SOFT: "#FF453A", MEDIUM: "#FFD60A", HARD: "#F2F2F7", INTERMEDIATE: "#30D158", WET: "#0A84FF" })[c] || Theme.fgDim;
    }
    function tyreLetter(c) {
        return c ? (c === "INTERMEDIATE" ? "I" : c.charAt(0)) : "?";
    }
    function secs(v) {
        return v ? String(v) + "s" : "…";
    }
    readonly property string posText: drv && drv.pos ? "P" + drv.pos : "P–"

    // ---- driver selection -------------------------------------------------------------
    property bool picking: false
    function pickDriver(tla) {
        Config.set(["modules", moduleId, "options", "driver"], tla);
        picking = false;
    }
    onHidden: picking = false

    // ---- sizes ------------------------------------------------------------------------
    readonly property int ch: Config.cfg.sizes.collapsedHeight
    collapsedSize: popping ? Qt.size(pit !== null || (popup && popup.kind === "penalty") ? 310 : 260, ch + 2) : drv && lapsOn ? Qt.size(statusShown ? 300 : 262, ch + 2) : Qt.size(statusShown ? 170 : 150, ch + 2)
    hoverSize: popping ? Qt.size(360, 62) : drv && lapsOn ? Qt.size(360, 62) : Qt.size(240, 48)
    expandedSize: picking || !drv ? Qt.size(400, 60 + Math.ceil(Math.max(1, drivers.length) / 6) * 30) : Qt.size(400, 196)

    // ---- small parts --------------------------------------------------------------------
    component Mono: Text {
        color: Theme.fg
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 1
        font.features: { "tnum": 1 }
    }
    component Chip: Rectangle {
        property alias text: lbl.text
        property color tone: Theme.accent
        property bool filled: true
        implicitWidth: lbl.implicitWidth + 10
        implicitHeight: 16
        radius: 4
        color: filled ? tone : "transparent"
        border.width: filled ? 0 : 1.5
        border.color: tone
        Text {
            id: lbl
            anchors.centerIn: parent
            color: parent.filled ? "#111" : parent.tone
            font.family: Theme.font
            font.pixelSize: 10
            font.weight: Font.Black
        }
    }
    component SectorBars: Row {
        property real barW: 16
        spacing: 3
        Repeater {
            model: root.drv ? root.drv.sectors : []
            delegate: Rectangle {
                required property var modelData
                width: parent.barW
                height: 6
                radius: 3
                color: root.timingColor(modelData.c)
            }
        }
    }
    component Tyre: Rectangle {
        property string compound: ""
        width: 16
        height: 16
        radius: 8
        color: "transparent"
        border.width: 2
        border.color: root.tyreColor(compound)
        Text {
            anchors.centerIn: parent
            text: root.tyreLetter(parent.compound)
            color: root.tyreColor(parent.compound)
            font.family: Theme.font
            font.pixelSize: 9
            font.weight: Font.Black
        }
    }
    component DriverTag: Row {
        spacing: 6
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 3
            height: 13
            radius: 1.5
            color: root.drv ? root.drv.color : Theme.fgDim
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.posText
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 1
            font.weight: Font.Black
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.drv ? root.drv.tla : ""
            color: Theme.fgDim
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 1
            font.weight: Font.DemiBold
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.posDelta !== 0
            text: root.posDelta > 0 ? "▲" + root.posDelta : "▼" + (-root.posDelta)
            color: root.posDelta > 0 ? root.col.gain : root.col.loss
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 3
            font.weight: Font.Bold
        }
    }

    // Popup content, one line (collapsed) or two (hover).
    component PopupLine: Item {
        property bool twoLines: false
        readonly property var p: root.pit
        readonly property string tla: root.drv ? root.drv.tla : ""
        readonly property string title: p ? (p.phase === "in" ? "BOX BOX  " + tla : (twoLines ? "PIT STOP  " : "") + tla) : root.popup ? root.popup.title : ""
        // one-line form: the tyre icon on the right shows the compound
        readonly property string compact: p ? (p.phase === "in" ? "in the pit lane" : "stop " + root.secs(p.stop) + " · lane " + root.secs(p.lane)) : ""
        readonly property string sub: {
            if (!p)
                return root.popup ? root.popup.sub || "" : "";
            const parts = [];
            if (p.compound)
                parts.push(p.compound.charAt(0) + p.compound.slice(1).toLowerCase() + (p.new === false ? " (used)" : ""));
            else if (p.oldCompound)
                parts.push("from " + p.oldCompound.toLowerCase());
            parts.push("stop " + root.secs(p.stop));
            parts.push("lane " + root.secs(p.lane));
            return parts.join("  ·  ");
        }
        readonly property color tone: p ? root.col.pit : root.popup ? root.popup.color : Theme.accent
        Chip {
            id: kind
            x: 12
            anchors.verticalCenter: parent.twoLines ? undefined : parent.verticalCenter
            y: parent.twoLines ? 12 : 0
            tone: parent.tone
            text: parent.p ? "PIT" : root.popup ? ({ status: "FLAG", penalty: "PEN" })[root.popup.kind] || "F1" : ""
        }
        Tyre {
            id: tyreIcon
            visible: parent.p !== null && parent.p.compound !== ""
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: kind.verticalCenter
            compound: parent.p ? parent.p.compound : ""
        }
        Text {
            id: ttl
            anchors.left: kind.right
            anchors.leftMargin: 8
            anchors.right: tyreIcon.visible ? tyreIcon.left : parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: kind.verticalCenter
            text: parent.twoLines || !parent.p ? parent.title : parent.title + "   " + parent.compact
            elide: Text.ElideRight
            color: parent.p ? Theme.fg : parent.tone
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 1
            font.weight: Font.Bold
            font.features: { "tnum": 1 }
        }
        Text {
            visible: parent.twoLines
            anchors.left: kind.left
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.top: kind.bottom
            anchors.topMargin: 8
            text: parent.sub
            elide: Text.ElideRight
            color: Theme.fgDim
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 2
            font.features: { "tnum": 1 }
        }
    }

    // ---- views ------------------------------------------------------------------------------
    collapsedView: Component {
        Item {
            PopupLine {
                anchors.fill: parent
                visible: root.popping
            }
            Item {
                anchors.fill: parent
                visible: !root.popping
                Chip {
                    id: flagChip
                    x: 10
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.statusShown
                    tone: root.statusColor(root.trackCode)
                    text: root.statusChip(root.trackCode)
                }
                DriverTag {
                    id: tag
                    visible: root.drv !== null && root.lapsOn
                    anchors.left: flagChip.visible ? flagChip.right : parent.left
                    anchors.leftMargin: flagChip.visible ? 8 : 12
                    anchors.verticalCenter: parent.verticalCenter
                }
                SectorBars {
                    id: bars
                    visible: tag.visible
                    anchors.right: lastLap.left
                    anchors.rightMargin: 9
                    anchors.verticalCenter: parent.verticalCenter
                }
                Mono {
                    id: lastLap
                    visible: tag.visible
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.drv && root.drv.inPit ? "IN PIT" : root.drv && root.drv.last.v ? root.drv.last.v : "–:––.–––"
                    color: root.drv && root.drv.inPit ? root.col.pit : root.textColor(root.drv ? root.drv.last.c : "")
                }
                Text {
                    visible: !tag.visible
                    anchors.left: flagChip.visible ? flagChip.right : parent.left
                    anchors.leftMargin: flagChip.visible ? 8 : 12
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: flagChip.visible ? Text.AlignLeft : Text.AlignHCenter
                    text: root.statusShown ? root.statusShort(root.trackCode) : "F1 · pick a driver"
                    elide: Text.ElideRight
                    color: root.statusShown ? root.statusColor(root.trackCode) : Theme.fgDim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 2
                    font.weight: Font.Bold
                }
            }
        }
    }

    hoverView: Component {
        Item {
            PopupLine {
                anchors.fill: parent
                visible: root.popping
                twoLines: true
            }
            Item {
                anchors.fill: parent
                visible: !root.popping && root.drv !== null && root.lapsOn
                DriverTag {
                    x: 14
                    y: 11
                }
                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    y: 10
                    spacing: 8
                    Chip {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.statusShown
                        tone: root.statusColor(root.trackCode)
                        text: root.statusChip(root.trackCode)
                    }
                    Tyre {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.drv && root.drv.tyre !== null
                        compound: root.drv && root.drv.tyre ? root.drv.tyre.c : ""
                    }
                    Mono {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.drv && root.drv.tyre !== null
                        text: root.drv && root.drv.tyre ? root.drv.tyre.age + "L" : ""
                        color: Theme.fgDim
                        font.pixelSize: Theme.fontSize - 3
                    }
                    Mono {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.drv ? (root.drv.interval || root.drv.gap || "") : ""
                        color: Theme.fgDim
                        font.pixelSize: Theme.fontSize - 3
                    }
                }
                Row {
                    x: 14
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 10
                    spacing: 12
                    Repeater {
                        model: root.drv ? root.drv.sectors : []
                        delegate: Mono {
                            required property var modelData
                            required property int index
                            text: "S" + (index + 1) + " " + (modelData.v || "––.–––")
                            color: root.textColor(modelData.c)
                            font.pixelSize: Theme.fontSize - 2
                        }
                    }
                }
                Mono {
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 10
                    text: root.drv && root.drv.last.v ? root.drv.last.v : "–:––.–––"
                    color: root.textColor(root.drv ? root.drv.last.c : "")
                    font.weight: Font.Bold
                }
            }
            Text {
                anchors.centerIn: parent
                visible: !root.popping && !(root.drv !== null && root.lapsOn)
                text: root.statusShown ? root.statusShort(root.trackCode) : "Click to pick your driver"
                color: root.statusShown ? root.statusColor(root.trackCode) : Theme.fgDim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
                font.weight: Font.Bold
            }
        }
    }

    expandedView: Component {
        Item {
            // header: meeting, lap, status
            Text {
                x: 18
                y: 12
                width: parent.width - 150
                text: root.st ? (root.st.session.meeting || "F1") + (root.st.session.type !== "Race" ? " · " + root.st.session.name : "") : "F1"
                elide: Text.ElideRight
                color: Theme.fgDim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 3
                font.weight: Font.DemiBold
            }
            Row {
                anchors.right: parent.right
                anchors.rightMargin: 18
                y: 10
                spacing: 8
                Mono {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.st && root.st.lap[1] > 0
                    text: root.st ? "LAP " + root.st.lap[0] + "/" + root.st.lap[1] : ""
                    color: Theme.fgDim
                    font.pixelSize: Theme.fontSize - 3
                }
                Chip {
                    anchors.verticalCenter: parent.verticalCenter
                    tone: root.statusColor(root.trackCode)
                    filled: root.trackCode !== "green"
                    text: root.trackCode === "green" ? "GREEN" : root.statusChip(root.trackCode)
                }
            }

            // driver picker
            Item {
                anchors.fill: parent
                anchors.topMargin: 36
                visible: root.picking || root.drv === null
                Text {
                    visible: root.drivers.length === 0
                    anchors.centerIn: parent
                    text: root.offline ? "Live timing unreachable" : "Waiting for the entry list…"
                    color: Theme.fgDim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 2
                }
                Grid {
                    x: 18
                    columns: 6
                    columnSpacing: 6
                    rowSpacing: 6
                    Repeater {
                        model: root.drivers
                        delegate: Rectangle {
                            id: cell
                            required property var modelData
                            readonly property bool mine: root.drv && root.drv.n === modelData.n
                            width: 54
                            height: 24
                            radius: 6
                            color: cellHover.hovered ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, mine ? 0.12 : 0.05)
                            border.width: mine ? 1.5 : 0
                            border.color: modelData.color
                            Rectangle {
                                x: 6
                                anchors.verticalCenter: parent.verticalCenter
                                width: 3
                                height: 12
                                radius: 1.5
                                color: cell.modelData.color
                            }
                            Text {
                                x: 14
                                anchors.verticalCenter: parent.verticalCenter
                                text: cell.modelData.tla
                                color: Theme.fg
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize - 2
                                font.weight: Font.DemiBold
                            }
                            HoverHandler {
                                id: cellHover
                                cursorShape: Qt.PointingHandCursor
                            }
                            TapHandler {
                                // exclusive: the click must not also collapse the island
                                gesturePolicy: TapHandler.WithinBounds
                                onTapped: root.pickDriver(cell.modelData.tla)
                            }
                        }
                    }
                }
            }

            // dashboard
            Item {
                anchors.fill: parent
                visible: !root.picking && root.drv !== null
                Row {
                    x: 18
                    y: 34
                    spacing: 10
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 4
                        height: 26
                        radius: 2
                        color: root.drv ? root.drv.color : Theme.fgDim
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.posText
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize + 9
                        font.weight: Font.Black
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            text: root.drv ? root.drv.tla + (root.posDelta !== 0 ? (root.posDelta > 0 ? "  ▲" + root.posDelta : "  ▼" + (-root.posDelta)) : "") : ""
                            color: root.posDelta > 0 ? root.col.gain : root.posDelta < 0 ? root.col.loss : Theme.fg
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize
                            font.weight: Font.Bold
                        }
                        Text {
                            text: root.drv ? root.drv.team : ""
                            color: Theme.fgDim
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize - 4
                        }
                    }
                }
                Column {
                    anchors.right: parent.right
                    anchors.rightMargin: 18
                    y: 34
                    spacing: 2
                    Mono {
                        anchors.right: parent.right
                        text: "INT " + (root.drv && root.drv.interval ? root.drv.interval : "–")
                        color: Theme.fgDim
                        font.pixelSize: Theme.fontSize - 3
                    }
                    Mono {
                        anchors.right: parent.right
                        text: "LDR " + (root.drv && root.drv.gap ? root.drv.gap : "–")
                        color: Theme.fgDim
                        font.pixelSize: Theme.fontSize - 3
                    }
                }

                // minisectors, one block per sector, with the sector time under it
                Row {
                    x: 18
                    y: 80
                    spacing: 10
                    Repeater {
                        model: root.drv ? root.drv.sectors : []
                        delegate: Column {
                            id: secCol
                            required property var modelData
                            required property int index
                            readonly property real w: (400 - 36 - 20) / 3
                            spacing: 5
                            Row {
                                spacing: 2
                                Repeater {
                                    model: secCol.modelData.seg.length > 0 ? secCol.modelData.seg : [""]
                                    delegate: Rectangle {
                                        required property var modelData
                                        width: (secCol.w - 2 * (Math.max(1, secCol.modelData.seg.length) - 1)) / Math.max(1, secCol.modelData.seg.length)
                                        height: 5
                                        radius: 2
                                        color: root.timingColor(modelData)
                                    }
                                }
                            }
                            Rectangle {
                                width: secCol.w
                                height: 3
                                radius: 1.5
                                color: root.timingColor(secCol.modelData.c)
                            }
                            Mono {
                                text: "S" + (secCol.index + 1) + "  " + (secCol.modelData.v || "––.–––")
                                color: root.textColor(secCol.modelData.c)
                                font.pixelSize: Theme.fontSize - 2
                            }
                        }
                    }
                }

                // last / best / tyre / stops
                Row {
                    x: 18
                    y: 140
                    spacing: 18
                    Column {
                        Text {
                            text: "LAST"
                            color: Theme.fgDim
                            font.family: Theme.font
                            font.pixelSize: 9
                            font.weight: Font.Bold
                        }
                        Mono {
                            text: root.drv && root.drv.last.v ? root.drv.last.v : "–:––.–––"
                            color: root.textColor(root.drv ? root.drv.last.c : "")
                            font.pixelSize: Theme.fontSize + 1
                            font.weight: Font.Bold
                        }
                    }
                    Column {
                        Text {
                            text: "BEST"
                            color: Theme.fgDim
                            font.family: Theme.font
                            font.pixelSize: 9
                            font.weight: Font.Bold
                        }
                        Mono {
                            text: root.drv && root.drv.best ? root.drv.best : "–:––.–––"
                            font.pixelSize: Theme.fontSize + 1
                        }
                    }
                    Column {
                        Text {
                            text: "TYRE"
                            color: Theme.fgDim
                            font.family: Theme.font
                            font.pixelSize: 9
                            font.weight: Font.Bold
                        }
                        Row {
                            spacing: 6
                            height: 20
                            Tyre {
                                anchors.verticalCenter: parent.verticalCenter
                                compound: root.drv && root.drv.tyre ? root.drv.tyre.c : ""
                            }
                            Mono {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.drv && root.drv.tyre ? root.drv.tyre.age + " laps" + (root.drv.tyre.new ? "" : " (used)") : "–"
                                font.pixelSize: Theme.fontSize - 2
                            }
                        }
                    }
                    Column {
                        Text {
                            text: "STOPS"
                            color: Theme.fgDim
                            font.family: Theme.font
                            font.pixelSize: 9
                            font.weight: Font.Bold
                        }
                        Mono {
                            text: root.drv ? (root.drv.inPit ? "IN PIT" : String(root.drv.stops)) : "–"
                            color: root.drv && root.drv.inPit ? root.col.pit : Theme.fg
                            font.pixelSize: Theme.fontSize + 1
                        }
                    }
                }
                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 18
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 12
                    text: "Change driver"
                    color: changeHover.hovered ? Theme.fg : Theme.fgDim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 3
                    font.underline: changeHover.hovered
                    HoverHandler {
                        id: changeHover
                        cursorShape: Qt.PointingHandCursor
                    }
                    TapHandler {
                        gesturePolicy: TapHandler.WithinBounds
                        onTapped: root.picking = true
                    }
                }
            }
        }
    }

    bubbleView: Component {
        Item {
            Text {
                anchors.centerIn: parent
                text: root.statusShown ? root.statusChip(root.trackCode) : root.drv && root.drv.pos ? String(root.drv.pos) : "F1"
                color: root.statusShown ? root.statusColor(root.trackCode) : root.drv ? root.drv.color : Theme.fg
                font.family: Theme.font
                font.pixelSize: 10
                font.weight: Font.Black
            }
        }
    }
}
