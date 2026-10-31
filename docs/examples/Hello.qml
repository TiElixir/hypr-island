import QtQuick
import "../core"

Activity {
    id: root
    activityId: "hello"              // key for config priorities / enabled
    priority: 65                     // base priority; "priorities.hello" in config.json overrides
    accent: "#7aa2f7"

    // Live whenever config.json says {"hello": {"show": true}}. Edit the file and
    // it appears or disappears without a restart. Use any condition you like.
    active: Config.cfg.hello !== undefined && Config.cfg.hello.show === true

    // One size per mode (logical px). Views are laid out at exactly these sizes.
    collapsedSize: Qt.size(96, Config.cfg.sizes.collapsedHeight)
    hoverSize: Qt.size(200, 44)
    expandedSize: Qt.size(280, 100)

    collapsedView: Component {
        Item {                        // each view's root fills the pill's content area
            Text {
                anchors.centerIn: parent
                text: "hello"
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
                text: "hello, hovering"
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
                text: "hello, expanded"
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize + 4
            }
        }
    }
    // bubbleView: Component { ... }  a 26x26 form shown when this is the runner-up
}
