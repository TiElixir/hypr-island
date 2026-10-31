import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.core
import qs.settings

ShellRoot {
    id: root

    // Finds, loads and unloads modules (built-in and ~/.config/island/modules).
    ModuleManager {
        id: mods
    }
    Selector {
        id: sel
        activities: mods.all
    }

    // Which screens get an island: "focused" (default), "primary" or "all".
    readonly property var targetScreens: {
        const screens = Quickshell.screens;
        const policy = Config.cfg.monitor.policy;
        if (screens.length === 0)
            return [];
        if (policy === "all") {
            const all = [];
            for (let i = 0; i < screens.length; i++)
                all.push(screens[i]);
            return all;
        }
        let pick = null;
        for (let i = 0; i < screens.length; i++) {
            if (policy === "primary") {
                if (screens[i].name === Config.cfg.monitor.name)
                    pick = screens[i];
            } else {
                const fm = Hyprland.focusedMonitor;
                if (fm && Hyprland.monitorFor(screens[i]) === fm)
                    pick = screens[i];
            }
        }
        return [pick !== null ? pick : screens[0]];
    }

    Variants {
        id: islands
        model: root.targetScreens
        delegate: Island {
            selector: sel
        }
    }

    SettingsPanel {
        screen: root.targetScreens.length > 0 ? root.targetScreens[0] : null
        moduleManager: mods
    }

    Component.onCompleted: {
        Hooks.rescan();
        Events.emit("island.ready", {});
    }

    function reloadAll() {
        mods.rescan();
        Hooks.rescan();
    }

    IpcHandler {
        target: "island"

        function toggle(): void {
            UiBus.toggleRequested();
        }
        function expand(): void {
            UiBus.expandRequested();
        }
        function collapse(): void {
            UiBus.collapseRequested();
        }
        function swap(): void {
            UiBus.swapRequested();
        }
        function settings(tab: string): void {
            UiBus.settingsRequested(tab);
        }
        // mode: "on" | "off" | "toggle" | "config" (follow config.json)
        function keepOnTop(mode: string): string {
            if (mode === "on")
                UiBus.keepOnTopOverride = true;
            else if (mode === "off")
                UiBus.keepOnTopOverride = false;
            else if (mode === "toggle")
                UiBus.keepOnTopOverride = !UiBus.keepOnTop;
            else if (mode === "config")
                UiBus.keepOnTopOverride = null;
            return UiBus.keepOnTop ? "on" : "off";
        }
        // Rescan modules and hook scripts (after adding or editing them).
        function reload(): void {
            root.reloadAll();
        }
        function modules(): string {
            return JSON.stringify(mods.summary());
        }
        function enable(id: string, on: bool): string {
            if (mods.recordOf(id) === null)
                return "unknown module";
            mods.setEnabled(id, on);
            return on ? "enabled" : "disabled";
        }
        // Move a module up (dir -1) or down (+1) in the priority order.
        function moveModule(id: string, dir: int): string {
            if (mods.recordOf(id) === null)
                return "unknown module";
            mods.move(id, dir);
            return JSON.stringify(mods.ordered.map(m => m.id + ":" + mods.priorityOf(m.id)));
        }
        function setPriority(id: string, value: int): string {
            if (mods.recordOf(id) === null)
                return "unknown module";
            mods.setPriority(id, value);
            return "ok";
        }
        function windows(): string {
            return JSON.stringify(Windows.list);
        }
        function focused(): string {
            return JSON.stringify(Windows.focused);
        }
        // Put an event on the bus, as if a module had emitted it.
        function emit(name: string, json: string): string {
            try {
                Events.emit(name, json ? JSON.parse(json) : {});
                return "ok";
            } catch (e) {
                return "invalid JSON: " + e;
            }
        }
        // Dotted path, e.g. "modules.clock.options.format". Prints JSON.
        function config(path: string): string {
            const v = path ? Config.get(path.split(".")) : Config.cfg;
            return JSON.stringify(v === undefined ? null : v);
        }
        function configSet(path: string, json: string): string {
            try {
                Config.set(path.split("."), JSON.parse(json));
                return "ok";
            } catch (e) {
                return "invalid JSON: " + e;
            }
        }
        function configReset(path: string): string {
            Config.reset(path.split("."));
            return "ok";
        }
        function status(): string {
            const p = sel.primary;
            const s = sel.secondary;
            return JSON.stringify({
                primary: p ? p.activityId : null,
                secondary: s ? s.activityId : null,
                live: sel.sorted.map(a => a.activityId),
                keepOnTop: UiBus.keepOnTop,
                fullscreen: Windows.workspaceFullscreen,
                hooks: Hooks.scripts.length,
                windows: islands.instances.map(w => ({
                            screen: w.screen ? w.screen.name : null,
                            mode: w.mode,
                            hovered: w.hovered,
                            shown: w.current ? w.current.activityId : null
                        }))
            });
        }
    }
}
