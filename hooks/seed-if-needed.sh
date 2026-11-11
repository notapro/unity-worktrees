#!/usr/bin/env bash
# If the hook's working directory is in a linked Unity worktree that has no Library, seed it.
# Registered on SessionStart (claude --worktree, Orca, plain git worktrees), PostToolUse
# EnterWorktree, SubagentStart (isolation: "worktree") and PreToolUse Bash as a backstop.
# The hook's cwd is the worktree for all four; CLAUDE_PROJECT_DIR stays at the main checkout.
# Runs before every Bash call, so the no-op path must stay cheap. Never blocks, never prints on stdout.
cat >/dev/null
exec >&2
root=$(cd "${CLAUDE_PLUGIN_ROOT:?}" && pwd -P)

# Stable path for scripts that cannot know the versioned plugin cache dir.
ln -sfn "$root" "$HOME/.claude/unity-worktrees" 2>/dev/null || true

# Common case (session at an already-seeded worktree root): exit without forking git.
[ ! -e "$PWD/Library" ] || [ ! -d "$PWD/ProjectSettings" ] || exit 0
{ read -r wt; read -r gitdir; read -r common; } < <(git rev-parse --path-format=absolute --show-toplevel --git-dir --git-common-dir 2>/dev/null)
[ -n "$common" ] || exit 0
[ -f "$wt/ProjectSettings/ProjectVersion.txt" ] || exit 0
[ ! -e "$wt/Library" ] || exit 0
# Main checkouts keep their own Library; only linked worktrees are seeded.
[ "$gitdir" != "$common" ] || exit 0

"$root/skills/new-unity-worktree/seed-worktree.sh" "$wt" || echo "unity-worktrees: seeding $wt failed; first editor open will import everything"
exit 0
