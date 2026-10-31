pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland

// What is open and what has focus, for modules, hooks and `island-ctl windows`.
// Backed by Quickshell.Hyprland, so it is event driven: nothing polls.
Singleton {
    id: root

    function describe(t) {
        if (!t)
            return null;
        const o = t.lastIpcObject || {};
        const ws = o.workspace || (t.workspace ? { id: t.workspace.id, name: t.workspace.name } : {});
        return {
            address: String(t.address).indexOf("0x") === 0 ? String(t.address) : "0x" + String(t.address),
            title: String(t.title),
            "class": String(o["class"] || ""),
            initialClass: String(o.initialClass || ""),
            pid: Number(o.pid) || 0,
            workspace: ws.name !== undefined ? String(ws.name) : "",
            workspaceId: Number(ws.id) || 0,
            floating: o.floating === true,
            // Hyprland: 0 none, 1 maximized (bars stay visible), 2 fullscreen
            maximized: Number(o.fullscreen) === 1,
            fullscreen: Number(o.fullscreen) >= 2,
            urgent: t.urgent === true
        };
    }

    readonly property var focused: describe(Hyprland.activeToplevel)
    readonly property var list: {
        const out = [];
        const v = Hyprland.toplevels.values;
        for (let i = 0; i < v.length; i++)
            out.push(describe(v[i]));
        return out;
    }
    readonly property int count: list.length
    readonly property string workspace: Hyprland.focusedWorkspace ? String(Hyprland.focusedWorkspace.name) : ""
    // True only for a really fullscreen window on the focused workspace.
    // Hyprland's own hasFullscreen is also true for a merely maximized window,
    // where the bars are still on screen.
    readonly property bool workspaceFullscreen: {
        const ws = Hyprland.focusedWorkspace;
        if (!ws)
            return false;
        for (const w of list)
            if (w.fullscreen && w.workspaceId === ws.id)
                return true;
        return false;
    }

    // ---- events ------------------------------------------------------------
    // Focus and title changes are coalesced so a busy browser tab cannot flood hooks.
    Timer {
        id: focusTimer
        interval: 60
        onTriggered: Events.emit("window.focus", root.focused || {})
    }
    Timer {
        id: titleTimer
        interval: 150
        onTriggered: {
            const f = root.focused;
            if (f)
                Events.emit("window.title", { address: f.address, title: f.title, "class": f["class"] });
        }
    }
    // Hyprland does not refresh a window's data (fullscreen state, workspace)
    // by itself when it changes, so ask for it on the events that change it.
    Timer {
        id: refreshTimer
        interval: 80
        onTriggered: Hyprland.refreshToplevels()
    }
    Connections {
        target: Hyprland
        function onActiveToplevelChanged() {
            focusTimer.restart();
        }
        function onRawEvent(ev) {
            if (ev.name === "fullscreen" || ev.name === "workspacev2" || ev.name === "movewindowv2")
                refreshTimer.restart();
            if (ev.name === "openwindow") {
                const p = ev.data.split(",");
                Events.emit("window.open", { address: "0x" + p[0], workspace: p[1] || "", "class": p[2] || "", title: p.slice(3).join(",") });
            } else if (ev.name === "closewindow") {
                Events.emit("window.close", { address: "0x" + ev.data });
            } else if (ev.name === "workspacev2") {
                Events.emit("workspace.change", { name: ev.data.split(",").slice(1).join(",") });
            }
        }
    }
    Connections {
        target: Hyprland.activeToplevel
        ignoreUnknownSignals: true
        function onTitleChanged() {
            titleTimer.restart();
        }
    }
}
