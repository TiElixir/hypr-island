import QtQuick
import qs.core

TabPage {
    SSection {
        title: "Display"
        subtitle: "Where the island appears."
    }
    SettingRow {
        path: ["monitor", "policy"]
        title: "Show on"
        description: "The focused monitor follows you around; the island moves with focus."
        type: "enum"
        choices: [
            { value: "focused", label: "Focused monitor" },
            { value: "primary", label: "One monitor" },
            { value: "all", label: "All monitors" }
        ]
    }
    SettingRow {
        path: ["monitor", "name"]
        title: "Monitor name"
        description: "Used by \"One monitor\". List them with hyprctl monitors."
        type: "string"
    }
    SettingRow {
        path: ["layer", "keepOnTop"]
        title: "Stay on top of fullscreen windows"
        description: "On: overlay layer, the island stays visible over fullscreen apps. Off: normal layer, fullscreen windows cover it."
        type: "bool"
    }

    SSection {
        title: "Clock"
        subtitle: "Always shown, separate from the island. It sits in the middle of the bar and moves to the right of the island while the island is showing something. Right-click it for these settings."
    }
    SettingRow {
        path: ["clock", "enabled"]
        title: "Show the clock"
        type: "bool"
    }
    SettingRow {
        path: ["clock", "format"]
        title: "Time format"
        description: "Qt format string, e.g. HH:mm:ss or h:mm AP. Without an s the clock only wakes once a minute."
        type: "string"
    }
    SettingRow {
        path: ["clock", "hideInFullscreen"]
        title: "Hide in fullscreen"
        description: "The island can stay above a fullscreen window (see above); the clock goes away."
        type: "bool"
    }
    SettingRow {
        path: ["clock", "gap"]
        title: "Gap to the island"
        type: "int"
        min: 4
        max: 60
        unit: "px"
    }

    SSection {
        title: "Behaviour"
        subtitle: "How the pill reacts to the pointer."
    }
    SettingRow {
        path: ["timings", "hoverInMs"]
        title: "Hover delay"
        description: "How long the pointer rests before the pill grows."
        type: "int"
        min: 0
        max: 600
        step: 10
        unit: "ms"
    }
    SettingRow {
        path: ["timings", "hoverOutMs"]
        title: "Hover leave delay"
        type: "int"
        min: 0
        max: 2000
        step: 25
        unit: "ms"
    }
    SettingRow {
        path: ["timings", "collapseOnLeave"]
        title: "Collapse when the pointer leaves"
        description: "Applies to the expanded view. Off: it stays open until you click it or press SUPER+ALT+I."
        type: "bool"
    }
    SettingRow {
        path: ["timings", "expandedLeaveMs"]
        title: "Expanded leave delay"
        type: "int"
        min: 0
        max: 5000
        step: 50
        unit: "ms"
    }
    SettingRow {
        path: ["timings", "expandedIdleMs"]
        title: "Idle collapse"
        description: "Opened by keybind but never hovered: collapse after this long."
        type: "int"
        min: 1000
        max: 60000
        step: 500
        unit: "ms"
    }

    SSection {
        title: "Experimental"
    }
    SettingRow {
        path: ["behavior", "focusGrab"]
        title: "Click outside to collapse"
        description: "Uses a Hyprland focus grab. On Hyprland 0.56 it stops hover from being reported while expanded, so leaving no longer collapses."
        type: "bool"
    }

    SSection {
        title: "Shortcuts"
        subtitle: "Bound in ~/.config/hypr/UserConfigs/UserKeybinds.conf"
    }
    Text {
        width: parent.width
        topPadding: 8
        bottomPadding: 8
        lineHeight: 1.5
        text: "SUPER + ALT + I      toggle the island\nSUPER + ALT + S      open these settings"
        color: Theme.fgDim
        font.family: "monospace"
        font.pixelSize: Theme.fontSize - 2
    }
}
