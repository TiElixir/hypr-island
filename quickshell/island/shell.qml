import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "core"
import "activities"

ShellRoot {
    id: root

    Registry {
        id: registry
    }
    Selector {
        id: sel
        activities: registry.all
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
        id: windows
        model: root.targetScreens
        delegate: Island {
            selector: sel
        }
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
        function status(): string {
            const p = sel.primary;
            const s = sel.secondary;
            return JSON.stringify({
                primary: p ? p.activityId : null,
                secondary: s ? s.activityId : null,
                live: sel.sorted.map(a => a.activityId),
                keepOnTop: UiBus.keepOnTop,
                windows: windows.instances.map(w => ({
                            screen: w.screen ? w.screen.name : null,
                            mode: w.mode,
                            hovered: w.hovered,
                            shown: w.current ? w.current.activityId : null
                        }))
            });
        }
    }
}
