#!/usr/bin/env bash
# Exercises hooks/claude-island-hook.sh against a private runtime dir.
# Never touches your real $XDG_RUNTIME_DIR/island.   Usage: tests/hook-test.sh
set -u
HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/hooks/claude-island-hook.sh"
export XDG_RUNTIME_DIR="$(mktemp -d)"
trap 'rm -rf "$XDG_RUNTIME_DIR"' EXIT
DIR="$XDG_RUNTIME_DIR/island/claude"
fail=0

ev() { # session event [extra-json-fields]
  local out rc
  out=$(printf '{"session_id":"%s","cwd":"/home/u/proj-%s","hook_event_name":"%s"%s}' "$1" "$1" "$2" "${3:+,$3}" | "$HOOK" 2>&1)
  rc=$?
  [ -z "$out" ] || { echo "FAIL: hook printed output for $2: $out"; fail=1; }
  [ "$rc" = 0 ] || { echo "FAIL: hook exited $rc for $2"; fail=1; }
}
state() { jq -r .state "$DIR/$1.json" 2>/dev/null || echo "(none)"; }
expect() { # session wanted
  local got; got=$(state "$1")
  if [ "$got" = "$2" ]; then echo "ok   $1 -> $got"; else echo "FAIL $1: wanted $2, got $got"; fail=1; fi
}

ev a SessionStart '"source":"startup"';        expect a idle
ev a UserPromptSubmit;                          expect a running
ev a PostToolUse;                               expect a running
ev a PermissionRequest;                         expect a needs_input
ev a Notification '"notification_type":"idle_prompt"'; expect a needs_input   # ignored
ev a PostToolUse;                               expect a running
ev a Notification '"notification_type":"permission_prompt"'; expect a needs_input
ev a PostToolUse;                               expect a running
ev a Stop '"background_tasks":[{"id":"x"}]';    expect a running
ev a Stop;                                      expect a done
ev a Notification '"notification_type":"idle_prompt"'; expect a done          # stays green
ev a SubagentStop;                              expect a done
ev a StopFailure '"error":"rate_limit"';        expect a error
ev a UserPromptSubmit;                          expect a running
ev a Elicitation;                               expect a needs_input
ev a ElicitationResult;                         expect a running
ev a SessionStart '"source":"compact"';         expect a running              # compact: no change

# "since" only moves when the state changes
s1=$(jq .since "$DIR/a.json"); sleep 1.1; ev a PostToolUse; s2=$(jq .since "$DIR/a.json")
[ "$s1" = "$s2" ] && echo "ok   since stable while state unchanged" || { echo "FAIL since moved"; fail=1; }

# two sessions are independent
ev b UserPromptSubmit; ev b PermissionRequest; expect b needs_input; expect a running

# an older event never overwrites a newer one
future=$(( $(date +%s%N) + 60000000000 )); jq --argjson t "$future" '.ts=$t | .state="done"' "$DIR/b.json" >"$DIR/b.tmp"; mv "$DIR/b.tmp" "$DIR/b.json"
ev b UserPromptSubmit; expect b done

# tick file exists, no stray temp files
[ -f "$XDG_RUNTIME_DIR/island/.tick" ] && echo "ok   tick written" || { echo "FAIL no tick"; fail=1; }
ls -A "$DIR" | grep -q '\.tmp$' && { echo "FAIL leftover tmp"; fail=1; } || echo "ok   no leftover temp files"

# SessionEnd removes the file
ev a SessionEnd; [ ! -e "$DIR/a.json" ] && echo "ok   SessionEnd removed a" || { echo "FAIL a still present"; fail=1; }

# garbage and hostile input never fail or print
for bad in '' 'not json' '{}' '{"session_id":"../../etc/x","hook_event_name":"Stop"}' '{"session_id":".hid","hook_event_name":"Stop"}'; do
  out=$(printf '%s' "$bad" | "$HOOK" 2>&1); rc=$?
  { [ -z "$out" ] && [ "$rc" = 0 ]; } && echo "ok   survives: ${bad:-<empty>}" || { echo "FAIL on input: $bad ($rc, $out)"; fail=1; }
done
ls "$XDG_RUNTIME_DIR/island" | grep -q etc && { echo "FAIL path traversal"; fail=1; }

# no runtime dir at all
out=$(XDG_RUNTIME_DIR= bash -c "printf '{\"session_id\":\"z\",\"hook_event_name\":\"Stop\"}' | '$HOOK'" 2>&1); rc=$?
{ [ -z "$out" ] && [ "$rc" = 0 ]; } && echo "ok   no XDG_RUNTIME_DIR is a no-op" || { echo "FAIL without runtime dir"; fail=1; }

# speed
start=$(date +%s%N); for _ in 1 2 3 4 5 6 7 8 9 10; do ev c PostToolUse; done; end=$(date +%s%N)
echo "info avg hook time: $(( (end - start) / 10000000 )) ms"

[ "$fail" = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
