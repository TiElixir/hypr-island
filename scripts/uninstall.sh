#!/usr/bin/env bash
# Reverses scripts/install.sh. Removes only what Island added.
#   scripts/uninstall.sh [--keep-config]
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
USERCFG="$HOME/.config/hypr/UserConfigs"
WAYBAR_CFG="$(readlink -f "$HOME/.config/waybar/config")"
KEEP_CONFIG=0
[ "${1:-}" = "--keep-config" ] && KEEP_CONFIG=1

say() { printf '  %s\n' "$*"; }

qs kill -c island >/dev/null 2>&1 || true

for f in Startup_Apps.conf WindowRules.conf UserKeybinds.conf; do
  file="$USERCFG/$f"
  if [ -f "$file" ] && grep -qF "# >>> island >>>" "$file"; then
    sed -i '/^# >>> island >>>$/,/^# <<< island <<<$/d' "$file"
    # drop the blank separator line the installer added
    sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$file"
    say "removed block: $file"
  fi
done

if [ -f "$WAYBAR_CFG.bak-island" ]; then
  mv -f "$WAYBAR_CFG.bak-island" "$WAYBAR_CFG"
  say "restored: $WAYBAR_CFG"
fi

[ -L "$HOME/.config/quickshell/island" ] && rm "$HOME/.config/quickshell/island" && say "removed symlink: ~/.config/quickshell/island"
[ -L "$HOME/.local/bin/island-ctl" ] && rm "$HOME/.local/bin/island-ctl" && say "removed symlink: ~/.local/bin/island-ctl"

if [ -x "$REPO/scripts/claude-hooks.py" ]; then python3 -I "$REPO/scripts/claude-hooks.py" uninstall || true; fi

[ "$KEEP_CONFIG" = 0 ] && rm -rf "$HOME/.config/island" && say "removed ~/.config/island"
rm -rf "${XDG_RUNTIME_DIR:-/nonexistent}/island" "$HOME/.cache/island"
say "removed runtime and cache dirs"
echo "done. Now run: hyprctl reload && killall -SIGUSR2 waybar"
