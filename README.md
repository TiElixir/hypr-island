# Island

A Dynamic-Island-style pill for Hyprland, written for [Quickshell](https://quickshell.org).
It sits at the top-center of the screen, blends into the bar while idle, and morphs
(spring-animated width, height and corner radius) into whatever is happening:

| Activity | Collapsed | Hover | Click |
|---|---|---|---|
| **Clock** (always on) | `HH:MM:SS`, blended into the bar | + date | big clock |
| **Spotify** (MPRIS) | album art with a progress ring | title, artist, progress | art, times, seekable bar, prev / play-pause / next |
| **Claude Code** | status dot (orange working, red needs you, green done) | top session summary | every session: project, state, time in state |
| **Cards** (`island-ctl push`) | icon + title | + subtitle | detail, progress, dismiss |

Only the pill takes mouse input. The rest of the top edge stays clickable.
With two live activities the runner-up becomes a small bubble beside the pill;
click it (or run `island-ctl swap`) to bring it to the front.

Requirements: Hyprland, Quickshell 0.3+, `jq`, `curl`, Python 3 (installer only),
a Nerd Font (`JetBrainsMono Nerd Font` by default).

## Install / uninstall

```sh
scripts/install.sh --dry-run     # see exactly what would change
scripts/install.sh               # links config hypr waybar
scripts/install.sh claude        # merge the Claude Code hooks (new sessions only)
hyprctl reload && killall -SIGUSR2 waybar
qs -c island                     # or log out/in; it autostarts afterwards

scripts/uninstall.sh             # removes everything below
```

Everything outside this repo that the installer touches:

| File | Change | Undo |
|---|---|---|
| `~/.config/quickshell/island` | symlink to `quickshell/island` | removed |
| `~/.local/bin/island-ctl` | symlink to `bin/island-ctl` | removed |
| `~/.config/island/config.json` | your config (created once, never overwritten) | removed |
| `~/.config/hypr/UserConfigs/Startup_Apps.conf` | `exec-once = qs -c island` | marker block removed |
| `~/.config/hypr/UserConfigs/WindowRules.conf` | `layerrule`s for namespace `island` (blur, ignore_alpha, no_anim) | marker block removed |
| `~/.config/hypr/UserConfigs/UserKeybinds.conf` | `SUPER+ALT+I` toggles the island | marker block removed |
| Waybar config (target of `~/.config/waybar/config`) | `clock` and `custom/swaync` leave the top bar's center; swaync moves to the right | `.bak-island` restored |
| `~/.claude/settings.json` | 12 hook entries, backup in `settings.json.bak-island` | exactly those entries removed |

Marker blocks look like `# >>> island >>>` ... `# <<< island <<<`. The three Hyprland
files are the dots' user-owned ones, so dots upgrades leave them alone. The Waybar file
is dots-managed: after a dots upgrade, re-run `scripts/install.sh waybar`.

Runtime files live in `$XDG_RUNTIME_DIR/island/` and `~/.cache/island/art/`.

## Configuration

`~/.config/island/config.json` is deep-merged over the defaults in
`quickshell/island/core/Config.qml` and hot-reloaded on save. Only put what you want to change.

| Key | Default | Meaning |
|---|---|---|
| `monitor.policy` | `"focused"` | `"focused"`, `"primary"` (uses `monitor.name`) or `"all"` |
| `layer.keepOnTop` | `true` | `true`: overlay layer, stays above fullscreen windows. `false`: normal top layer, fullscreen windows cover it |
| `window.width/height/marginTop` | 620 / 270 / 3 | Fixed window the pill moves in. Must be bigger than the largest pill |
| `sizes.collapsedHeight`, `sizes.maxRadius` | 24, 24 | Pill geometry |
| `timings.hoverInMs` / `hoverOutMs` | 80 / 250 | Hover intent and leave delay |
| `timings.expandedLeaveMs` | 600 | Expanded pill collapses this long after the pointer leaves |
| `timings.expandedIdleMs` | 5000 | Expanded by keybind and never hovered: collapse after this |
| `timings.collapseOnLeave` | `true` | Disable to keep it expanded until toggled |
| `behavior.focusGrab` | `false` | Experimental click-outside-to-collapse. On Hyprland 0.56 it stops hover from being reported while expanded, so leaving no longer collapses |
| `spring.spring/damping/epsilon` | 3.0 / 0.32 / 0.25 | Animation feel. Lower damping = bouncier |
| `colors.bgAlpha` | 0.9 | Pill background opacity (blur comes from the layer rule) |
| `colors.running/needsInput/done` | `#FF9F0A` `#FF453A` `#30D158` | Claude status colours |
| `font.family/size` | JetBrainsMono Nerd Font / 13 | |
| `clock.format` | `"HH:mm:ss"` | Qt format. With no `s` the clock only wakes once a minute |
| `clock.dateFormat`, `clock.collapsedWidth` | `"dddd, d MMMM yyyy"`, 104 | |
| `spotify.playerPriority` | `["spotify","*"]` | First match on D-Bus name or identity wins, `*` = anything. Players that are playing beat paused ones first |
| `spotify.pausedLingerSec` | 60 | Keep showing a paused player this long |
| `priorities.*` | see below | Higher takes the pill, the runner-up becomes the bubble |
| `claude.staleTimeoutMin` | 30 | Sessions silent this long are dropped (a running session with a live process is exempt) |
| `claude.sweepSec` | 30 | Dead-process sweep interval, only while sessions exist |
| `claude.hoverAckMs` | 3000 | Cumulative hover time that acknowledges green |
| `claude.doneFadeSec` | 0 | `0`: green stays until clicked or hovered. `>0`: also fades after N seconds |
| `claude.focusOnClick` | `true` | Clicking a session row focuses its terminal |
| `external.defaultTimeoutSec` | 5 | Card lifetime when `--timeout` is not given |
| `enabled.clock/spotify/claude/external` | all `true` | Switch an activity off |

Default priorities: `claude_needs_input` 100, `external` 70, `spotify` 60, `claude_running` 55,
`claude_done` 40, `clock` 0. So music playing while Claude works shows the music pill with an
orange bubble, and a permission prompt takes the pill immediately.

## island-ctl

```sh
island-ctl push --id vol --title "Volume 40%" --icon 󰕾 --progress 40 --timeout 2
island-ctl push --id build --title "Build failed" --subtitle "exit 2" --icon  --color "#FF453A" --timeout 0
island-ctl clear --id build        # or --all
island-ctl list                    # active cards and Claude sessions
island-ctl toggle | expand | collapse | swap
island-ctl keep-on-top on|off|toggle|config [--save]
island-ctl status                  # JSON: primary, runner-up, per-window mode
island-ctl focus <pid>             # focus the window that owns a process
island-ctl restart
```

`--icon` is a Nerd Font glyph/emoji or an absolute image path. `--timeout 0` makes a card sticky.
Cards are files, so pushing works while the island is stopped.

## Claude Code bridge

`hooks/claude-island-hook.sh` is registered for 12 events and writes one file per session,
atomically, to `$XDG_RUNTIME_DIR/island/claude/<session_id>.json`, then rewrites
`.tick` in place. The island watches only `.tick` (Quickshell can watch files, not directories)
and rescans on change. State files survive island restarts and work with the island stopped.

| Event | State |
|---|---|
| `SessionStart` (startup, resume, clear, fork) | idle (registered) |
| `UserPromptSubmit`, `PostToolUse`, `PostToolUseFailure`, `PermissionDenied`, `ElicitationResult` | running |
| `PermissionRequest`, `Elicitation`, `Notification` (`permission_prompt`, `elicitation_dialog`, `agent_needs_input`) | needs_input (red) |
| `Stop` | done (green); running if `background_tasks` is non-empty |
| `StopFailure` | error (red) |
| `Notification` `idle_prompt`, `SubagentStop`, `SessionStart` (compact) | no change |
| `SessionEnd` | session removed |

The hook prints nothing, always exits 0, has a 2 s timeout and does nothing if `jq` or the
runtime dir is missing. It averages about 16 ms.

Known limits:

- **Red stays until the next event after you approve.** Claude Code has no "permission granted"
  hook, so after approving a long-running tool the pill stays red until `PostToolUse`.
- `PreToolUse` is deliberately not hooked: `UserPromptSubmit` and `PostToolUse` already cover
  "running", and skipping it halves per-tool-call overhead.
- Claude Code reports `Notification` hooks as not firing in the VS Code extension. `PermissionRequest`
  is the primary red trigger for that reason.
- Window focusing walks the session's process tree up to a Hyprland client. In Lua-mode
  Hyprland (`hyprland.lua`) `island-ctl focus` uses a best-effort `hyprctl dispatch` Lua
  expression that has **not** been tested; hyprlang mode is tested.

## Adding an activity

An activity is one QML file in `quickshell/island/activities/` plus two lines in `Registry.qml`.
It extends `Activity` (`core/Activity.qml`), which is where the full interface is documented.

A complete, tested example lives in [`docs/examples/Hello.qml`](docs/examples/Hello.qml). It is live
while `config.json` contains `{"hello": {"show": true}}`, which also shows config hot-reload.
To try it:

```sh
cp docs/examples/Hello.qml quickshell/island/activities/
echo 'Hello 1.0 Hello.qml' >> quickshell/island/activities/qmldir
```

then register it in `activities/Registry.qml`:

```qml
property QtObject hello: Hello {}
readonly property var all: [clock, spotify, claude, external, hello]
```

The skeleton of any activity:

```qml
Activity {
    id: root
    activityId: "hello"            // key for config priorities / enabled
    priority: 65                   // base priority; config "priorities.hello" overrides
    accent: "#7aa2f7"
    active: <any condition>        // live or not

    collapsedSize: Qt.size(96, Config.cfg.sizes.collapsedHeight)   // logical px, one per mode
    hoverSize: Qt.size(200, 44)
    expandedSize: Qt.size(280, 100)

    collapsedView: Component { Item { /* root fills the pill content area */ } }
    hoverView:     Component { Item { } }
    expandedView:  Component { Item { } }
    bubbleView:    Component { Item { } }   // optional, 26x26, shown when runner-up
}
```

What the host gives you:

- **Properties you set:** `activityId`, `active`, `priority`, `accent`, `ambient`, `urgent`
  (take over immediately, even mid-hover), `collapsedSize`/`hoverSize`/`expandedSize`,
  `collapsedView`/`hoverView`/`expandedView`/`bubbleView`.
- **Properties the island writes:** `hostMode` (`collapsed`/`hover`/`expanded`, only for the activity
  on screen) and `hostHovered`. Gate timers on these so nothing runs while it is not visible.
- **Callbacks:** `onActivated(mode)` on a click while not expanded (return `false` to handle the
  click without expanding), `acknowledge()`.
- **Signal:** `attention()`.
- **Helpers you can use:** `Config.cfg`, `Theme` (wallust-aware colours), `Feed` (`Feed.changed`
  fires when `island-ctl` or a hook writes state; `Feed.stateDir` is the runtime dir), and the
  widgets in `components/` (`ProgressRing`, `ArtCircle`, `SeekBar`, `IconButton`, `StateDot`, `GlyphIcon`).

Rules of thumb: no polling, only timers that run while something visible needs them, and never
errors when your data source is missing.

## Layout

```
quickshell/island/   shell.qml, core/ (window, pill, config, theme, feed),
                     activities/ (clock, spotify, claude, external, Registry),
                     components/ (shared widgets)
bin/island-ctl       CLI
docs/examples/       Hello.qml, a tested example activity
hooks/               Claude Code hook
scripts/             install, uninstall, settings.json merger
tests/               hook-test.sh, fake-mpris.py
config/              config.example.json
```

## Testing without the real thing

```sh
tests/hook-test.sh                       # hook state machine, in a private runtime dir
python3 tests/fake-mpris.py              # fake "Spotify" for playerctl and the island
python3 tests/fake-mpris.py --no-length  # ad/podcast with length 0
echo '{"session_id":"t","cwd":"/tmp/demo","hook_event_name":"PermissionRequest"}' | hooks/claude-island-hook.sh
island-ctl status                        # what the island thinks is live
hyprctl layers | grep island             # layer, size, namespace
```

During development run it straight from the repo with `qs -p quickshell/island`.
`qs log -c island` shows its log. It hot-reloads on every QML save.

## Troubleshooting

- **Nothing shows:** `qs log -c island`, and `hyprctl layers | grep island`.
- **Two clocks:** Waybar's top bar still has `clock` in `modules-center`; run `scripts/install.sh waybar`.
- **No blur:** `hyprctl reload`, then restart the island so the layer rules apply to a fresh surface.
- **Claude never lights up:** hooks apply to sessions started after `install.sh claude`. Check
  `ls $XDG_RUNTIME_DIR/island/claude` while a session runs.
