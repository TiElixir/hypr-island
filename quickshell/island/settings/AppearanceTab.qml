import QtQuick
import qs.core

TabPage {
    SSection {
        title: "Look"
    }
    SettingRow {
        path: ["colors", "bgAlpha"]
        title: "Background opacity"
        description: "Blur behind it comes from the island layer rule in your Hyprland config."
        type: "real"
        min: 0.3
        max: 1
        step: 0.02
    }
    SettingRow {
        path: ["font", "family"]
        title: "Font"
        type: "string"
    }
    SettingRow {
        path: ["font", "size"]
        title: "Font size"
        type: "int"
        min: 9
        max: 20
        unit: "px"
    }
    SettingRow {
        path: ["sizes", "collapsedHeight"]
        title: "Collapsed height"
        description: "Match your Waybar height so the island sits in the bar."
        type: "int"
        min: 18
        max: 40
        unit: "px"
    }
    SettingRow {
        path: ["sizes", "hoverScale"]
        title: "Hover size"
        description: "How big the island grows when you hover over it, relative to its design size."
        type: "real"
        min: 0.6
        max: 1.2
        step: 0.02
    }
    SettingRow {
        path: ["sizes", "expandedScale"]
        title: "Expanded size"
        description: "How much bigger the expanded island is drawn than its design size."
        type: "real"
        min: 1
        max: 1.6
        step: 0.02
    }
    SettingRow {
        path: ["sizes", "flare"]
        title: "Edge flare"
        description: "Radius of the concave curves that join the expanded island to the top edge of the screen. 0 removes them."
        type: "int"
        min: 0
        max: 44
        unit: "px"
    }
    SettingRow {
        path: ["sizes", "maxRadius"]
        title: "Corner radius"
        type: "int"
        min: 8
        max: 40
        unit: "px"
    }

    SSection {
        title: "Status colours"
        subtitle: "Used by the Claude module. Hex like #FF9F0A."
    }
    SettingRow {
        path: ["colors", "running"]
        title: "Working"
        type: "color"
    }
    SettingRow {
        path: ["colors", "needsInput"]
        title: "Needs you"
        type: "color"
    }
    SettingRow {
        path: ["colors", "done"]
        title: "Done"
        type: "color"
    }

    SSection {
        title: "Motion"
        subtitle: "The spring that morphs the pill."
    }
    SettingRow {
        path: ["spring", "spring"]
        title: "Stiffness"
        type: "real"
        min: 1
        max: 8
        step: 0.1
    }
    SettingRow {
        path: ["spring", "damping"]
        title: "Damping"
        description: "Lower is bouncier."
        type: "real"
        min: 0.1
        max: 1
        step: 0.02
    }

    SSection {
        title: "Window"
        subtitle: "The invisible area the pill and clock move in. Must be larger than the biggest expanded pill plus the clock."
    }
    SettingRow {
        path: ["window", "width"]
        title: "Width"
        type: "int"
        min: 600
        max: 1600
        step: 10
        unit: "px"
    }
    SettingRow {
        path: ["window", "height"]
        title: "Height"
        type: "int"
        min: 300
        max: 800
        step: 10
        unit: "px"
    }
    SettingRow {
        path: ["window", "marginTop"]
        title: "Top margin"
        type: "int"
        min: 0
        max: 30
        unit: "px"
    }
}
