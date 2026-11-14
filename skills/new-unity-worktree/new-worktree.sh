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

if command -v unity >/dev/null; then
  # Branching here refuses an existing branch and supplies the --base the Unity CLI lacks.
  git -C "$src" branch "$name" "$base"
  # --seed full keeps PackageCache: first open measured ~2x faster than the default cache seed.
  unity vcs git worktree add "$name" "$src" --into "$dst" --seed full --non-interactive --no-banner --quiet \
    || { rc=$?; git -C "$src" worktree remove --force "$dst" 2>/dev/null || true
         git -C "$src" branch -D "$name" >/dev/null || true; exit "$rc"; }
  # The CLI keeps these from the source editor's session; seed-worktree.sh skips its scrub when Library exists.
  rm -rf "$dst/Library/Pipeline" "$dst/Library/Temp"
  # The CLI seed drops this, so the editor would open an untitled scene instead of the source's.
  cp "$src/Library/LastSceneManagerSetup.txt" "$dst/Library/" 2>/dev/null || true
else
  git -C "$src" worktree add -b "$name" "$dst" "$base"
fi
"$(dirname "$0")/seed-worktree.sh" "$dst" "$src"

echo "WORKTREE=$dst"
echo "BRANCH=$name"
