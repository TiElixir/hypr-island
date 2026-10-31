import QtQuick
import qs.core          // Activity, Config, Theme, Events, Windows ...

// The root must be an Activity. ModuleManager sets moduleId and manifest;
// option("key") reads the value from Settings, falling back to the manifest default.
Activity {
    id: root
    accent: "#7aa2f7"

    // Live while the option is on. Use any condition you like.
    active: option("show") === true

    // One size per mode (logical px). Views are laid out at exactly these sizes.
    collapsedSize: Qt.size(96, Config.cfg.sizes.collapsedHeight)
    hoverSize: Qt.size(200, 44)
    expandedSize: Qt.size(280, 100)

    collapsedView: Component {
        Item {                       // each view's root fills the pill's content area
            Text {
                anchors.centerIn: parent
                text: String(root.option("text"))
                color: root.accent
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
            }
        }
    }
    hoverView: Component {
        Item {
            Text {
                anchors.centerIn: parent
                text: root.option("text") + ", hovering"
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
            }
        }
    }
    expandedView: Component {
        Item {
            Text {
                anchors.centerIn: parent
                text: root.option("text") + ", expanded"
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize + 4
            }
        }
    }

    // Optional lifecycle callbacks:
    onShown: console.log("hello: I am the main pill")
    onHidden: console.log("hello: no longer the main pill")
    // bubbleView: Component { ... }   a 26x26 form shown when this is the runner-up
}
