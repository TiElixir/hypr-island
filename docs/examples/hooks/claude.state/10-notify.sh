#!/bin/sh
# Example event hook: desktop notification when a Claude session needs you.
# Install: mkdir -p ~/.config/island/hooks/claude.state && cp this there && chmod +x
# Env: ISLAND_EVENT, ISLAND_DATA (JSON), and every flat field as ISLAND_<FIELD>.
[ "$ISLAND_TO" = "needs_input" ] || exit 0
notify-send -u critical "Claude needs you" "$ISLAND_PROJECT"
