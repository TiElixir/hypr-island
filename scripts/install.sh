#!/usr/bin/env bash
# Installs Island into your session. Idempotent; every edit outside this repo
# is wrapped in "# >>> island >>>" / "# <<< island <<<" markers (or backed up),
# so scripts/uninstall.sh can remove it exactly.
#
#   scripts/install.sh [--dry-run] [--modules LIST] [step...]
#   steps: links config modules hypr waybar claude
#          (default: links config modules hypr waybar)
#
# The modules step asks which built-in modules to install. --modules answers
# for it: comma-separated ids (spotify,claude,external,windowfocus,f1,discord), all or none.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HYPR="$HOME/.config/hypr"
USERCFG="$HYPR/UserConfigs"
WAYBAR_CFG="$(readlink -f "$HOME/.config/waybar/config")"
CONFIG="$HOME/.config/island/config.json"
BEGIN="# >>> island >>>"
END="# <<< island <<<"
DRY=0
PICK=""

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
  if [ -f "$CONFIG" ]; then say "keeping existing config.json"; return; fi
  run mkdir -p "$HOME/.config/island"
  run cp "$REPO/config/config.example.json" "$CONFIG"
}

# ---- modules: which built-in modules are installed ----------------------------
# A module left out goes into config.json's "skipModules": the island never
# loads it and Settings doesn't list it. A module put back is switched on.
ids=() names=() defs=() descs=() state=() on=()

read_modules() {
  local m id name def desc
  for m in "$REPO"/quickshell/island/modules/*/manifest.json; do
    IFS=$'\t' read -r id name def desc < <(jq -r '[.id, .name, (.defaultEnabled != false | tostring),
      (.description // "" | split(": ")[0] | split(". ")[0] | rtrimstr("."))] | @tsv' "$m")
    ids+=("$id"); names+=("$name"); defs+=("$def"); descs+=("$desc")
  done
}

show_modules() {
  local i d mark w
  w=$(( $(tput cols 2>/dev/null || echo 100) - 38 ))
  [ "$w" -ge 20 ] || w=20
  for i in "${!ids[@]}"; do
    d="${descs[i]}"
    if [ "${#d}" -gt "$w" ]; then d="${d:0:w-1}…"; fi
    if [ "${on[i]}" = 1 ]; then mark=x; else mark=" "; fi
    printf '    %d [%s] %-24s %s\n' "$((i + 1))" "$mark" "${names[i]}" "$d"
  done
}

join_names() { local out="" x; for x in "$@"; do out="${out:+$out, }$x"; done; printf '%s' "${out:-none}"; }
json_list() { jq -cn '$ARGS.positional' --args "$@"; }

step_modules() {
  echo "modules"
  command -v jq >/dev/null || { say "skip: jq is required"; return; }
  [ -f "$CONFIG" ] || step_config
  local src="$CONFIG" i n picks=()
  [ -f "$src" ] || src="$REPO/config/config.example.json"
  read_modules

  # state: "skip" or "keep", then "on" or "off" (its switch in Settings).
  # Installed now means kept and switched on.
  for i in "${!ids[@]}"; do
    state[i]=$(jq -r --arg id "${ids[i]}" --argjson def "${defs[i]}" '
      (if ((.skipModules // []) | any(.[]?; . == $id)) then "skip" else "keep" end) + " " +
      (if (.modules[$id].enabled | if . == null then $def else . end) == true then "on" else "off" end)' "$src")
    if [ "${state[i]}" = "keep on" ]; then on[i]=1; else on[i]=0; fi
  done

  if [ -n "$PICK" ]; then
    case "$PICK" in
      all) picks=("${ids[@]}") ;;
      none) picks=() ;;
      *) IFS=', ' read -r -a picks <<<"$PICK" ;;
    esac
    for n in "${picks[@]}"; do
      [ -n "$n" ] || continue
      [[ " ${ids[*]} " == *" $n "* ]] || { echo "unknown module: $n (have: ${ids[*]})" >&2; exit 2; }
    done
    for i in "${!ids[@]}"; do
      if [[ " ${picks[*]} " == *" ${ids[i]} "* ]]; then on[i]=1; else on[i]=0; fi
    done
  elif [ "$DRY" = 1 ] || [ ! -t 0 ]; then
    show_modules
    if [ "$DRY" = 1 ]; then say "[dry-run] would ask which ones to install (or pass --modules)"
    else say "no terminal to ask, left as they are (pass --modules to choose)"; fi
    return
  else
    say "Pick the modules to install. Unticked ones are not loaded and don't show up"
    say "in Settings; run scripts/install.sh modules again to change your mind."
    while :; do
      show_modules
      IFS=', ' read -r -a picks -p "  numbers to tick or untick, Enter when done: " || picks=()
      [ ${#picks[@]} -gt 0 ] || break
      for n in "${picks[@]}"; do
        [ -n "$n" ] || continue
        if [[ "$n" =~ ^[0-9]{1,3}$ ]] && [ $((10#$n)) -ge 1 ] && [ $((10#$n)) -le "${#ids[@]}" ]; then
          n=$((10#$n))
          on[n-1]=$((1 - on[n-1]))
        else
          say "no module $n"
        fi
      done
    done
  fi

  local skip=() enable=() kept=() left=() turned=() new
  for i in "${!ids[@]}"; do
    if [ "${on[i]}" = 1 ]; then
      kept+=("${names[i]}")
      if [ "${state[i]#* }" = off ]; then enable+=("${ids[i]}"); turned+=("${names[i]}"); fi
    else
      skip+=("${ids[i]}"); left+=("${names[i]}")
    fi
  done
  new=$(jq --argjson skip "$(json_list "${skip[@]}")" --argjson enable "$(json_list "${enable[@]}")" '
    (if ($skip | length) > 0 then .skipModules = $skip else del(.skipModules) end)
    | reduce $enable[] as $id (.; .modules[$id].enabled = true)' "$src")
  say "installed: $(join_names "${kept[@]}")"
  say "left out:  $(join_names "${left[@]}")"
  if [ "$(jq -cS . "$src")" = "$(jq -cS . <<<"$new")" ]; then
    say "up to date: $CONFIG"
  elif [ "$DRY" = 1 ]; then
    say "[dry-run] would update $CONFIG (switching on: $(join_names "${turned[@]}"))"
  else
    # In place, like the island's own saves, so its file watch picks it up.
    printf '%s\n' "$new" >"$CONFIG"
    say "updated: $CONFIG (a running island applies it at once)"
  fi
}

step_hypr() {
  echo "hyprland (user-owned files, hyprlang)"
  add_block "$USERCFG/Startup_Apps.conf" 'exec-once = qs -c island  # Island (Dynamic-Island style widget)'
  add_block "$USERCFG/WindowRules.conf" 'layerrule = match:namespace island, blur on
layerrule = match:namespace island, ignore_alpha 0.3
layerrule = match:namespace island, no_anim on
layerrule = match:namespace island-settings, blur on
layerrule = match:namespace island-settings, ignore_alpha 0.5
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
  if [ -f "$CONFIG" ] && jq -e '(.skipModules // []) | any(.[]?; . == "claude")' "$CONFIG" >/dev/null 2>&1; then
    say "note: the Claude Code module is not installed; add it with scripts/install.sh modules"
  fi
  if [ "$DRY" = 1 ]; then python3 -I "$REPO/scripts/claude-hooks.py" install --dry-run; else python3 -I "$REPO/scripts/claude-hooks.py" install; fi
}

steps=()
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --modules=*) PICK="${1#--modules=}" ;;
    --modules) [ $# -ge 2 ] || { echo "--modules needs a list" >&2; exit 2; }; shift; PICK="$1" ;;
    -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
    *) declare -F "step_$1" >/dev/null || { echo "unknown step: $1 (see --help)" >&2; exit 2; }; steps+=("$1") ;;
  esac
  shift
done
[ ${#steps[@]} -eq 0 ] && steps=(links config modules hypr waybar)
for s in "${steps[@]}"; do "step_$s"; done
echo "done."
