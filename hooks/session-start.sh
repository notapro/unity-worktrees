#!/usr/bin/env bash
# SessionStart: if the session opens in a linked Unity worktree that has no Library, seed it.
# Covers worktrees made by Orca, plain `git worktree add` or `claude --worktree`.
# Never fails the session.
root=$(cd "${CLAUDE_PLUGIN_ROOT:?}" && pwd -P)

# Stable path for scripts that cannot know the versioned plugin cache dir.
ln -sfn "$root" "$HOME/.claude/unity-worktrees" 2>/dev/null || true

wt=$(git -C "${CLAUDE_PROJECT_DIR:-$PWD}" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -f "$wt/ProjectSettings/ProjectVersion.txt" ] || exit 0
[ ! -e "$wt/Library" ] || exit 0
# Main checkouts keep their own Library; only linked worktrees are seeded.
[ "$(git -C "$wt" rev-parse --absolute-git-dir)" != "$(git -C "$wt" rev-parse --path-format=absolute --git-common-dir)" ] || exit 0

"$root/skills/new-unity-worktree/seed-worktree.sh" "$wt" || echo "unity-worktrees: seeding $wt failed; first editor open will import everything" >&2
exit 0
