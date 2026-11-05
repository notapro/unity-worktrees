#!/usr/bin/env bash
# usage: setup-orca.sh [project-dir] [--force]
# Copies this skill's orca.yaml into a Unity project's root. Does not commit it.
set -euo pipefail

dir=""; force=0
for a in "$@"; do
  case $a in
    --force) force=1;;
    *) dir=$a;;
  esac
done
dir=${dir:-$PWD}
top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || (cd "$dir" && pwd))

[ -f "$top/ProjectSettings/ProjectVersion.txt" ] || { echo "not a Unity project: $top" >&2; exit 2; }
if [ -e "$top/orca.yaml" ] && [ "$force" = 0 ]; then
  echo "orca.yaml already exists in $top; review it, or pass --force to overwrite" >&2
  exit 2
fi
[ -e "$HOME/.claude/unity-worktrees" ] || echo "warning: ~/.claude/unity-worktrees is missing; start one Claude session with the plugin installed to create it" >&2

cp "$(dirname "$0")/orca.yaml" "$top/orca.yaml"
echo "wrote $top/orca.yaml"
echo "Commit it on the branch you create Orca worktrees from (Orca reads it from the new worktree)."
