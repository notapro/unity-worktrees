#!/usr/bin/env bash
# usage: remove-worktree.sh <name|branch|path> [--force]
# Run from the main checkout (not from inside the worktree being removed).
set -euo pipefail

target=${1:?usage: remove-worktree.sh <name|branch|path> [--force]}; shift
force=0
[ "${1:-}" = "--force" ] && force=1

main=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")

wt=""; br=""; lock=""; matches=0
cur=""; curbr=""; curlock=""
while IFS= read -r line; do
  case $line in
    "worktree "*) cur=${line#worktree }; curbr=""; curlock="";;
    "branch "*)   curbr=${line#branch refs/heads/};;
    locked*)      curlock="${line#locked} ";;
    "")
      if [ -n "$cur" ] && [ "$cur" != "$main" ] \
         && { [ "$cur" = "$target" ] || [ "$curbr" = "$target" ] || [ "$(basename "$cur")" = "$target" ]; }; then
        wt=$cur; br=$curbr; lock=$curlock; matches=$((matches + 1))
      fi
      cur="";;
  esac
done < <(git -C "$main" worktree list --porcelain; echo)

[ -n "$wt" ] || { echo "no linked worktree matches '$target' (main checkout is never removed)" >&2; exit 2; }
[ "$matches" = 1 ] || { echo "'$target' matches $matches worktrees; pass the path instead" >&2; exit 2; }
case "$PWD/" in "$wt"/*) echo "cd out of $wt first" >&2; exit 2;; esac

# Closing an editor discards unsaved scene edits, so only do it when told to.
if ! "$(dirname "$0")/check-removable.sh" "$wt" 2>/dev/null; then
  if [ "$force" = 0 ]; then
    echo "Unity editor is open on $wt. Close it (saving first), or pass --force to close it via the CLI." >&2
    exit 2
  fi
  "$(dirname "$0")/close-editor.sh" "$wt" --discard || exit 2
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

if [ -n "$lock" ]; then
  # Claude Code locks its worktrees with "claude <agent|session> <id> (pid <pid> start <time>)";
  # unlock only when that pid is gone. Other locks need --force.
  pid=$(printf %s "$lock" | sed -nE 's/^ ?claude .*\(pid ([0-9]+) .*/\1/p')
  if [ "$force" = 0 ] && { [ -z "$pid" ] || kill -0 "$pid" 2>/dev/null; }; then
    echo "$wt is locked:${lock% }. Pass --force to unlock and remove it." >&2
    exit 2
  fi
  git -C "$main" worktree unlock "$wt"
fi
if command -v unity >/dev/null; then
  # --discard-changes is safe: the checks above already refused real uncommitted work.
  (cd "$main" && unity vcs git worktree remove "$wt" --discard-changes -y --non-interactive --no-banner --quiet)
else
  git -C "$main" worktree remove --force "$wt"
fi
git -C "$main" worktree prune
if [ -n "$br" ]; then
  # -D even without --force: the check above found every commit on another branch, which -d ignores.
  git -C "$main" branch -D "$br"
fi
echo "removed $wt${br:+ and branch $br}"
