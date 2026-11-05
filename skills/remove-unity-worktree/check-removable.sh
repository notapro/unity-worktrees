#!/usr/bin/env bash
# usage: check-removable.sh [worktree]
# Read-only guard: exit 1 if a Unity editor has the worktree open. Closing one discards unsaved
# scene edits. Orca archive hook: worktree comes from $ORCA_WORKTREE_PATH. Never deletes anything,
# because Orca also runs the archive hook for plain archiving.
set -euo pipefail

wt=${1:-${ORCA_WORKTREE_PATH:-$PWD}}

if [ -n "$(lsof -t "$wt/Temp/UnityLockfile" 2>/dev/null || true)" ]; then
  echo "Unity editor is open on $wt. Save and close it first." >&2
  exit 1
fi
