import QtQuick
import Quickshell
import Quickshell.Io

// Finds modules, loads the enabled ones, and owns everything Settings needs
// to change about them (enabled, priority, options).
//
// A module is a directory with a manifest.json and a QML entry file whose root
// extends Activity (see README). Two places are scanned:
//   built-in   <shell dir>/modules/<id>/
//   yours      ~/.config/island/modules/<id>/     (survives upgrades)
// Modules import the shared API with `import qs.core` / `import qs.components`.
// A disabled module is never instantiated: it costs nothing and runs no script.
Scope {
    id: mgr

    readonly property string builtinDir: Quickshell.shellDir + "/modules"
    readonly property string userDir: Quickshell.env("HOME") + "/.config/island/modules"

    // Discovered manifests: { id, name, description, dir, builtin, entry, manifest, error }
    property var modules: []
    // id -> Activity, only for enabled modules.
    property var instances: ({})
    property int rev: 0

    // What the Selector arbitrates between.
    readonly property var all: {
        const _ = rev;
        const out = [];
        for (const id in instances)
            out.push(instances[id]);
        return out;
    }

    property var sources: ({})
    property var errors: ({})

    // ---- discovery ------------------------------------------------------------
    function rescan() {
        if (!lister.running)
            lister.running = true;
    }
    Component.onCompleted: rescan()

    Process {
        id: lister
        command: ["sh", "-c", 'mkdir -p "$2"; for root in "$1" "$2"; do for d in "$root"/*/; do [ -f "${d}manifest.json" ] || continue; d=${d%/}; ' + 'if m=$(jq -c . "$d/manifest.json" 2>/dev/null); then printf "%s\\t%s\\n" "$d" "$m"; else printf "%s\\t!INVALID\\n" "$d"; fi; done; done; exit 0', "sh", mgr.builtinDir, mgr.userDir]
        stdout: StdioCollector {
            onStreamFinished: mgr.ingest(text)
        }
    }

    function ingest(text) {
        const out = [];
        const seen = {};
        for (const line of text.split("\n")) {
            const i = line.indexOf("\t");
            if (i < 1)
                continue;
            const dir = line.slice(0, i);
            const raw = line.slice(i + 1);
            const builtin = dir.indexOf(builtinDir) === 0;
            const rec = { dir: dir, builtin: builtin, id: dir.slice(dir.lastIndexOf("/") + 1), name: dir.slice(dir.lastIndexOf("/") + 1), description: "", entry: "module.qml", manifest: {}, error: "" };
            try {
                if (raw === "!INVALID")
                    throw new Error("manifest.json is not valid JSON");
                const m = JSON.parse(raw);
                if (typeof m.id !== "string" || !/^[a-z0-9_-]+$/.test(m.id))
                    throw new Error("manifest needs an \"id\" of lowercase letters, digits, - or _");
                rec.id = m.id;
                rec.name = m.name || m.id;
                rec.description = m.description || "";
                const entry = m.entry || "module.qml";
                if (typeof entry !== "string" || entry.indexOf("..") >= 0 || entry.charAt(0) === "/" || !/\.qml$/.test(entry))
                    throw new Error("\"entry\" must be a relative .qml file inside the module");
                rec.entry = entry;
                rec.manifest = m;
                if (seen[m.id])
                    throw new Error("duplicate id \"" + m.id + "\" (also in " + seen[m.id] + ")");
                seen[m.id] = dir;
            } catch (e) {
                rec.error = String(e.message || e);
                console.warn("island module " + dir + ": " + rec.error);
            }
            out.push(rec);
        }
        modules = out;
        sync();
    }

    // ---- lifecycle --------------------------------------------------------------
    function recordOf(id) {
        for (const m of modules)
            if (m.id === id && !m.error)
                return m;
        return null;
    }

    function enabledOf(id) {
        const m = recordOf(id);
        const c = Config.cfg.modules[id];
        if (c && c.enabled !== undefined)
            return c.enabled === true;
        return m ? m.manifest.defaultEnabled !== false : false;
    }

    Connections {
        target: Config
        function onCfgChanged() {
            mgr.sync();
        }
    }

    function sync() {
        const next = Object.assign({}, instances);
        let changed = false;
        for (const m of modules) {
            if (m.error)
                continue;
            const want = enabledOf(m.id);
            const have = next[m.id] !== undefined;
            if (want && !have) {
                const o = create(m);
                if (o) {
                    next[m.id] = o;
                    changed = true;
                }
            } else if (!want && have) {
                destroyInstance(m.id, next[m.id]);
                delete next[m.id];
                changed = true;
            }
        }
        for (const id in next) {
            if (recordOf(id) === null) {
                destroyInstance(id, next[id]);
                delete next[id];
                changed = true;
            }
        }
        if (changed) {
            instances = next;
            rev++;
        }
    }

    function setError(id, text) {
        const e = Object.assign({}, errors);
        if (text)
            e[id] = text;
        else
            delete e[id];
        errors = e;
    }

    function create(m) {
        const comp = Qt.createComponent("file://" + m.dir + "/" + m.entry);
        if (comp.status !== Component.Ready) {
            const msg = comp.status === Component.Error ? comp.errorString() : "still loading";
            console.warn("island module " + m.id + " failed to load: " + msg);
            setError(m.id, msg);
            return null;
        }
        const o = comp.createObject(mgr, { moduleId: m.id, manifest: m.manifest });
        if (!o) {
            setError(m.id, "could not create " + m.entry);
            return null;
        }
        setError(m.id, "");
        if (m.manifest.emits && typeof m.manifest.emits === "object")
            for (const ev in m.manifest.emits)
                Events.register(ev, String(m.manifest.emits[ev]), "");
        if (m.manifest.source && typeof m.manifest.source === "object") {
            const sr = sourceComp.createObject(mgr, { inst: o, spec: m.manifest.source, moduleDir: m.dir });
            const s = Object.assign({}, sources);
            s[m.id] = sr;
            sources = s;
        }
        return o;
    }

    Component {
        id: sourceComp
        SourceRunner {}
    }

    function destroyInstance(id, o) {
        const sr = sources[id];
        if (sr) {
            sr.stop();
            sr.destroy();
            const s = Object.assign({}, sources);
            delete s[id];
            sources = s;
        }
        o.destroy();
    }

    // ---- event subscriptions (manifest "subscribe": ["window.*", ...]) -------------
    Connections {
        target: Events
        function onEvent(name, data) {
            for (const id in mgr.instances) {
                const inst = mgr.instances[id];
                const subs = inst.manifest.subscribe;
                if (!subs)
                    continue;
                for (const p of subs) {
                    if (Events.matches(p, name)) {
                        inst.eventReceived(name, data);
                        break;
                    }
                }
            }
        }
    }

    // ---- what Settings reads and writes ---------------------------------------------
    function priorityOf(id) {
        const c = Config.cfg.modules[id];
        if (c && c.priority !== undefined)
            return c.priority;
        const m = recordOf(id);
        return m && m.manifest.priority !== undefined ? m.manifest.priority : 0;
    }

    // Most important first. The ambient clock always stays last.
    readonly property var ordered: {
        const list = modules.filter(m => !m.error);
        list.sort((a, b) => (a.manifest.ambient === true) - (b.manifest.ambient === true) || priorityOf(b.id) - priorityOf(a.id) || a.name.localeCompare(b.name));
        return list;
    }
    readonly property var broken: modules.filter(m => m.error)

    function setEnabled(id, on) {
        Config.set(["modules", id, "enabled"], on);
    }
    function setPriority(id, n) {
        Config.set(["modules", id, "priority"], Math.round(n));
    }

    // Put `above` ahead of `below` by swapping their priorities, so the other
    // modules keep exactly the numbers they had.
    function ensureAbove(above, below) {
        let pa = priorityOf(above), pb = priorityOf(below);
        if (pa > pb)
            return;
        if (pa === pb) {
            setPriority(above, pb + 1);
            return;
        }
        setPriority(above, pb);
        setPriority(below, pa);
    }
    function move(id, dir) {
        if (dir === 0)
            return;
        const list = ordered.filter(m => m.manifest.ambient !== true);
        const i = list.findIndex(m => m.id === id);
        const j = i + dir;
        if (i < 0 || j < 0 || j >= list.length)
            return;
        if (dir < 0)
            ensureAbove(list[i].id, list[j].id);
        else
            ensureAbove(list[j].id, list[i].id);
    }

    function optionSchema(id) {
        const m = recordOf(id);
        return m && m.manifest.options ? m.manifest.options : [];
    }
    function optionValue(id, key) {
        const v = Config.get(["modules", id, "options", key]);
        if (v !== undefined)
            return v;
        for (const o of optionSchema(id))
            if (o.key === key)
                return o.default;
        return undefined;
    }
    function optionIsSet(id, key) {
        return Config.hasUser(["modules", id, "options", key]);
    }
    function setOption(id, key, value) {
        Config.set(["modules", id, "options", key], value);
    }
    function resetOption(id, key) {
        Config.reset(["modules", id, "options", key]);
    }
    function resetModule(id) {
        Config.reset(["modules", id]);
    }

    function statusOf(id) {
        const inst = instances[id];
        if (errors[id])
            return "error";
        if (!inst)
            return "off";
        return inst.live ? "live" : "idle";
    }
    function sourceStatusOf(id) {
        const _ = rev;
        const inst = instances[id];
        return inst && sources[id] ? inst.sourceStatus : "";
    }

    // JSON for `island-ctl modules`.
    function summary() {
        return modules.map(m => ({
                    id: m.id,
                    name: m.name,
                    builtin: m.builtin,
                    enabled: m.error ? false : enabledOf(m.id),
                    priority: m.error ? null : priorityOf(m.id),
                    status: m.error ? "error: " + m.error : statusOf(m.id),
                    source: sourceStatusOf(m.id)
                }));
    }
}
