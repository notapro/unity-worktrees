#!/usr/bin/env bash
# usage: seed-worktree.sh [worktree] [source-checkout]
# Makes a fresh Unity worktree open fast: clones Library and carries over uncommitted
# Packages/ + ProjectSettings/ edits. Idempotent; a no-op outside Unity projects.
# Orca setup hook: worktree comes from $ORCA_WORKTREE_PATH, source from $ORCA_ROOT_PATH.
set -euo pipefail

dst=${1:-${ORCA_WORKTREE_PATH:-$PWD}}
dst=$(cd "$dst" && git rev-parse --show-toplevel)
src=${2:-${ORCA_ROOT_PATH:-}}
[ -n "$src" ] || src=$(git -C "$dst" worktree list --porcelain | sed -n '1s/^worktree //p')

[ -f "$dst/ProjectSettings/ProjectVersion.txt" ] || exit 0
[ "$src" != "$dst" ] || exit 0

if [ -n "$(lsof -t "$src/Temp/UnityLockfile" 2>/dev/null || true)" ]; then
  echo "warning: editor is open on $src; cloning its live Library (untested, Unity reimports if inconsistent)" >&2
fi

gitdir=$(git -C "$dst" rev-parse --absolute-git-dir)
# The Bash backstop hook and SubagentStart can fire together; one seeder at a time.
lock="$gitdir/unity-seeding.lock"
tmp="$dst/Library.seeding"
waited=0
until mkdir "$lock" 2>/dev/null; do
  # The holder writes its pid right after mkdir; with no pid yet, only age marks the lock stale.
  holder=$(cat "$lock/pid" 2>/dev/null || true)
  if { [ -n "$holder" ] && ! kill -0 "$holder" 2>/dev/null; } \
     || { [ -z "$holder" ] && [ -n "$(find "$lock" -maxdepth 0 -mmin +10 2>/dev/null)" ]; }; then
    echo "removing stale seeding lock $lock" >&2; rm -rf "$lock"; continue
  fi
  [ "$waited" -lt 120 ] || { echo "timed out waiting for another seeder ($lock)" >&2; exit 1; }
  waited=$((waited + 1)); sleep 1
done
echo $$ > "$lock/pid"
trap 'rm -rf "$tmp" "$lock"' EXIT
# The seeder we waited for finished the job.
[ "$waited" = 0 ] || [ ! -e "$dst/Library" ] || exit 0

seeded="$gitdir/unity-seeded"
# Copy files once per worktree: a re-seed (e.g. after Library is deleted) must not overwrite edits made here.
if [ -e "$seeded" ]; then
  echo "Packages/ProjectSettings already seeded; not copying them again" >&2
else
  : > "$seeded"
  # Overlaying the source's uncommitted manifest onto a different base commit could break the project.
  if git -C "$src" diff --quiet HEAD "$(git -C "$dst" rev-parse HEAD)" -- Packages ProjectSettings; then
    while IFS= read -r f; do
      [ -f "$src/$f" ] || continue
      mkdir -p "$dst/$(dirname "$f")"
      cp "$src/$f" "$dst/$f"
      echo "$f" >> "$seeded"
    done < <(git -C "$src" ls-files -m -o --exclude-standard -- Packages ProjectSettings)
  else
    echo "base's Packages/ProjectSettings differ from $src HEAD; skipping their seeding" >&2
  fi
fi

if [ -e "$dst/Library" ]; then
  echo "Library already present; not cloning" >&2
elif [ -d "$src/Library" ]; then
  # APFS clone is ~4s and ~free for a 6.7 GB Library; fall back to reflink, then a plain copy.
  # Clone beside the target and rename at the end, so an interrupted copy or a second seeder
  # never leaves a half-filled Library that Unity would trust.
  rm -rf "$tmp"
  cp -cR "$src/Library" "$tmp" 2>/dev/null \
    || { rm -rf "$tmp"; cp -R --reflink=auto "$src/Library" "$tmp" 2>/dev/null; } \
    || { rm -rf "$tmp"; cp -R "$src/Library" "$tmp"; }
  # These belong to the source editor's session (Pipeline/ holds its port, pid and token);
  # a stale copy can misroute the CLI or look like a live editor.
  rm -rf "$tmp/Pipeline" "$tmp/Temp" "$tmp/ilpp.pid" "$tmp"/*-lock
  mv "$tmp" "$dst/Library"
else
  echo "warning: no Library in $src; first open will do a full import" >&2
fi

echo "seeded $dst from $src ($(wc -l < "$seeded" | tr -d ' ') file(s) + Library)"
