pragma Singleton

import QtQuick
import Quickshell

// The shared event bus. Modules, the windows service and the island itself
// emit named events with a JSON-able payload; modules subscribe (manifest
// "subscribe" or Connections) and event hooks (Hooks.qml) run scripts for them.
//
// Names are dotted and namespaced by their source: "window.focus",
// "spotify.track", "claude.state", "island.mode", "mymodule.something"...
Singleton {
    id: root

    signal event(string name, var data)

    // name -> { description, fields }. Documentation for Settings and for
    // people writing hooks; emitting an unregistered event is always fine.
    property var catalog: ({
        "window.focus": { description: "The focused window changed", fields: "address, title, class, pid, workspace" },
        "window.title": { description: "The focused window's title changed", fields: "address, title, class" },
        "window.open": { description: "A window opened", fields: "address, class, title, workspace" },
        "window.close": { description: "A window closed", fields: "address" },
        "workspace.change": { description: "The focused workspace changed", fields: "name" },
        "island.mode": { description: "The pill went collapsed / hover / expanded", fields: "mode, activity" },
        "island.primary": { description: "A different module took the pill", fields: "activity" },
        "spotify.track": { description: "The playing track changed", fields: "title, artist, album, player" },
        "spotify.state": { description: "Playback started, paused or stopped", fields: "state, player" },
        "claude.state": { description: "A Claude Code session changed state", fields: "session, project, from, to" },
        "external.card": { description: "A card was pushed with island-ctl", fields: "id, title, subtitle" }
    })

    // Ring buffer of the latest events, filled only while Settings shows it.
    property bool recording: false
    property var recent: []

    function emit(name, data) {
        const d = data === undefined || data === null ? {} : data;
        if (recording) {
            const r = recent.slice(-39);
            r.push({ t: Date.now(), name: name, data: d });
            recent = r;
        }
        event(name, d);
    }

    // Modules can document the events they emit (manifest "emits" does it for you).
    function register(name, description, fields) {
        const c = Object.assign({}, catalog);
        c[name] = { description: description || "", fields: fields || "" };
        catalog = c;
    }

    // "window.*" matches window.focus; "*" matches everything.
    function matches(pattern, name) {
        if (pattern === "*" || pattern === name)
            return true;
        return pattern.slice(-2) === ".*" && name.indexOf(pattern.slice(0, -1)) === 0;
    }
}
