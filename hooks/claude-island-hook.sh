#!/usr/bin/env bash
# Claude Code hook -> Island bridge.
#
# Reads the hook JSON on stdin, maps the event to a session state and writes
# one small JSON file per session, atomically:
#     $XDG_RUNTIME_DIR/island/claude/<session_id>.json
# then rewrites $XDG_RUNTIME_DIR/island/.tick in place so the island (which can
# only watch single files) wakes up and rescans. Works with the island stopped.
#
# Rules: prints NOTHING (stdout of some events is added to Claude's context),
# never blocks, always exits 0, silently does nothing if jq or the runtime
# dir is missing.
#
# state: idle | running | needs_input | done | error

exec >/dev/null 2>&1
set +e

main() {
  [ -n "${XDG_RUNTIME_DIR:-}" ] || return 0
  command -v jq >/dev/null || return 0

  local now_ns now_s input
  now_ns=$(date +%s%N)
  now_s=$((now_ns / 1000000000))
  input=$(cat)
  [ -n "$input" ] || return 0

  local sid event cwd ntype source bg
  # Fields are joined with the ASCII unit separator, not tab: a whitespace IFS
  # would collapse empty fields and shift every value after them.
  IFS=$'\x1f' read -r sid event cwd ntype source bg < <(
    jq -r '[
      (.session_id // ""), (.hook_event_name // ""), (.cwd // ""),
      (.notification_type // ""), (.source // ""),
      ((.background_tasks // []) | length | tostring)
    ] | map(tostring) | join("\u001f")' <<<"$input"
  )
  [ -n "$sid" ] || return 0
  case "$sid" in */* | .*) return 0 ;; esac

  local dir="$XDG_RUNTIME_DIR/island/claude"
  local file="$dir/$sid.json"
  local tick="$XDG_RUNTIME_DIR/island/.tick"

  local new=""
  case "$event" in
    SessionStart)
      if [ "$source" = "compact" ] && [ -f "$file" ]; then return 0; fi
      new=idle ;;
    UserPromptSubmit | PostToolUse | PostToolUseFailure | PermissionDenied | ElicitationResult)
      new=running ;;
    PermissionRequest | Elicitation)
      new=needs_input ;;
    Notification)
      case "$ntype" in
        permission_prompt | elicitation_dialog | agent_needs_input) new=needs_input ;;
        *) return 0 ;; # idle_prompt etc.: keep whatever state we have
      esac ;;
    Stop)
      # Background tasks still running means Claude is not really finished.
      if [ "${bg:-0}" -gt 0 ] 2>/dev/null; then new=running; else new=done; fi ;;
    StopFailure)
      new=error ;;
    SessionEnd)
      if [ -f "$file" ]; then
        rm -f "$file"
        mkdir -p "$XDG_RUNTIME_DIR/island" && printf '%s' "$now_ns" >"$tick"
      fi
      return 0 ;;
    *) return 0 ;; # SubagentStop and anything else: no change
  esac

  mkdir -p "$dir" || return 0

  # Previous state, so "since" only moves when the state actually changes
  # and an older event can never overwrite a newer one.
  local prev_state="" prev_since="" prev_ts=0 prev_pid="" prev_pidstart=""
  if [ -f "$file" ]; then
    IFS=$'\x1f' read -r prev_state prev_since prev_ts prev_pid prev_pidstart < <(
      jq -r '[(.state // ""), (.since // 0), (.ts // 0), (.pid // 0), (.pid_start // "")] | map(tostring) | join("\u001f")' "$file"
    )
  fi
  [ "${prev_ts:-0}" -gt "$now_ns" ] 2>/dev/null && return 0

  local since="$now_s"
  [ "$prev_state" = "$new" ] && [ -n "$prev_since" ] && since="$prev_since"

  # The claude process: first ancestor whose comm looks like claude.
  local pid="" pidstart="" p="$PPID" i=0 comm
  while [ "$i" -lt 10 ] && [ -n "$p" ] && [ "$p" -gt 1 ] 2>/dev/null; do
    comm=$(cat "/proc/$p/comm" 2>/dev/null)
    case "$comm" in claude* | node | bun) pid="$p"; break ;; esac
    p=$(sed 's/^.*) //' "/proc/$p/stat" 2>/dev/null | awk '{print $2}')
    i=$((i + 1))
  done
  [ -n "$pid" ] || pid="${prev_pid:-0}"
  if [ "$pid" != "0" ] && [ -n "$pid" ]; then
    if [ "$pid" = "$prev_pid" ] && [ -n "$prev_pidstart" ]; then
      pidstart="$prev_pidstart"
    else
      pidstart=$(sed 's/^.*) //' "/proc/$pid/stat" 2>/dev/null | awk '{print $20}')
    fi
  fi

  local tmp="$dir/.$sid.$$.tmp"
  jq -cn \
    --arg id "$sid" --arg state "$new" --arg cwd "$cwd" --arg event "$event" \
    --arg project "$(basename "${CLAUDE_PROJECT_DIR:-${cwd:-$sid}}")" \
    --argjson ts "$now_ns" --argjson since "$since" \
    --argjson pid "${pid:-0}" --arg pidstart "$pidstart" \
    '{id:$id, state:$state, cwd:$cwd, project:$project, ts:$ts, since:$since,
      pid:$pid, pid_start:$pidstart, last_event:$event}' >"$tmp" || { rm -f "$tmp"; return 0; }
  mv -f "$tmp" "$file" || { rm -f "$tmp"; return 0; }

  # Only wake the island when something it displays changed.
  if [ "$prev_state" != "$new" ]; then
    printf '%s' "$now_ns" >"$tick"
  fi
}

main
exit 0
