import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.core
import qs.components

// Music over MPRIS. Prefers Spotify (configurable), ignores playerctld,
// and hides itself when nothing is playing.
Activity {
    id: root

    accent: "#1DB954"

    collapsedSize: Qt.size(56, Config.cfg.sizes.collapsedHeight + 2)
    hoverSize: Qt.size(310, 48)
    expandedSize: Qt.size(392, 164)

    // ---- player selection -------------------------------------------------
    // Pass 1 considers only playing players, pass 2 everything. Within a
    // pass, playerPriority decides.
    readonly property var player: pickPlayer()

    function pickPlayer() {
        const all = [];
        const vals = Mpris.players.values;
        for (let i = 0; i < vals.length; i++) {
            if (String(vals[i].dbusName).indexOf("playerctld") < 0)
                all.push(vals[i]);
        }
        if (all.length === 0)
            return null;
        const norm = s => String(s).toLowerCase();
        const matches = (p, key) => key === "*" || norm(p.dbusName).indexOf(norm(key)) >= 0 || norm(p.identity).indexOf(norm(key)) >= 0;
        const prio = root.option("playerPriority");
        for (const onlyPlaying of [true, false]) {
            for (let k = 0; k < prio.length; k++) {
                for (let i = 0; i < all.length; i++) {
                    if (matches(all[i], prio[k]) && (!onlyPlaying || all[i].isPlaying))
                        return all[i];
                }
            }
        }
        return null;
    }

    readonly property bool playing: player !== null && player.isPlaying
    property bool lingering: false

    onPlayingChanged: {
        root.emit("state", { state: playing ? "playing" : "paused", player: player ? String(player.identity) : "" });
        if (playing) {
            lingering = true;
            lingerTimer.stop();
        } else if (player !== null) {
            lingerTimer.restart();
        }
    }
    onPlayerChanged: {
        lingering = playing;
        if (!player || playing)
            lingerTimer.stop();
        fetchArt();
    }
    Timer {
        id: lingerTimer
        interval: Number(root.option("pausedLingerSec")) * 1000
        onTriggered: root.lingering = false
    }

    active: player !== null && String(player.trackTitle) !== "" && (playing || lingering)

    // ---- track info -------------------------------------------------------
    readonly property string title: player ? String(player.trackTitle) : ""
    readonly property string artist: player ? String(player.trackArtist) : ""
    readonly property string album: player ? String(player.trackAlbum) : ""
    // One event per track change (title and artist settle a moment apart).
    Timer {
        id: trackTimer
        interval: 150
        onTriggered: if (root.title !== "")
            root.emit("track", { title: root.title, artist: root.artist, album: root.album, player: root.player ? String(root.player.identity) : "" })
    }
    onTitleChanged: trackTimer.restart()
    onArtistChanged: trackTimer.restart()
    // Ads and podcasts can report length 0.
    readonly property bool hasLength: player !== null && player.lengthSupported && player.length > 0
    readonly property real position: player && player.positionSupported ? player.position : 0
    readonly property real length: hasLength ? player.length : 0
    readonly property real progress: hasLength ? Math.max(0, Math.min(1, position / length)) : 0
    readonly property bool canSeek: hasLength && player.canSeek && player.positionSupported

    function fmt(sec) {
        const s = Math.max(0, Math.floor(sec));
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
    }

    // MPRIS does not push position. Tick once a second, only while it moves.
    Timer {
        interval: 1000
        repeat: true
        running: root.active && root.playing && root.hasLength
        onTriggered: root.player.positionChanged()
    }
    Connections {
        target: root.player
        ignoreUnknownSignals: true
        function onTrackChanged() {
            root.player.positionChanged();
        }
    }

    // ---- album art, cached on disk ---------------------------------------
    readonly property string artUrl: player ? String(player.trackArtUrl) : ""
    readonly property string artDir: Quickshell.env("HOME") + "/.cache/island/art"
    property string artSource: ""
    property string loadedFor: ""
    onArtUrlChanged: fetchArt()

    function artFile(url) {
        return artDir + "/" + Qt.md5(url) + ".jpg";
    }
    function fetchArt() {
        if (!artProc.running)
            startFetch();
    }
    function startFetch() {
        const u = artUrl;
        loadedFor = u;
        if (u === "") {
            artSource = "";
            return;
        }
        if (u.indexOf("file://") === 0) {
            artSource = u;
            return;
        }
        if (!/^https?:\/\//.test(u)) {
            artSource = "";
            return;
        }
        artProc.command = ["sh", "-c", 'mkdir -p "$3"\n' + 'if [ ! -s "$2" ]; then curl -fsSL --max-time 10 -o "$2.part" "$1" && mv -f "$2.part" "$2"; fi\n' + 'rc=0; [ -s "$2" ] || rc=1\n' + 'ls -t "$3"/*.jpg 2>/dev/null | tail -n +51 | xargs -r rm -f --\n' + 'exit $rc', "sh", u, artFile(u), artDir];
        artProc.running = true;
    }
    Process {
        id: artProc
        onExited: code => {
            if (root.loadedFor !== root.artUrl)
                root.startFetch();
            else if (code === 0)
                root.artSource = "file://" + root.artFile(root.loadedFor);
        }
    }

    // ---- views ------------------------------------------------------------
    collapsedView: Component {
        Item {
            ArtCircle {
                anchors.centerIn: parent
                width: 22
                height: 22
                source: root.artSource
                progress: root.progress
                showRing: root.hasLength
                ringColor: root.accent
            }
        }
    }

    bubbleView: Component {
        Item {
            ArtCircle {
                anchors.centerIn: parent
                width: 20
                height: 20
                source: root.artSource
                progress: root.progress
                showRing: root.hasLength
                ringColor: root.accent
            }
        }
    }

    hoverView: Component {
        Item {
            ArtCircle {
                id: art
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                width: 30
                height: 30
                source: root.artSource
                progress: root.progress
                showRing: root.hasLength
                ringColor: root.accent
            }
            Column {
                anchors.left: art.right
                anchors.leftMargin: 10
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                Text {
                    width: parent.width
                    text: root.title
                    elide: Text.ElideRight
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                    font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width
                    text: root.artist
                    elide: Text.ElideRight
                    color: Theme.fgDim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 3
                }
                SeekBar {
                    width: parent.width
                    height: 8
                    value: root.progress
                    indeterminate: !root.hasLength
                    color: root.accent
                }
            }
        }
    }

    expandedView: Component {
        Item {
            id: ex

            Rectangle {
                id: artBox
                x: 18
                y: 18
                width: 128
                height: 128
                radius: 16
                color: Theme.track
                clip: true
                Image {
                    anchors.fill: parent
                    source: root.artSource
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                    sourceSize: Qt.size(256, 256)
                    layer.enabled: true
                }
            }

            Column {
                x: artBox.x + artBox.width + 18
                y: 20
                width: ex.width - x - 18
                spacing: 2
                Text {
                    width: parent.width
                    text: root.title
                    elide: Text.ElideRight
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize + 3
                    font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width
                    text: root.artist
                    elide: Text.ElideRight
                    color: Theme.fgDim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 1
                }
            }

            Item {
                id: lower
                x: artBox.x + artBox.width + 18
                y: 78
                width: ex.width - x - 18
                height: 70

                SeekBar {
                    id: bar
                    width: parent.width
                    value: root.progress
                    seekable: root.canSeek
                    indeterminate: !root.hasLength
                    color: root.accent
                    onSeekTo: fraction => {
                        if (root.canSeek)
                            root.player.position = fraction * root.length;
                    }
                }
                Text {
                    y: 14
                    text: root.hasLength ? root.fmt(bar.dragging ? bar.scrub * root.length : root.position) : ""
                    color: Theme.fgDim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 3
                }
                Text {
                    y: 14
                    anchors.right: parent.right
                    text: root.hasLength ? root.fmt(root.length) : "live"
                    color: Theme.fgDim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize - 3
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 32
                    spacing: 6
                    IconButton {
                        glyph: String.fromCodePoint(0xF04AE)
                        enabled: root.player !== null && root.player.canGoPrevious
                        onClicked: root.player.previous()
                    }
                    IconButton {
                        glyph: root.playing ? String.fromCodePoint(0xF03E4) : String.fromCodePoint(0xF040A)
                        size: 38
                        glyphSize: 22
                        enabled: root.player !== null && root.player.canTogglePlaying
                        onClicked: root.player.togglePlaying()
                    }
                    IconButton {
                        glyph: String.fromCodePoint(0xF04AD)
                        enabled: root.player !== null && root.player.canGoNext
                        onClicked: root.player.next()
                    }
                }
            }
        }
    }
}
