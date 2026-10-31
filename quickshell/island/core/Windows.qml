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
            address: String(t.address),
            title: String(t.title),
            "class": String(o["class"] || ""),
            initialClass: String(o.initialClass || ""),
            pid: Number(o.pid) || 0,
            workspace: ws.name !== undefined ? String(ws.name) : "",
            workspaceId: Number(ws.id) || 0,
            floating: o.floating === true,
            fullscreen: Number(o.fullscreen) > 0,
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
    readonly property bool workspaceFullscreen: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.hasFullscreen === true : false

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
    Connections {
        target: Hyprland
        function onActiveToplevelChanged() {
            focusTimer.restart();
        }
        function onRawEvent(ev) {
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
