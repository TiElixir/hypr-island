import QtQuick
import Quickshell.Hyprland
import Quickshell.Widgets
import qs.core

// Your Discord voice call. discordfeed.py holds the connection to the Discord
// client and streams the call; this file only draws it and sends commands back.
//
//   collapsed   mic state and how long the call has lasted
//   hover       channel name and the participants' avatars
//   expanded    avatars with names, then mic / deafen / camera / leave
//
// Mic, deafen and leave go over Discord's local RPC. That API has no camera
// control, so the camera button presses the key you bound to it in Discord.
Activity {
    id: root

    accent: "#5865F2"

    // ---- state from discordfeed.py ----------------------------------------
    property bool inCall: false
    property string channelName: ""
    property string guildName: ""
    property string kind: "voice"
    property real since: 0
    property string meId: ""
    property var members: []
    property var speaking: ({})
    property bool muted: false
    property bool deafened: false
    property string feedState: ""

    // Nothing about a call is true once the script is not connected to Discord.
    function resetCall() {
        inCall = false;
        members = [];
        speaking = {};
        muted = false;
        deafened = false;
    }
    onSourceStatusChanged: {
        if (sourceStatus.indexOf("running") !== 0)
            resetCall();
    }

    onSourceMessage: msg => {
        if (msg.t === "call") {
            inCall = msg.inCall === true;
            if (inCall) {
                channelName = String(msg.name || "");
                guildName = String(msg.guild || "");
                kind = String(msg.kind || "voice");
                since = Number(msg.since) || 0;
                meId = String(msg.me || "");
                members = msg.members || [];
                const sp = {};
                for (const m of members)
                    if (m.speaking)
                        sp[m.id] = true;
                speaking = sp;
            } else {
                members = [];
                speaking = {};
            }
        } else if (msg.t === "speaking") {
            const sp = Object.assign({}, speaking);
            if (msg.on)
                sp[msg.id] = true;
            else
                delete sp[msg.id];
            speaking = sp;
        } else if (msg.t === "voice") {
            muted = msg.mute === true;
            deafened = msg.deaf === true;
        } else if (msg.t === "status") {
            feedState = String(msg.state || "");
            if (feedState !== "ready")
                resetCall();
            if (feedState === "setup")
                showNotice("Discord needs an application", String(msg.message || ""), col.warn, 9000);
            else if (feedState === "authorizing")
                showNotice("Approve Island in Discord", "Press Authorize in the Discord window that just opened", root.accent, 25000);
            else if (feedState === "error")
                showNotice("Discord", String(msg.message || "Something went wrong"), col.bad, 9000);
            else
                clearNotice();
        }
    }

    // ---- notices: setup and authorisation, shown for a while ----------------
    property var notice: null
    readonly property bool noticing: notice !== null
    function showNotice(title, sub, color, ms) {
        notice = { title: title, sub: sub, color: color };
        noticeTimer.interval = ms;
        noticeTimer.restart();
        pulse(color, 2);
    }
    function clearNotice() {
        notice = null;
        noticeTimer.stop();
    }
    Timer {
        id: noticeTimer
        onTriggered: root.notice = null
    }

    active: inCall || noticing
    urgent: noticing

    // ---- call length ---------------------------------------------------------
    property real now: Date.now()
    readonly property int elapsed: Math.max(0, Math.floor((now - since * 1000) / 1000))
    // Only ticks while the call is the main pill.
    Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: root.hostPresented && root.inCall && !root.noticing
        onTriggered: root.now = Date.now()
    }
    function fmt(sec) {
        const h = Math.floor(sec / 3600), m = Math.floor(sec / 60) % 60, s = sec % 60;
        const two = n => String(n).padStart(2, "0");
        return h > 0 ? h + ":" + two(m) + ":" + two(s) : m + ":" + two(s);
    }

    // ---- commands --------------------------------------------------------------
    function send(obj) {
        sourceWrite(JSON.stringify(obj) + "\n");
    }
    // While deafened, the mic button undeafens, like Discord's own.
    function toggleMute() {
        if (deafened)
            send({ cmd: "deaf", value: false });
        else
            send({ cmd: "mute", value: !muted });
    }
    function toggleDeafen() {
        send({ cmd: "deaf", value: !deafened });
    }
    function leave() {
        send({ cmd: "leave" });
    }

    // "CTRL SHIFT, V" or "CTRL+SHIFT+V" -> "CTRL SHIFT, V"; "" when unset or odd.
    function shortcutOf(text) {
        const t = String(text || "").trim();
        if (t === "" || !/^[A-Za-z0-9_ ,+\-]+$/.test(t))
            return "";
        const parts = t.split(/[\s,+]+/).filter(p => p !== "");
        const key = parts.pop();
        return parts.join(" ") + ", " + key;
    }
    readonly property string cameraKeys: shortcutOf(option("cameraShortcut"))
    readonly property string windowClass: {
        const c = String(option("windowClass") || "").trim();
        return /^[A-Za-z0-9_.\-]+$/.test(c) ? c : "discord";
    }
    function toggleCamera() {
        if (cameraKeys !== "")
            Hyprland.dispatch("sendshortcut " + cameraKeys + ", class:^(" + windowClass + ")$");
    }

    // ---- look ------------------------------------------------------------------
    readonly property QtObject col: QtObject {
        readonly property color live: "#30D158"
        readonly property color bad: "#FF453A"
        readonly property color warn: "#FF9F0A"
    }
    readonly property bool micOff: muted || deafened
    readonly property string micGlyph: String.fromCodePoint(deafened ? 0xF07CE : muted ? 0xF036D : 0xF036C)
    readonly property string subtitle: guildName !== "" ? guildName + "  ·  " + members.length : members.length + (members.length === 1 ? " person" : " people")

    readonly property int ch: Config.cfg.sizes.collapsedHeight
    collapsedSize: noticing ? Qt.size(290, ch + 2) : Qt.size(elapsed >= 3600 ? 112 : 96, ch + 2)
    hoverSize: noticing ? Qt.size(340, 56) : Qt.size(330, 52)
    expandedSize: noticing ? Qt.size(360, 84) : Qt.size(392, 170)

    component Avatar: Item {
        id: av
        property var m: null
        property real size: 28
        property bool badge: false
        readonly property bool talking: m !== null && root.speaking[m.id] === true
        width: size
        height: size

        // Dark rim separates overlapping avatars; green while the person talks.
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.width: 2
            border.color: av.talking ? root.col.live : Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 1)
            Behavior on border.color {
                ColorAnimation {
                    duration: 120
                }
            }
        }
        ClippingRectangle {
            anchors.fill: parent
            anchors.margins: 3
            radius: width / 2
            color: Theme.track
            Text {
                anchors.centerIn: parent
                visible: img.status !== Image.Ready
                text: av.m && av.m.name ? String(av.m.name).charAt(0).toUpperCase() : ""
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: av.size * 0.4
                font.weight: Font.Bold
            }
            Image {
                id: img
                anchors.fill: parent
                source: av.m && av.m.avatar ? "file://" + av.m.avatar : ""
                asynchronous: true
                fillMode: Image.PreserveAspectCrop
                sourceSize: Qt.size(96, 96)
            }
        }
        Rectangle {
            visible: av.badge && av.m !== null && (av.m.muted || av.m.deafened)
            x: av.width - width + 2
            y: av.height - height + 2
            width: 15
            height: 15
            radius: 7.5
            color: root.col.bad
            border.width: 2
            border.color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 1)
            Text {
                anchors.centerIn: parent
                text: String.fromCodePoint(av.m && av.m.deafened ? 0xF07CE : 0xF036D)
                color: "white"
                font.family: Theme.font
                font.pixelSize: 8
            }
        }
    }

    component CtlButton: Item {
        id: btn
        property string glyph: ""
        property bool off: false      // shows the "switched off" state, in red
        property bool danger: false   // solid red
        signal clicked
        width: 46
        height: 34

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: btn.danger ? (ma.pressed ? "#D93A31" : "#FF453A") : btn.off ? Qt.rgba(1, 0.27, 0.23, ma.containsMouse ? 0.34 : 0.24) : Qt.rgba(1, 1, 1, ma.pressed ? 0.24 : ma.containsMouse ? 0.17 : 0.1)
            Behavior on color {
                ColorAnimation {
                    duration: 100
                }
            }
        }
        Text {
            anchors.centerIn: parent
            text: btn.glyph
            color: btn.danger ? "white" : btn.off ? "#FF6A60" : Theme.fg
            font.family: Theme.font
            font.pixelSize: 17
        }
        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }

    component NoticeBox: Item {
        Rectangle {
            x: 14
            anchors.verticalCenter: parent.verticalCenter
            width: 8
            height: 8
            radius: 4
            color: root.notice ? root.notice.color : root.accent
        }
        Column {
            x: 30
            width: parent.width - 44
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            Text {
                width: parent.width
                text: root.notice ? root.notice.title : ""
                elide: Text.ElideRight
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 2
                font.weight: Font.Bold
            }
            Text {
                width: parent.width
                visible: parent.parent.height > 40
                text: root.notice ? root.notice.sub : ""
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                color: Theme.fgDim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 3
            }
        }
    }

    // ---- views -----------------------------------------------------------------
    collapsedView: Component {
        Item {
            NoticeBox {
                anchors.fill: parent
                visible: root.noticing
            }
            Row {
                anchors.centerIn: parent
                visible: !root.noticing
                spacing: 7
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.micGlyph
                    color: root.micOff ? root.col.bad : root.accent
                    font.family: Theme.font
                    font.pixelSize: 14
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.fmt(root.elapsed)
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                    font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                }
            }
        }
    }

    hoverView: Component {
        Item {
            id: hv
            readonly property int maxShown: 5
            readonly property int overflow: Math.max(0, root.members.length - maxShown)
            readonly property real step: 20

            NoticeBox {
                anchors.fill: parent
                visible: root.noticing
            }

            Item {
                anchors.fill: parent
                visible: !root.noticing

                // avatars overlap, the last one may be "+N"
                Item {
                    id: stack
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    width: (Math.min(root.members.length, hv.maxShown) + (hv.overflow > 0 ? 1 : 0) - 1) * hv.step + 28
                    height: 28
                    Repeater {
                        model: root.members.slice(0, hv.maxShown)
                        delegate: Avatar {
                            required property var modelData
                            required property int index
                            x: index * hv.step
                            m: modelData
                            size: 28
                        }
                    }
                    Rectangle {
                        visible: hv.overflow > 0
                        x: hv.maxShown * hv.step
                        width: 28
                        height: 28
                        radius: 14
                        color: Theme.track
                        border.width: 2
                        border.color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 1)
                        Text {
                            anchors.centerIn: parent
                            text: "+" + hv.overflow
                            color: Theme.fg
                            font.family: Theme.font
                            font.pixelSize: 10
                            font.weight: Font.Bold
                        }
                    }
                }

                Column {
                    x: 16
                    width: stack.x - 16 - 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1
                    Text {
                        width: parent.width
                        text: root.channelName
                        elide: Text.ElideRight
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 1
                        font.weight: Font.DemiBold
                    }
                    Text {
                        width: parent.width
                        text: root.subtitle
                        elide: Text.ElideRight
                        color: Theme.fgDim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 3
                    }
                }
            }
        }
    }

    expandedView: Component {
        Item {
            id: ex
            readonly property int slots: 7
            readonly property bool crowded: root.members.length > slots
            readonly property int shownCount: crowded ? slots - 1 : root.members.length

            NoticeBox {
                anchors.fill: parent
                visible: root.noticing
            }

            Item {
                anchors.fill: parent
                visible: !root.noticing

                Column {
                    x: 18
                    y: 14
                    width: parent.width - 36 - 76
                    spacing: 1
                    Text {
                        width: parent.width
                        text: root.channelName
                        elide: Text.ElideRight
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize + 1
                        font.weight: Font.DemiBold
                    }
                    Text {
                        width: parent.width
                        text: root.subtitle
                        elide: Text.ElideRight
                        color: Theme.fgDim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize - 3
                    }
                }
                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 18
                    y: 16
                    text: root.fmt(root.elapsed)
                    color: Theme.fgDim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                    font.features: { "tnum": 1 }
                }

                Row {
                    x: 18
                    y: 56
                    Repeater {
                        model: root.members.slice(0, ex.shownCount)
                        delegate: Column {
                            required property var modelData
                            width: 48
                            spacing: 3
                            Avatar {
                                anchors.horizontalCenter: parent.horizontalCenter
                                m: modelData
                                size: 36
                                badge: true
                            }
                            Text {
                                width: parent.width - 4
                                anchors.horizontalCenter: parent.horizontalCenter
                                horizontalAlignment: Text.AlignHCenter
                                text: modelData.name
                                elide: Text.ElideRight
                                color: Theme.fgDim
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize - 4
                            }
                        }
                    }
                    Item {
                        visible: ex.crowded
                        width: 48
                        height: 36
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 36
                            height: 36
                            radius: 18
                            color: Theme.track
                            Text {
                                anchors.centerIn: parent
                                text: "+" + (root.members.length - ex.shownCount)
                                color: Theme.fg
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize - 2
                                font.weight: Font.Bold
                            }
                        }
                    }
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 124
                    spacing: 10
                    CtlButton {
                        glyph: root.micGlyph
                        off: root.micOff
                        onClicked: root.toggleMute()
                    }
                    CtlButton {
                        glyph: String.fromCodePoint(root.deafened ? 0xF07CE : 0xF02CB)
                        off: root.deafened
                        onClicked: root.toggleDeafen()
                    }
                    CtlButton {
                        visible: root.cameraKeys !== ""
                        glyph: String.fromCodePoint(0xF05A0)
                        onClicked: root.toggleCamera()
                    }
                    CtlButton {
                        danger: true
                        glyph: String.fromCodePoint(0xF03F7)
                        onClicked: root.leave()
                    }
                }
            }
        }
    }

    bubbleView: Component {
        Item {
            Text {
                anchors.centerIn: parent
                text: root.micGlyph
                color: root.micOff ? root.col.bad : root.accent
                font.family: Theme.font
                font.pixelSize: 13
            }
        }
    }
}
