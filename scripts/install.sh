#!/usr/bin/env bash
# Installs Island into your session. Idempotent; every edit outside this repo
# is wrapped in "# >>> island >>>" / "# <<< island <<<" markers (or backed up),
# so scripts/uninstall.sh can remove it exactly.
#
#   scripts/install.sh [--dry-run] [step...]
#   steps: links config hypr waybar claude   (default: links config hypr waybar)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HYPR="$HOME/.config/hypr"
USERCFG="$HYPR/UserConfigs"
WAYBAR_CFG="$(readlink -f "$HOME/.config/waybar/config")"
BEGIN="# >>> island >>>"
END="# <<< island <<<"
DRY=0

say() { printf '  %s\n' "$*"; }
run() { if [ "$DRY" = 1 ]; then say "[dry-run] $*"; else "$@"; fi; }

# Writes our marker block into a file. An existing block is replaced, so
# re-running the installer after an update refreshes it.
add_block() { # file, content
  local file="$1" content="$2"
  if [ ! -f "$file" ]; then say "skip: $file does not exist"; return; fi
  local have=""
  if grep -qF "$BEGIN" "$file"; then
    have=1
    local current
    current=$(sed -n "/^$BEGIN\$/,/^$END\$/p" "$file" | sed '1d;$d')
    if [ "$current" = "$content" ]; then say "up to date: $file"; return; fi
  fi
  if [ -n "$have" ]; then say "replace block: $file"; else say "append block: $file"; fi
  if [ "$DRY" = 0 ]; then
    [ -n "$have" ] && sed -i "/^$BEGIN\$/,/^$END\$/d" "$file"
    printf '\n%s\n%s\n%s\n' "$BEGIN" "$content" "$END" >>"$file"
  fi
}

step_links() {
  echo "links"
  run mkdir -p "$HOME/.config/quickshell" "$HOME/.local/bin"
  if [ -e "$HOME/.config/quickshell/island" ] && [ ! -L "$HOME/.config/quickshell/island" ]; then
    say "refusing: ~/.config/quickshell/island exists and is not a symlink"; return 1
  fi
  run ln -sfn "$REPO/quickshell/island" "$HOME/.config/quickshell/island"
  if [ -x "$REPO/bin/island-ctl" ]; then
    run ln -sfn "$REPO/bin/island-ctl" "$HOME/.local/bin/island-ctl"
  fi
}

step_config() {
  echo "config"
  if [ -f "$HOME/.config/island/config.json" ]; then say "keeping existing config.json"; return; fi
  run mkdir -p "$HOME/.config/island"
  run cp "$REPO/config/config.example.json" "$HOME/.config/island/config.json"
}

step_hypr() {
  echo "hyprland (user-owned files, hyprlang)"
  add_block "$USERCFG/Startup_Apps.conf" 'exec-once = qs -c island  # Island (Dynamic-Island style widget)'
  add_block "$USERCFG/WindowRules.conf" 'layerrule = match:namespace island, blur on
layerrule = match:namespace island, ignore_alpha 0.3
layerrule = match:namespace island, no_anim on
layerrule = match:namespace island-settings, blur on
layerrule = match:namespace island-settings, ignore_alpha 0.3
layerrule = match:namespace island-settings, no_anim on'
  add_block "$USERCFG/UserKeybinds.conf" 'bindd = $mainMod ALT, I, toggle island, exec, qs ipc -c island call island toggle
bindd = $mainMod ALT, S, island settings, exec, $HOME/.local/bin/island-ctl settings'
  say "apply with: hyprctl reload"
}

step_waybar() {
  echo "waybar: $WAYBAR_CFG"
  if grep -qF "island:" "$WAYBAR_CFG"; then say "already edited"; return; fi
  if [ ! -f "$WAYBAR_CFG.bak-island" ]; then run cp -p "$WAYBAR_CFG" "$WAYBAR_CFG.bak-island"; fi
  say "top bar: clock + custom/swaync leave modules-center, swaync moves to modules-right"
  [ "$DRY" = 1 ] && return
  python3 -I - "$WAYBAR_CFG" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
cut = text.index('"position": "top"')
end = text.index('"position": "bottom"')
top, rest = text[:end], text[end:]
center = re.compile(r'"modules-center"\s*:\s*\[.*?\]\s*,', re.S)
m = center.search(top, cut)
if not m:
    sys.exit("could not find the top bar's modules-center; edit it by hand")
top = top[:m.start()] + '// island: clock and custom/swaync moved out of the center\n"modules-center": [],' + top[m.end():]
right = re.compile(r'("modules-right"\s*:\s*\[)', re.S)
m = right.search(top, cut)
if not m:
    sys.exit("could not find the top bar's modules-right; edit it by hand")
top = top[:m.end()] + '\n\t"custom/swaync", // island: moved here from the center' + top[m.end():]
open(path, "w", encoding="utf-8").write(top + rest)
PY
  say "apply with: killall -SIGUSR2 waybar"
}

step_claude() {
  echo "claude hooks"
  if [ ! -x "$REPO/scripts/claude-hooks.py" ]; then say "not built yet (phase 2)"; return; fi
  if [ "$DRY" = 1 ]; then python3 -I "$REPO/scripts/claude-hooks.py" install --dry-run; else python3 -I "$REPO/scripts/claude-hooks.py" install; fi
}

steps=()
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) steps+=("$a") ;;
  esac
done
[ ${#steps[@]} -eq 0 ] && steps=(links config hypr waybar)
for s in "${steps[@]}"; do "step_$s"; done
echo "done."
