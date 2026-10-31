#!/bin/sh
# Example event hook: log every focus change. The payload is also on stdin as JSON.
echo "$(date +%T) $ISLAND_CLASS: $ISLAND_TITLE" >> "${XDG_RUNTIME_DIR:-/tmp}/island-focus.log"
