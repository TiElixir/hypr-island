import QtQuick
import qs.core

// F1 live timing. f1feed.py streams the state of the selected driver from
// F1's live-timing hub; this file only draws it. Each feature (lap times,
// race status, formation lap, lights out, pit, penalty, position) has its own
// switch in Settings.
//
//   collapsed   P3 HAM ▮▮▮ 1:21.345        (sector bars: purple / green / yellow)
//   hover       sector times, last lap, tyre, interval
//   expanded    minisectors, last / best, tyre, gaps, and the driver picker
//   popups      take the island for a few seconds (urgent) with a coloured pulse
Activity {
    id: root

    // ---- data from f1feed.py -------------------------------------------------
    property var st: null              // latest {"t":"state"} message: every car
    property var drivers: []           // entry list: n, tla, name, team, color
    property string offline: ""

    // Your driver and the optional second one, resolved from the entry list.
    // The feed carries every car, so changing either is instant.
    function resolveNum(opt) {
        const want = String(opt || "").trim().toUpperCase();
        if (want === "")
            return "";
        for (const d of drivers)
            if (d.n === want || d.tla === want)
                return d.n;
        return /^[0-9]+$/.test(want) ? want : "";
    }
    readonly property string drvNum: resolveNum(option("driver"))
    readonly property string drv2Num: {
        const n = resolveNum(option("driver2"));
        return n === drvNum ? "" : n;
    }
    function carOf(num) {
        if (!st || !num || !st.cars || !st.cars[num])
            return null;
        let info = { n: num, tla: num, team: "", color: "#888888" };
        for (const d of drivers)
            if (d.n === num)
                info = { n: num, tla: d.tla, team: d.team, color: d.color };
        return Object.assign(info, st.cars[num]);
    }
    readonly property var drv: carOf(drvNum)
    readonly property var drv2: carOf(drv2Num)
    readonly property bool onAir: st !== null && st.live === true && offline === ""
    readonly property string trackCode: st ? st.track.code : "green"

    // ---- feed delay -------------------------------------------------------------
    // Holds every message back by delaySec, so the island matches a TV or
    // stream that runs behind live timing. The queue lives here rather than in
    // the script, so changing the delay mid-race keeps the connection and the
    // messages already received: more delay pauses, less catches up at once.
    readonly property real delayMs: Math.max(0, Number(option("delaySec")) || 0) * 1000
    property var queue: []

    onSourceMessage: msg => {
        if (delayMs <= 0 && queue.length === 0) {
            apply(msg);
            return;
        }
        queue = queue.concat([{ at: Date.now(), msg: msg }]);
        if (!releaseTimer.running)
            armRelease();
    }
    onDelayMsChanged: release()

    function release() {
        const now = Date.now();
        let i = 0;
        while (i < queue.length && queue[i].at + delayMs <= now)
            apply(queue[i++].msg);
        if (i > 0)
            queue = queue.slice(i);
        armRelease();
    }
    // One single-shot timer aimed at the next message that is due, never a poll.
    function armRelease() {
        if (queue.length === 0) {
            releaseTimer.stop();
            return;
        }
        releaseTimer.interval = Math.max(20, queue[0].at + delayMs - Date.now());
        releaseTimer.restart();
    }
    Timer {
        id: releaseTimer
        onTriggered: root.release()
    }

    function apply(msg) {
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
    readonly property bool formationOn: option("showFormation") === true
    readonly property bool startOn: option("showStart") === true
    readonly property bool pitOn: option("showPit") === true
    readonly property bool penaltyOn: option("showPenalty") === true
    readonly property bool positionOn: option("showPosition") === true
    readonly property int popupMs: Math.max(2, Number(option("popupSec")) || 6) * 1000

    readonly property bool statusShown: statusOn && onAir && trackCode !== "green"
    // F1 sends nothing for the formation lap; f1feed.py works it out.
    readonly property bool formationShown: formationOn && onAir && st.session.formation === true
    // What the pill's flag chip shows: the track status, else the formation lap.
    readonly property string chipCode: statusShown ? trackCode : formationShown ? "formation" : ""
    // The expanded header always shows one.
    readonly property string headCode: trackCode !== "green" ? trackCode : formationShown ? "formation" : "green"
    readonly property var pit: pitOn && onAir && st && st.pits && st.pits[drvNum] ? st.pits[drvNum] : null

    // A short-lived popup: {kind, color, title, sub}. Pit stops have their own,
    // fed live while the stop happens.
    property var popup: null
    property real popupAt: 0
    readonly property bool popping: popup !== null || pit !== null

    active: onAir && (lapsOn || chipCode !== "") || popping
    urgent: popping
    accent: popping ? (popup ? popup.color : col.pit) : chipCode !== "" ? statusColor(chipCode) : drv ? drv.color : "#E10600"

    function showPopup(p, ms) {
        popupAt = Date.now();
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
        if (e._event === "status" && e.code === "formation") {
            if (formationOn) {
                showPopup({ kind: "status", color: statusColor("formation"), title: statusShort("formation"), sub: "Lights out after this lap" }, popupMs);
                pulse(statusColor("formation"), 2);
            }
        } else if (e._event === "start" && startOn) {
            const laps = st && st.lap[1] > 0 ? st.lap[1] + " laps" : "";
            const where = st ? st.session.meeting : "";
            showPopup({ kind: "start", color: col.green, title: e.restart ? "RESTART" : "LIGHTS OUT", sub: e.restart ? "The race resumes" + (e.lap ? " on lap " + e.lap : "") : [where, laps].filter(s => s).join("  ·  ") }, popupMs);
            pulse(col.green, 3);
        } else if (e._event === "status" && statusOn) {
            const c = statusColor(e.code);
            const sectors = e.sectors && e.sectors.length ? "Sector " + e.sectors.join(", ") : "";
            showPopup({ kind: "status", color: c, title: statusShort(e.code), sub: e.code === "yellow" ? sectors : e.label }, popupMs);
            pulse(c, e.code === "red" || e.code === "sc" ? 3 : 2);
        } else if (e._event === "penalty" && penaltyOn) {
            const mine = e.driver !== "" && (e.driver === drvNum || e.driver === drv2Num);
            if (option("penaltyScope") !== "all" && !mine)
                return;
            showPopup({ kind: "penalty", color: col.penalty, title: (e.tla || "#" + e.driver) + "  " + e.summary, sub: e.message }, popupMs * 2);
            pulse(col.penalty, mine ? 3 : 2);
        } else if (e._event === "pit" && pitOn && e.phase === "in" && e.driver === drvNum) {
            pulse(col.pit, 2);
        } else if (e._event === "position" && positionOn && e.driver === drvNum) {
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
        return ({ green: "#30D158", yellow: "#FFD60A", sc: "#FFB020", vsc: "#FFB020", vscending: "#FFB020", red: "#FF453A", chequered: "#F2F2F7", formation: "#C7C7CC" })[code] || Theme.accent;
    }
    function statusShort(code) {
        return ({ green: "GREEN FLAG", yellow: "YELLOW FLAG", sc: "SAFETY CAR", vsc: "VIRTUAL SC", vscending: "VSC ENDING", red: "RED FLAG", chequered: "CHEQUERED FLAG", formation: "FORMATION LAP" })[code] || code.toUpperCase();
    }
    function statusChip(code) {
        return ({ yellow: "YEL", sc: "SC", vsc: "VSC", vscending: "VSC", red: "RED", chequered: "FIN", formation: "FORM" })[code] || "";
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
    onDrvNumChanged: posDelta = 0

    // ---- driver selection -------------------------------------------------------------
    // "" not picking, "1" your driver, "2" the second driver
    property string picking: ""
    function pickDriver(tla) {
        Config.set(["modules", moduleId, "options", picking === "2" ? "driver2" : "driver"], tla);
        picking = "";
    }
    onHidden: picking = ""

    // ---- sizes ------------------------------------------------------------------------
    readonly property int ch: Config.cfg.sizes.collapsedHeight
    collapsedSize: popping ? Qt.size(pit !== null || (popup && popup.kind === "penalty") ? 310 : 260, ch + 2) : drv && lapsOn ? Qt.size(chipCode !== "" ? 300 : 262, ch + 2) : Qt.size(chipCode !== "" ? 170 : 150, ch + 2)
    hoverSize: popping ? Qt.size(360, 62) : drv && lapsOn ? Qt.size(360, 62) : Qt.size(240, 48)
    readonly property bool showPicker: picking !== "" || drv === null
    expandedSize: showPicker ? Qt.size(420, 64 + Math.ceil(Math.max(1, drivers.length + (picking === "2" ? 1 : 0)) / 6) * 30) : Qt.size(420, drv2 ? 232 : 150)

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

    // The five start lights: red for a moment, then out. Only while the popup
    // is fresh, so moving between views doesn't replay it.
    component Lamps: Row {
        id: lampRow
        property real lit: 0
        spacing: 3
        function play() {
            if (Date.now() - root.popupAt < 1500)
                litAnim.restart();
        }
        onVisibleChanged: if (visible)
            play()
        Component.onCompleted: if (visible)
            play()
        SequentialAnimation {
            id: litAnim
            PropertyAction {
                target: lampRow
                property: "lit"
                value: 1
            }
            PauseAnimation {
                duration: 300
            }
            NumberAnimation {
                target: lampRow
                property: "lit"
                to: 0
                duration: 160
                easing.type: Easing.OutQuad
            }
        }
        Repeater {
            model: 5
            delegate: Rectangle {
                width: 9
                height: 9
                radius: 4.5
                color: Qt.tint(Qt.rgba(1, 1, 1, 0.16), Qt.rgba(1, 0.23, 0.19, lampRow.lit))
            }
        }
    }

    // Popup content, one line (collapsed) or two (hover).
    component PopupLine: Item {
        property bool twoLines: false
        readonly property var p: root.pit
        readonly property bool lights: !p && root.popup !== null && root.popup.kind === "start"
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
            visible: !parent.lights
            tone: parent.tone
            text: parent.p ? "PIT" : root.popup ? ({ status: "FLAG", penalty: "PEN" })[root.popup.kind] || "F1" : ""
        }
        Lamps {
            id: lamps
            x: 12
            anchors.verticalCenter: kind.verticalCenter
            visible: parent.lights
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
            anchors.left: parent.lights ? lamps.right : kind.right
            anchors.leftMargin: parent.lights ? 10 : 8
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
                    visible: root.chipCode !== ""
                    tone: root.statusColor(root.chipCode)
                    text: root.statusChip(root.chipCode)
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
                    text: root.chipCode !== "" ? root.statusShort(root.chipCode) : "F1 · pick a driver"
                    elide: Text.ElideRight
                    color: root.chipCode !== "" ? root.statusColor(root.chipCode) : Theme.fgDim
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
                        visible: root.chipCode !== ""
                        tone: root.statusColor(root.chipCode)
                        text: root.statusChip(root.chipCode)
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
                text: root.chipCode !== "" ? root.statusShort(root.chipCode) : "Click to pick your driver"
                color: root.chipCode !== "" ? root.statusColor(root.chipCode) : Theme.fgDim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
                font.weight: Font.Bold
            }
        }
    }

    // One driver in the expanded island: position, tyre and gap on top, then
    // minisectors with the sector colour and time, then last and best lap.
    component DriverBlock: Item {
        id: blk
        property var d: null
        property bool primary: false
        readonly property real w3: (width - 20) / 3
        height: 76

        Rectangle {
            id: bar
            y: 1
            width: 4
            height: 20
            radius: 2
            color: blk.d ? blk.d.color : Theme.fgDim
        }
        Text {
            id: posT
            anchors.left: bar.right
            anchors.leftMargin: 8
            anchors.verticalCenter: bar.verticalCenter
            text: blk.d && blk.d.pos ? "P" + blk.d.pos : "P–"
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: Theme.fontSize + 4
            font.weight: Font.Black
        }
        Text {
            id: tlaT
            anchors.left: posT.right
            anchors.leftMargin: 8
            anchors.verticalCenter: bar.verticalCenter
            text: blk.d ? blk.d.tla : ""
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: Theme.fontSize
            font.weight: Font.Bold
        }
        Text {
            anchors.left: tlaT.right
            anchors.leftMargin: 8
            anchors.verticalCenter: bar.verticalCenter
            text: blk.primary && root.posDelta !== 0 ? (root.posDelta > 0 ? "▲" + root.posDelta : "▼" + (-root.posDelta)) : blk.d ? blk.d.team : ""
            color: blk.primary && root.posDelta > 0 ? root.col.gain : blk.primary && root.posDelta < 0 ? root.col.loss : Theme.fgDim
            font.family: Theme.font
            font.pixelSize: Theme.fontSize - 4
            font.weight: blk.primary && root.posDelta !== 0 ? Font.Bold : Font.Normal
        }
        Row {
            anchors.right: parent.right
            anchors.verticalCenter: bar.verticalCenter
            spacing: 6
            Tyre {
                anchors.verticalCenter: parent.verticalCenter
                visible: blk.d !== null && blk.d.tyre !== null
                compound: blk.d && blk.d.tyre ? blk.d.tyre.c : ""
            }
            Mono {
                anchors.verticalCenter: parent.verticalCenter
                visible: blk.d !== null && blk.d.tyre !== null
                text: blk.d && blk.d.tyre ? blk.d.tyre.age + "L" : ""
                color: Theme.fgDim
                font.pixelSize: Theme.fontSize - 3
            }
            Mono {
                anchors.verticalCenter: parent.verticalCenter
                leftPadding: 6
                text: !blk.d ? "" : blk.d.inPit ? "IN PIT" : blk.d.retired ? "OUT" : (blk.d.pos === 1 ? "LEADER" : (blk.d.interval || blk.d.gap || ""))
                color: blk.d && blk.d.inPit ? root.col.pit : Theme.fgDim
                font.pixelSize: Theme.fontSize - 3
            }
        }

        Row {
            y: 30
            spacing: 10
            Repeater {
                model: blk.d ? blk.d.sectors : []
                delegate: Column {
                    id: secCol
                    required property var modelData
                    required property int index
                    readonly property int n: Math.max(1, modelData.seg.length)
                    spacing: 3
                    Row {
                        spacing: 2
                        Repeater {
                            model: secCol.modelData.seg.length > 0 ? secCol.modelData.seg : [""]
                            delegate: Rectangle {
                                required property var modelData
                                width: (blk.w3 - 2 * (secCol.n - 1)) / secCol.n
                                height: 5
                                radius: 2
                                color: root.timingColor(modelData)
                            }
                        }
                    }
                    Rectangle {
                        width: blk.w3
                        height: 3
                        radius: 1.5
                        color: root.timingColor(secCol.modelData.c)
                    }
                    Mono {
                        topPadding: 1
                        text: "S" + (secCol.index + 1) + "  " + (secCol.modelData.v || "––.–––")
                        color: root.textColor(secCol.modelData.c)
                        font.pixelSize: Theme.fontSize - 2
                    }
                }
            }
        }

        Row {
            y: 60
            spacing: 8
            Text {
                anchors.baseline: lastT.baseline
                text: "LAST"
                color: Theme.fgDim
                font.family: Theme.font
                font.pixelSize: 9
                font.weight: Font.Bold
            }
            Mono {
                id: lastT
                text: blk.d && blk.d.last.v ? blk.d.last.v : "–:––.–––"
                color: root.textColor(blk.d ? blk.d.last.c : "")
                font.weight: Font.Bold
            }
            Item {
                width: 8
                height: 1
            }
            Text {
                anchors.baseline: lastT.baseline
                text: "BEST"
                color: Theme.fgDim
                font.family: Theme.font
                font.pixelSize: 9
                font.weight: Font.Bold
            }
            Mono {
                text: blk.d && blk.d.best ? blk.d.best : "–:––.–––"
            }
        }
        Mono {
            anchors.right: parent.right
            y: 60
            text: blk.d ? blk.d.stops + (blk.d.stops === 1 ? " stop" : " stops") : ""
            color: Theme.fgDim
            font.pixelSize: Theme.fontSize - 3
        }
    }

    component Link: Text {
        signal activated
        color: linkHover.hovered ? Theme.fg : Theme.fgDim
        font.family: Theme.font
        font.pixelSize: Theme.fontSize - 3
        font.underline: linkHover.hovered
        HoverHandler {
            id: linkHover
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            // exclusive: the click must not also collapse the island
            gesturePolicy: TapHandler.WithinBounds
            onTapped: parent.activated()
        }
    }

    expandedView: Component {
        Item {
            // header: meeting (or what is being picked), lap, track status
            Text {
                x: 18
                y: 12
                width: parent.width - 170
                text: root.picking === "2" ? "Pick a second driver" : root.showPicker ? "Pick your driver" : root.st ? (root.st.session.meeting || "F1") + (root.st.session.type !== "Race" ? " · " + root.st.session.name : "") : "F1"
                elide: Text.ElideRight
                color: root.showPicker ? Theme.fg : Theme.fgDim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 3
                font.weight: Font.DemiBold
            }
            Row {
                anchors.right: parent.right
                anchors.rightMargin: 18
                y: 10
                spacing: 8
                Link {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.picking !== "" && root.drv !== null
                    text: "Cancel"
                    onActivated: root.picking = ""
                }
                Mono {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !root.showPicker && root.st !== null && root.st.lap[1] > 0
                    text: root.st ? "LAP " + root.st.lap[0] + "/" + root.st.lap[1] : ""
                    color: Theme.fgDim
                    font.pixelSize: Theme.fontSize - 3
                }
                Chip {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !root.showPicker
                    tone: root.statusColor(root.headCode)
                    filled: root.headCode !== "green"
                    text: root.headCode === "green" ? "GREEN" : root.statusChip(root.headCode)
                }
            }

            // driver picker
            Item {
                anchors.fill: parent
                anchors.topMargin: 36
                visible: root.showPicker
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
                        model: root.picking === "2" ? [{ n: "", tla: "NONE", color: "transparent" }].concat(root.drivers) : root.drivers
                        delegate: Rectangle {
                            id: cell
                            required property var modelData
                            readonly property bool chosen: modelData.n === (root.picking === "2" ? root.drv2Num : root.drvNum)
                            width: 58
                            height: 24
                            radius: 6
                            color: cellHover.hovered ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, chosen ? 0.12 : 0.05)
                            border.width: chosen ? 1.5 : 0
                            border.color: modelData.n ? modelData.color : Theme.fgDim
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
                                color: cell.modelData.n ? Theme.fg : Theme.fgDim
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
                                onTapped: root.pickDriver(cell.modelData.n ? cell.modelData.tla : "")
                            }
                        }
                    }
                }
            }

            // your driver, then the second one
            DriverBlock {
                x: 18
                y: 36
                width: parent.width - 36
                visible: !root.showPicker
                d: root.drv
                primary: true
            }
            Rectangle {
                x: 18
                y: 118
                width: parent.width - 36
                height: 1
                visible: !root.showPicker && root.drv2 !== null
                color: Theme.hairline
            }
            DriverBlock {
                x: 18
                y: 126
                width: parent.width - 36
                visible: !root.showPicker && root.drv2 !== null
                d: root.drv2
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: 18
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 10
                spacing: 14
                visible: !root.showPicker
                Link {
                    text: "Change driver"
                    onActivated: root.picking = "1"
                }
                Link {
                    text: root.drv2 ? "Change 2nd" : "Add 2nd driver"
                    onActivated: root.picking = "2"
                }
            }
        }
    }

    bubbleView: Component {
        Item {
            Text {
                anchors.centerIn: parent
                text: root.chipCode !== "" ? root.statusChip(root.chipCode) : root.drv && root.drv.pos ? String(root.drv.pos) : "F1"
                color: root.chipCode !== "" ? root.statusColor(root.chipCode) : root.drv ? root.drv.color : Theme.fg
                font.family: Theme.font
                font.pixelSize: 10
                font.weight: Font.Black
            }
        }
    }
}
