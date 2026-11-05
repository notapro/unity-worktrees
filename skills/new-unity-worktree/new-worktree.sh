#!/usr/bin/env bash
# usage: new-worktree.sh <name> [--base REF] [--force]
# Run from inside the Unity project (or any of its worktrees) to branch from.
# For worktrees created by Orca, seed-worktree.sh runs as Orca's setup hook instead.
set -euo pipefail

name=${1:?usage: new-worktree.sh <name> [--base REF] [--force]}; shift
base=HEAD; force=0
while [ $# -gt 0 ]; do
  case $1 in
    --base) base=${2:?--base needs a ref}; shift 2;;
    --force) force=1; shift;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done

src=$(git rev-parse --show-toplevel)
[ -f "$src/ProjectSettings/ProjectVersion.txt" ] || { echo "not a Unity project: $src" >&2; exit 2; }
dst="$(dirname "$src")/$(basename "$src")-$name"
[ ! -e "$dst" ] || { echo "already exists: $dst" >&2; exit 2; }

# Unity holds Temp/UnityLockfile open while an editor runs; cloning a live Library is untested.
if [ "$force" = 0 ] && [ -n "$(lsof -t "$src/Temp/UnityLockfile" 2>/dev/null || true)" ]; then
  echo "Unity editor is open on $src. Close it (or pass --force) so Library is cloned in a clean state." >&2
  exit 2
fi

git -C "$src" worktree add -b "$name" "$dst" "$base"
"$(dirname "$0")/seed-worktree.sh" "$dst" "$src"

echo "WORKTREE=$dst"
echo "BRANCH=$name"
