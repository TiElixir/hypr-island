import QtQuick

// Base type for every activity. An activity is one self-contained module:
// it decides when it is live, how important it is, and what it looks like in
// each island mode. See README.md for how to add one.
QtObject {
    id: act

    // Lets an activity declare helpers (Timer, Process, SystemClock...) inline.
    default property list<QtObject> resources

    // ---- identity (set by ModuleManager from manifest.json) -----------------
    property string moduleId: ""
    property var manifest: ({})
    property string activityId: moduleId

    // ---- options ------------------------------------------------------------
    // Values come from the manifest's "options" schema, overridden by
    // config.json modules.<id>.options and edited in Settings. Call option()
    // inside a binding and it re-evaluates when the setting changes.
    readonly property var moduleCfg: Config.cfg.modules[moduleId] || ({})
    readonly property var optionDefaults: {
        const d = {};
        const o = manifest.options || [];
        for (let i = 0; i < o.length; i++)
            d[o[i].key] = o[i].default;
        return d;
    }
    function option(key) {
        const o = moduleCfg.options;
        return o && o[key] !== undefined ? o[key] : optionDefaults[key];
    }

    // ---- arbitration --------------------------------------------------------
    // Subclasses bind this to their own condition.
    property bool active: false
    // Fallback when the manifest has no priority.
    property int priority: 0
    // Settings priority (config.json modules.<id>.priority) > manifest > `priority`.
    readonly property int basePriority: moduleCfg.priority !== undefined ? moduleCfg.priority : (manifest.priority !== undefined ? manifest.priority : priority)
    // A module may override this to vary with its own state (Claude does).
    property int effectivePriority: basePriority
    property color accent: Theme.accent
    // Ambient activities (the clock) are always present and render blended
    // into the bar when collapsed.
    property bool ambient: manifest.ambient === true
    // Urgent activities take over the island immediately, even mid-hover.
    property bool urgent: false

    readonly property bool live: active

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
    // On screen as the main pill / as the side bubble.
    property bool hostPresented: false
    property bool hostBubble: false

    // ---- lifecycle callbacks: implement with onShown: { ... } ---------------
    signal shown        // became the main pill
    signal hidden       // stopped being the main pill
    signal modeChanged(string mode)   // collapsed | hover | expanded, while shown
    onHostPresentedChanged: hostPresented ? shown() : hidden()
    onHostModeChanged: modeChanged(hostMode)

    // ---- events, options, scripts -------------------------------------------
    // Emit "<moduleId>.<name>" on the shared bus (hooks and other modules see it).
    function emit(name, data) {
        Events.emit(moduleId + "." + name, data);
    }
    // Delivered for the patterns in manifest "subscribe" (e.g. "window.*").
    signal eventReceived(string name, var data)
    // Fed by the manifest's "source" script: one signal per JSON line it prints.
    property var sourceData: null
    property string sourceStatus: "off"
    signal sourceMessage(var msg)

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
