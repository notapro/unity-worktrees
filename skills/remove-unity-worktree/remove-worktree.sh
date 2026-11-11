#!/usr/bin/env bash
# usage: remove-worktree.sh <name|branch|path> [--force]
# Run from the main checkout (not from inside the worktree being removed).
set -euo pipefail

target=${1:?usage: remove-worktree.sh <name|branch|path> [--force]}; shift
force=0
[ "${1:-}" = "--force" ] && force=1

main=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")

wt=""; br=""
cur=""; curbr=""
while IFS= read -r line; do
  case $line in
    "worktree "*) cur=${line#worktree }; curbr="";;
    "branch "*)   curbr=${line#branch refs/heads/};;
    "")
      if [ -n "$cur" ] && [ "$cur" != "$main" ] \
         && { [ "$cur" = "$target" ] || [ "$curbr" = "$target" ] || [ "$(basename "$cur")" = "$target" ]; }; then
        wt=$cur; br=$curbr
      fi;;
  esac
done < <(git -C "$main" worktree list --porcelain; echo)

[ -n "$wt" ] || { echo "no linked worktree matches '$target' (main checkout is never removed)" >&2; exit 2; }
case "$PWD/" in "$wt"/*) echo "cd out of $wt first" >&2; exit 2;; esac

# Closing an editor discards unsaved scene edits, so only do it when told to.
if ! "$(dirname "$0")/check-removable.sh" "$wt" 2>/dev/null; then
  if [ "$force" = 0 ]; then
    echo "Unity editor is open on $wt. Close it (saving first), or pass --force to close it via the CLI." >&2
    exit 2
  fi
  "$(dirname "$0")/close-editor.sh" "$wt" || exit 2
fi

if [ "$force" = 0 ]; then
  seeded="$(git -C "$wt" rev-parse --absolute-git-dir)/unity-seeded"
  [ -f "$seeded" ] || : > "$seeded"
  # Files copied in by new-worktree.sh show as changes by design, so they don't count as dirty.
  dirty=$(git -C "$wt" status --porcelain | cut -c4- | grep -vxFf "$seeded" || true)
  unmerged=0
  if [ -n "$br" ]; then
    others=$(git -C "$main" for-each-ref --format='%(refname)' refs/heads refs/remotes | grep -vx "refs/heads/$br" || true)
    # shellcheck disable=SC2086
    unmerged=$(git -C "$main" rev-list --count "$br" --not $others)
  fi
  if [ -n "$dirty" ] || [ "$unmerged" != 0 ]; then
    [ -z "$dirty" ] || { echo "uncommitted changes in $wt:" >&2; echo "$dirty" >&2; }
    [ "$unmerged" = 0 ] || echo "$unmerged commit(s) on '$br' exist on no other branch" >&2
    echo "Merge or commit them, or pass --force to discard." >&2
    exit 2
  fi
fi

# Claude Code locks the worktrees it creates.
git -C "$main" worktree unlock "$wt" 2>/dev/null || true
if command -v unity >/dev/null; then
  # --discard-changes is safe: the checks above already refused real uncommitted work.
  (cd "$main" && unity vcs git worktree remove "$wt" --discard-changes -y --non-interactive --no-banner --quiet)
else
  git -C "$main" worktree remove --force "$wt"
fi
git -C "$main" worktree prune
if [ -n "$br" ]; then
  if [ "$force" = 1 ]; then git -C "$main" branch -D "$br"; else git -C "$main" branch -d "$br"; fi
fi
echo "removed $wt${br:+ and branch $br}"
