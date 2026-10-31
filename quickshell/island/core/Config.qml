pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// User config lives in ~/.config/island/config.json and is deep-merged over
// `defaults`. The file is watched, so edits apply without a restart.
Singleton {
    id: root

    readonly property string path: Quickshell.env("HOME") + "/.config/island/config.json"

    readonly property var defaults: ({
        // "focused" | "primary" | "all"
        monitor: { policy: "focused", name: "" },
        // keepOnTop: true  -> overlay layer, island stays above fullscreen windows
        //            false -> top layer, fullscreen windows cover it
        layer: { keepOnTop: true },
        window: { width: 620, height: 270, marginTop: 3 },
        sizes: { collapsedHeight: 24, maxRadius: 24 },
        timings: {
            hoverInMs: 80,
            hoverOutMs: 250,
            expandedLeaveMs: 600,
            // Opened by keybind but the pointer never came near: collapse after this.
            expandedIdleMs: 5000,
            collapseOnLeave: true
        },
        behavior: {
            // Experimental. Grabs input while expanded so an outside click
            // collapses it, but on Hyprland 0.56 it stops the pill from seeing
            // hover, so leave-to-collapse stops working. Off by default.
            focusGrab: false
        },
        spring: { spring: 3.0, damping: 0.32, epsilon: 0.25 },
        colors: {
            bgAlpha: 0.9,
            running: "#FF9F0A",
            needsInput: "#FF453A",
            done: "#30D158"
        },
        font: { family: "JetBrainsMono Nerd Font", size: 13 },
        clock: {
            // Qt date format. Without an "s" the clock only wakes once a minute.
            format: "HH:mm:ss",
            dateFormat: "dddd, d MMMM yyyy",
            collapsedWidth: 104
        },
        spotify: {
            // First entry that matches wins. Matches dbus name or identity,
            // case-insensitive. "*" matches anything. Players that are playing
            // are preferred over paused ones before priority is applied.
            playerPriority: ["spotify", "*"],
            // Keep showing a paused player for this long, then fall back.
            pausedLingerSec: 60
        },
        claude: {
            // Sessions silent for this long are dropped (a running session
            // with a live process is exempt, long tools send no events).
            staleTimeoutMin: 30,
            // How often dead processes are swept, only while sessions exist.
            sweepSec: 30,
            // Hovering a green pill this long (cumulative) acknowledges it.
            hoverAckMs: 3000,
            // 0 = green stays until clicked or hovered. > 0 = also fade after N s.
            doneFadeSec: 0,
            // Clicking a session row focuses the terminal window it runs in.
            focusOnClick: true
        },
        external: {
            // Used when `island-ctl push` gives no --timeout of its own.
            defaultTimeoutSec: 5
        },
        // Higher wins the primary slot, the runner-up becomes the side bubble.
        priorities: {
            claude_needs_input: 100,
            external: 70,
            spotify: 60,
            claude_running: 55,
            claude_done: 40,
            clock: 0
        },
        enabled: { clock: true, spotify: true, claude: true, external: true }
    })

    property var user: ({})
    readonly property var cfg: merge(defaults, user)

    function isObj(v) {
        return v !== null && typeof v === "object" && !Array.isArray(v);
    }

    function merge(a, b) {
        if (!isObj(a) || !isObj(b))
            return b === undefined ? a : b;
        const out = {};
        for (const k in a)
            out[k] = a[k];
        for (const k in b)
            out[k] = isObj(a[k]) && isObj(b[k]) ? merge(a[k], b[k]) : b[k];
        return out;
    }

    FileView {
        path: root.path
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const parsed = JSON.parse(text());
                root.user = root.isObj(parsed) ? parsed : {};
            } catch (e) {
                console.warn("island: ignoring invalid config.json:", e);
                root.user = {};
            }
        }
        onLoadFailed: root.user = {}
    }
}
