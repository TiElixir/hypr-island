#!/usr/bin/env python3
"""Merge Island's hooks into ~/.claude/settings.json, or remove them again.

    claude-hooks.py install   [--dry-run] [--settings PATH]
    claude-hooks.py uninstall [--dry-run] [--settings PATH]

Existing hooks and every other setting are preserved. A one-time backup is
written next to the file as settings.json.bak-island. Hook entries are
recognised by their command mentioning claude-island-hook.sh, so uninstall
removes exactly what install added. Changes only apply to NEW Claude Code
sessions.
"""
import argparse
import json
import os
import shutil
import sys
import tempfile

MARK = "claude-island-hook.sh"
HOOK = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "hooks", MARK)
# PreToolUse is deliberately absent: UserPromptSubmit and PostToolUse already
# cover "running", and skipping it halves the per-tool-call overhead.
EVENTS = [
    "SessionStart",
    "UserPromptSubmit",
    "PostToolUse",
    "PostToolUseFailure",
    "PermissionRequest",
    "PermissionDenied",
    "Notification",
    "Elicitation",
    "ElicitationResult",
    "Stop",
    "StopFailure",
    "SessionEnd",
]


def command():
    # Silent no-op (exit 0) if the repo moves, instead of a hook error on every event.
    return f'P="{HOOK}"; [ -x "$P" ] && exec "$P"; exit 0'


def is_ours(group):
    return any(MARK in (h.get("command") or "") for h in group.get("hooks", []))


def load(path):
    if not os.path.exists(path):
        return {}
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def save(path, data):
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".settings.", suffix=".tmp")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    shutil.copymode(path, tmp) if os.path.exists(path) else None
    os.replace(tmp, path)


def install(data):
    hooks = data.setdefault("hooks", {})
    added = []
    for ev in EVENTS:
        groups = hooks.setdefault(ev, [])
        if any(is_ours(g) for g in groups):
            continue
        groups.append({"hooks": [{"type": "command", "command": command(), "timeout": 2}]})
        added.append(ev)
    return added


def uninstall(data):
    hooks = data.get("hooks", {})
    removed = []
    for ev in list(hooks):
        kept = [g for g in hooks[ev] if not is_ours(g)]
        if len(kept) != len(hooks[ev]):
            removed.append(ev)
        if kept:
            hooks[ev] = kept
        else:
            del hooks[ev]
    if "hooks" in data and not data["hooks"]:
        del data["hooks"]
    return removed


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("action", choices=["install", "uninstall"])
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--settings", default=os.path.expanduser("~/.claude/settings.json"))
    args = ap.parse_args()

    path = args.settings
    try:
        data = load(path)
    except json.JSONDecodeError as e:
        sys.exit(f"{path} is not valid JSON ({e}); refusing to touch it")

    changed = install(data) if args.action == "install" else uninstall(data)
    verb = "added to" if args.action == "install" else "removed from"
    print(f"  {len(changed)} event(s) {verb} {path}: {', '.join(changed) or '-'}")
    if not changed or args.dry_run:
        if args.dry_run:
            print("  [dry-run] nothing written")
        return
    backup = path + ".bak-island"
    if args.action == "install" and os.path.exists(path) and not os.path.exists(backup):
        shutil.copy2(path, backup)
        print(f"  backup: {backup}")
    save(path, data)
    print("  done. Applies to new Claude Code sessions only.")


if __name__ == "__main__":
    main()
