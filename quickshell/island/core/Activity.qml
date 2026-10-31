import QtQuick

// Base type for every activity. An activity is one self-contained module:
// it decides when it is live, how important it is, and what it looks like in
// each island mode. See README.md for how to add one.
QtObject {
    id: act

    // Lets an activity declare helpers (Timer, Process, SystemClock...) inline.
    default property list<QtObject> resources

    // ---- identity & arbitration ------------------------------------------
    property string activityId: ""
    // Subclasses bind this to their own condition.
    property bool active: false
    // Base priority. config.json "priorities.<activityId>" overrides it.
    property int priority: 0
    property color accent: Theme.accent
    // Ambient activities (the clock) are always present and render blended
    // into the bar when collapsed.
    property bool ambient: false
    // Urgent activities take over the island immediately, even mid-hover.
    property bool urgent: false

    readonly property bool enabled: Config.cfg.enabled[activityId] !== false
    readonly property bool live: enabled && active
    property int effectivePriority: {
        const o = Config.cfg.priorities[activityId];
        return o !== undefined ? o : priority;
    }

    // ---- geometry per mode (logical pixels) ------------------------------
    property size collapsedSize: Qt.size(100, Config.cfg.sizes.collapsedHeight)
    property size hoverSize: collapsedSize
    property size expandedSize: hoverSize

    // ---- views, rendered inside the clipped pill -------------------------
    // Each view's root should use anchors.fill: parent. It is sized to the
    // matching *Size above, so layout never depends on the animated pill size.
    property Component collapsedView: null
    property Component hoverView: null
    property Component expandedView: null
    // Compact form shown when this is the runner-up (side bubble).
    property Component bubbleView: null

    // ---- host -> activity -------------------------------------------------
    // Called when the pill is clicked while not expanded. Return false to
    // handle the click without expanding (e.g. acknowledging a status).
    function onActivated(mode) {
        return true;
    }
    function acknowledge() {
    }

    // ---- host state, written by the island showing this activity ---------
    property string hostMode: "collapsed"
    property bool hostHovered: false

    // ---- activity -> host -------------------------------------------------
    // Ask the island to promote this activity now and pulse.
    signal attention

    function sizeFor(mode) {
        return mode === "expanded" ? expandedSize : mode === "hover" ? hoverSize : collapsedSize;
    }
    function viewFor(mode) {
        return mode === "expanded" ? expandedView : mode === "hover" ? hoverView : collapsedView;
    }
}
