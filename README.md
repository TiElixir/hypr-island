# Island

A Dynamic-Island-style pill for Hyprland, written for [Quickshell](https://quickshell.org).
It sits at the top-center of the screen and morphs (spring-animated width, height and
corner shape) into whatever is happening. Expanded, it attaches to the top edge of the
screen with concave flares that ease into the edge.

Everything the island shows comes from a **module**. Modules, hooks and settings are all
extensible without touching this repo:

| You want to | Do this |
|---|---|
| Show something new on the island | Drop a module into `~/.config/island/modules/<id>/` |
| Feed a module from a script or an API | Add a `source` to its manifest |
| Run a script when something happens | Drop an executable into `~/.config/island/hooks/<event>/` |
| Tweak or switch things off | Open Settings (`SUPER+ALT+S`) |
| Push a one-off message from a shell script | `island-ctl push` |

Built-in modules: **Music** (Spotify and any MPRIS player), **Claude Code** (session status),
**Cards** (`island-ctl push`) and an optional **Active window**.
The **clock** is not a module: it is always there, centered in the bar while the island is idle,
and slides to the right of the island while the island shows something. Hover for the date,
right-click to open Settings.

Only the pill, its bubble and the clock take mouse input. The rest of the top edge stays clickable.
With two live modules, the runner-up becomes a small bubble beside the pill; click it (or run
`island-ctl swap`) to bring it to the front.

Requirements: Hyprland, Quickshell 0.3+, `jq`, `curl`, Python 3 (installer only),
a Nerd Font (`JetBrainsMono Nerd Font` by default).

## Install / uninstall

```sh
scripts/install.sh --dry-run     # see exactly what would change
scripts/install.sh               # links config hypr waybar
scripts/install.sh claude        # merge the Claude Code hooks (new sessions only)
hyprctl reload && killall -SIGUSR2 waybar
qs -c island                     # or log out and in; it autostarts afterwards

scripts/uninstall.sh             # removes everything below, keeps your modules and hooks
```

Everything outside this repo that the installer touches:

| File | Change | Undo |
|---|---|---|
| `~/.config/quickshell/island` | symlink to `quickshell/island` | removed |
| `~/.local/bin/island-ctl` | symlink to `bin/island-ctl` | removed |
| `~/.config/island/config.json` | your settings (created once, never overwritten) | removed |
| `~/.config/hypr/UserConfigs/Startup_Apps.conf` | `exec-once = qs -c island` | marker block removed |
| `~/.config/hypr/UserConfigs/WindowRules.conf` | blur rules for the `island` and `island-settings` layers | marker block removed |
| `~/.config/hypr/UserConfigs/UserKeybinds.conf` | `SUPER+ALT+I` toggles the island, `SUPER+ALT+S` opens Settings | marker block removed |
| Waybar config (target of `~/.config/waybar/config`) | `clock` and `custom/swaync` leave the top bar's center; swaync moves to the right | `.bak-island` restored |
| `~/.claude/settings.json` | 12 hook entries, backup in `settings.json.bak-island` | exactly those entries removed |

Marker blocks look like `# >>> island >>>` ... `# <<< island <<<`; re-running the installer
refreshes them. The three Hyprland files are the dots' user-owned ones, so dots upgrades leave
them alone. The Waybar file is dots-managed: after a dots upgrade, re-run `scripts/install.sh waybar`.
Runtime files live in `$XDG_RUNTIME_DIR/island/` and `~/.cache/island/art/`.
`~/.config/island/modules/` and `hooks/` are yours and are never removed while they hold files.

## Settings

Open with `SUPER+ALT+S`, `island-ctl settings [tab]`, or right-click the clock. Esc, the close
button, or a click outside closes it. Every change is saved to `config.json` immediately, and each
setting has a reset arrow once you have changed it.

- **General**: monitor, stay above fullscreen windows, clock, hover timings.
- **Modules**: switch each module on or off, reorder with the arrows (or type a priority number),
  see its status and script status, and edit its options. Options are generated from the module's
  `manifest.json`, so your own modules get a settings page for free.
- **Hooks**: every discovered hook script with an on/off switch and a Test button, the event
  catalog, and a live event log while the tab is open.
- **Appearance**: opacity, font, sizes, expanded size, edge flare, colours, spring, window area.
- **Advanced**: file locations, rescan, open the config in your editor, restart, reset everything.

A disabled module is never loaded: it costs nothing and its script does not run.

## Configuration

`~/.config/island/config.json` is deep-merged over the defaults in
`quickshell/island/core/Config.qml`. Edit it by hand (hot-reloaded) or through Settings. Only put
what you want to change. Per-module settings live under `modules.<id>`:

```json
{
  "clock": { "format": "h:mm AP" },
  "sizes": { "expandedScale": 1.3 },
  "modules": {
    "spotify": { "enabled": true, "priority": 80, "options": { "pausedLingerSec": 10 } }
  }
}
```

| Key | Default | Meaning |
|---|---|---|
| `monitor.policy` / `monitor.name` | `"focused"` / `""` | `"focused"`, `"primary"` (uses `name`) or `"all"` |
| `layer.keepOnTop` | `true` | `true`: overlay layer, stays above fullscreen windows. `false`: normal layer, fullscreen windows cover it |
| `clock.enabled` / `format` / `dateFormat` / `gap` | on / `HH:mm:ss` / long date / 14 | The standalone clock. Without an `s` in `format` it only wakes once a minute |
| `sizes.expandedScale` | 1.2 | Expanded views are drawn this much larger than their design size |
| `sizes.flare` | 22 | Radius of the concave flares into the top edge (0 removes them) |
| `sizes.collapsedHeight`, `sizes.maxRadius` | 24, 24 | Pill geometry |
| `window.width/height/marginTop` | 920 / 460 / 3 | The invisible area the pill and clock move in; must exceed the biggest expanded pill plus the clock |
| `timings.hoverInMs` / `hoverOutMs` | 80 / 250 | Hover intent and leave delay |
| `timings.expandedLeaveMs` / `expandedIdleMs` | 600 / 5000 | Expanded collapses this long after the pointer leaves / when never hovered |
| `timings.collapseOnLeave` | `true` | Disable to keep it expanded until toggled |
| `behavior.focusGrab` | `false` | Experimental click-outside-to-collapse. On Hyprland 0.56 it stops hover from being reported while expanded |
| `spring.spring/damping/epsilon` | 3.0 / 0.32 / 0.25 | Animation feel. Lower damping is bouncier |
| `colors.bgAlpha`, `colors.running/needsInput/done` | 0.9, orange, red, green | Background opacity and Claude status colours |
| `font.family/size` | JetBrainsMono Nerd Font / 13 | |
| `hooks.enabled/timeoutSec/minIntervalMs/disabled` | on / 10 / 250 / `[]` | Event hook runner |
| `modules.<id>.enabled/priority/options` | from the manifest | Per-module settings |

Older configs with flat `spotify`, `claude`, `external`, `enabled` and `priorities` keys are migrated
automatically and rewritten in the `modules` layout the first time Settings saves.

## Writing a module

A module is a folder with a `manifest.json` and a QML file whose root is an `Activity`.
Put it in `~/.config/island/modules/<id>/` (built-ins live in `quickshell/island/modules/`),
then `island-ctl reload` and enable it in Settings. A complete one is in
[`docs/examples/hello`](docs/examples/hello).

```
~/.config/island/modules/hello/
├── manifest.json
└── module.qml
```

### manifest.json

```json
{
  "id": "hello",                    // required: lowercase letters, digits, - _
  "name": "Hello",                  // shown in Settings
  "description": "One line.",
  "entry": "module.qml",            // default module.qml
  "priority": 65,                   // who wins the island; higher wins
  "defaultEnabled": true,           // false: the user switches it on in Settings
  "ambient": false,                 // true: always last in the order, not reorderable
  "subscribe": ["window.*"],        // event patterns delivered to onEventReceived
  "emits": { "hello.waved": "Documented in Settings > Hooks" },
  "source": { "...": "see Scripts" },
  "options": [
    { "key": "text", "type": "string", "default": "hello", "label": "Greeting", "description": "..." }
  ]
}
```

Option `type` is one of `bool`, `int`, `real` (give `min` and `max` for a slider, optional `step`
and `unit`), `string`, `enum` (needs `choices`), `color` (`#RRGGBB`) and `list` (array of strings,
edited as comma separated text). Read a value with `option("key")` inside a binding and it updates
live when the user changes it. Validate a manifest with `tests/manifest-test.sh path/to/module`.

### module.qml

```qml
import QtQuick
import qs.core                // Activity, Config, Theme, Events, Windows, Feed ...
import qs.components          // ProgressRing, SeekBar, IconButton, StateDot, GlyphIcon ...

Activity {
    id: root
    accent: "#7aa2f7"
    active: option("show") === true            // live or not: any condition

    collapsedSize: Qt.size(96, Config.cfg.sizes.collapsedHeight)   // logical px, one per mode
    hoverSize: Qt.size(200, 44)
    expandedSize: Qt.size(280, 100)            // drawn expandedScale times larger

    collapsedView: Component { Item { /* root fills the pill's content area */ } }
    hoverView:     Component { Item { } }
    expandedView:  Component { Item { } }
    bubbleView:    Component { Item { } }      // optional, 26x26, shown when runner-up

    onShown: console.log("I am the main pill")
}
```

The `Activity` interface (full comments in `core/Activity.qml`):

- **Properties you set:** `active`, `accent`, `urgent` (takes the island immediately, even
  mid-hover), `priority` (fallback), `effectivePriority` (override to vary with state, as Claude
  does), the three sizes, the four views.
- **Read-only context:** `moduleId`, `manifest`, `basePriority` (Settings > manifest), `option(key)`,
  `hostMode` (`collapsed`/`hover`/`expanded`), `hostHovered`, `hostPresented`, `hostBubble`.
- **Lifecycle signals:** `shown`, `hidden`, `modeChanged(mode)`. Gate timers on `hostMode` so nothing
  runs while your module is not visible.
- **Callbacks:** `onActivated(mode)` on a click while not expanded (return `false` to handle the
  click without expanding), `acknowledge()`.
- **Events:** `emit("name", {data})` puts `<moduleId>.name` on the bus; `onEventReceived(name, data)`
  gets the events matching `subscribe`.
- **Script data:** `sourceData`, `sourceStatus`, `onSourceMessage(msg)`.

Rules of thumb: no polling, timers only while something visible needs them, and never errors when
your data source is missing. Edits to a user module apply after `island-ctl restart` (the
built-in ones hot-reload while you develop with `qs -p quickshell/island`).

### Scripts (`source`)

A module can be fed by a script the island runs and restarts for it, and only while the module is
enabled. This is how you bring in data from anywhere (an HTTP API, a file, another program) without
writing QML for the plumbing.

```json
"source": {
  "command": ["python3", "fetch.py"],   // runs in the module's folder
  "mode": "poll",                       // "poll": run every intervalSec. "stream": one long-running process
  "intervalSec": 30,                    // or "intervalOption": "pollSec" to use a module option
  "timeoutSec": 20,                     // poll mode
  "restartSec": 5                       // stream mode: restart delay, backs off on repeated failure
}
```

- Every stdout line that is a JSON object becomes `onSourceMessage(msg)` and `sourceData`.
  Other text arrives as `{"text": "..."}`.
- A line like `{"_event": "updated", "n": 3}` also emits `<moduleId>.updated` on the bus, so hooks
  can react to what your script reports.
- The script sees `ISLAND_MODULE_ID`, `ISLAND_MODULE_DIR`, `ISLAND_CTL` and every option as
  `ISLAND_OPT_<KEY>`. It restarts when an option changes. stderr goes to the island's log.
- `sourceStatus` is `running`, `ok`, `error: ...`, or `exited (code), restarting in Ns`; Settings
  shows it on the module's card.

### Window data

The `Windows` singleton (event driven, backed by Hyprland) is available to every module and script:
`Windows.focused`, `Windows.list`, `Windows.count`, `Windows.workspace`, `Windows.workspaceFullscreen`.
Each window has `address`, `title`, `class`, `initialClass`, `pid`, `workspace`, `floating`,
`fullscreen`, `urgent`. From a shell: `island-ctl windows`, `island-ctl focused`.
`modules/windowfocus` is a small module built on it (off by default).

## Event hooks

An executable file in `~/.config/island/hooks/<event>/` runs every time that event fires:

```sh
mkdir -p ~/.config/island/hooks/claude.state
cp docs/examples/hooks/claude.state/10-notify.sh ~/.config/island/hooks/claude.state/
chmod +x ~/.config/island/hooks/claude.state/10-notify.sh
island-ctl reload
```

The payload arrives as JSON on stdin, in `$ISLAND_DATA`, and as flat variables `$ISLAND_<FIELD>`
(`$ISLAND_PROJECT`, `$ISLAND_TO`, ...), plus `$ISLAND_EVENT` and `$ISLAND_CTL`. Hooks run in a pool of
four, are killed after `hooks.timeoutSec`, and the same script is not restarted within
`hooks.minIntervalMs`, so a noisy event cannot flood you. Switch single hooks off or test them in
Settings > Hooks. Events (Settings > Hooks lists them live):

| Event | Payload |
|---|---|
| `window.focus`, `window.title` | address, title, class, pid, workspace |
| `window.open`, `window.close`, `workspace.change` | address, class, title, workspace / name |
| `spotify.track` | title, artist, album, player |
| `spotify.state` | state (`playing`/`paused`), player |
| `claude.state` | session, project, from, to (`running`, `needs_input`, `done`, `error`, `idle`, `ended`) |
| `external.card` | id, title, subtitle |
| `island.mode`, `island.primary`, `island.ready` | mode, activity |
| `<module>.<name>` | whatever the module or its script emits |

Test one without waiting for it: `island-ctl emit claude.state '{"to":"needs_input","project":"demo"}'`.

## island-ctl

```sh
island-ctl push --id vol --title "Volume 40%" --icon 󰕾 --progress 40 --timeout 2
island-ctl push --id build --title "Build failed" --subtitle "exit 2" --color "#FF453A" --timeout 0
island-ctl clear --id build        # or --all
island-ctl list                    # active cards and Claude sessions
island-ctl toggle | expand | collapse | swap
island-ctl settings [tab]
island-ctl modules                 # enabled, priority, status per module
island-ctl module enable|disable|up|down <id>   |   island-ctl module priority <id> <n>
island-ctl reload                  # rescan modules and hook scripts
island-ctl windows | focused       # JSON
island-ctl emit <event> [json]
island-ctl config get [path] | set <path> <json> | reset <path>    # dotted path
island-ctl keep-on-top on|off|toggle|config [--save]
island-ctl status | focus <pid> | restart
```

`--icon` is a Nerd Font glyph/emoji or an absolute image path. `--timeout 0` makes a card sticky.
Cards are files, so pushing works while the island is stopped.

## Claude Code bridge

`hooks/claude-island-hook.sh` is registered for 12 Claude Code events and writes one file per
session, atomically, to `$XDG_RUNTIME_DIR/island/claude/<session_id>.json`, then rewrites `.tick`
in place. The island watches only `.tick` (Quickshell can watch files, not directories) and rescans.
State files survive island restarts and work with the island stopped. (These are Claude Code's
hooks; the *event hooks* above are the island's.)

| Event | State |
|---|---|
| `SessionStart` (startup, resume, clear, fork) | idle (registered) |
| `UserPromptSubmit`, `PostToolUse`, `PostToolUseFailure`, `PermissionDenied`, `ElicitationResult` | running |
| `PermissionRequest`, `Elicitation`, `Notification` (`permission_prompt`, `elicitation_dialog`, `agent_needs_input`) | needs_input (red) |
| `Stop` | done (green); running if `background_tasks` is non-empty |
| `StopFailure` | error (red) |
| `Notification` `idle_prompt`, `SubagentStop`, `SessionStart` (compact) | no change |
| `SessionEnd` | session removed |

The hook prints nothing, always exits 0, has a 2 s timeout and does nothing if `jq` or the runtime
dir is missing. It averages about 16 ms. Known limits:

- **Red stays until the next event after you approve.** Claude Code has no "permission granted"
  hook, so after approving a long-running tool the pill stays red until `PostToolUse`.
- `PreToolUse` is deliberately not hooked: `UserPromptSubmit` and `PostToolUse` already cover
  "running", and skipping it halves per-tool-call overhead.
- Claude Code reports `Notification` hooks as not firing in the VS Code extension;
  `PermissionRequest` is the primary red trigger for that reason.
- Window focusing walks the session's process tree up to a Hyprland client. In Lua-mode Hyprland
  (`hyprland.lua`) `island-ctl focus` uses a best-effort `hyprctl dispatch` Lua expression that has
  **not** been tested; hyprlang mode is tested.

## Layout

```
quickshell/island/
├── shell.qml            wiring, IPC
├── core/                island window, pill, config, theme, events, hooks, module manager, windows service
├── modules/             built-in modules: claude, spotify, external, windowfocus
├── components/          shared widgets for modules
└── settings/            the Settings panel
bin/island-ctl           CLI
hooks/                   Claude Code hook
scripts/                 install, uninstall, settings.json merger
docs/examples/           hello module, example event hooks
tests/                   hook-test.sh, manifest-test.sh, fake-mpris.py
config/                  config.example.json
```

## Testing without the real thing

```sh
tests/hook-test.sh                       # Claude hook state machine, in a private runtime dir
tests/manifest-test.sh                   # validate module manifests
python3 tests/fake-mpris.py              # fake "Spotify" for playerctl and the island
python3 tests/fake-mpris.py --no-length  # ad/podcast with length 0
island-ctl emit window.focus '{"class":"demo","title":"hi"}'    # drive modules and hooks
echo '{"session_id":"t","cwd":"/tmp/demo","hook_event_name":"PermissionRequest"}' | hooks/claude-island-hook.sh
island-ctl status                        # what the island thinks is live
hyprctl layers | grep island             # layers, sizes, namespaces
```

During development run it straight from the repo with `qs -p quickshell/island`;
`qs log -c island` shows its log.

## Troubleshooting

- **Nothing shows:** `qs log -c island`, and `hyprctl layers | grep island`.
- **Two clocks:** Waybar's top bar still has `clock` in `modules-center`; run `scripts/install.sh waybar`.
- **No blur:** `hyprctl reload`, then `island-ctl restart` so the layer rules apply to a fresh surface.
- **My module is not listed:** `island-ctl reload`, then check Settings > Modules for an error card
  (invalid manifest, duplicate id, QML error). `tests/manifest-test.sh <dir>` explains manifest problems.
- **A hook never runs:** it must be executable, in a folder named exactly like the event, and not
  switched off in Settings > Hooks. Its last failure is shown there.
- **Claude never lights up:** hooks apply to sessions started after `install.sh claude`. Check
  `ls $XDG_RUNTIME_DIR/island/claude` while a session runs.
