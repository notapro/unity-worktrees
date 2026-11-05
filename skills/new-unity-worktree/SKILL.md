---
name: new-unity-worktree
description: Create a git worktree of a Unity project that opens fast, for parallel agent work. Branches from HEAD, copies uncommitted Packages/ProjectSettings edits, and APFS-clones Library so the first open imports almost nothing. Use when the user wants a new worktree, a parallel branch, or an isolated copy of a Unity project, and optionally to continue there with another skill.
---

# new-unity-worktree

Plain `git worktree add` gives a Unity project with no `Library/` (10-30 min cold import) and without uncommitted package/version edits (so it may not open at all). The script fixes both.

## Run

From the Unity project (any directory inside it), with the Unity editor closed:

```
~/.claude/unity-worktrees/skills/new-unity-worktree/new-worktree.sh <name> [--base REF] [--force]
```

- Creates sibling dir `<repo>-<name>` on new branch `<name>`, from `--base` (default `HEAD`).
- Copies modified/untracked files under `Packages/` and `ProjectSettings/` into it (not `Assets/`).
- Clones `Library/` (~4 s, ~free on APFS), then deletes `Library/Pipeline` so the Unity CLI cannot route to the source project.
- Refuses if an editor holds the source's `Temp/UnityLockfile`; `--force` overrides (cloning a live Library is untested).
- Last output lines: `WORKTREE=<path>` and `BRANCH=<name>`.

If the user gave no name, derive a short kebab-case one from the task. Do not ask.

Worktrees made by other tools (`git worktree add`, `claude --worktree`, other agents) are seeded by the plugin's SessionStart hook when a session starts in them; this skill is for creating one on request.

## Then

1. If the user named a follow-up (a skill, or a task such as "then brainstorm X"): call `EnterWorktree` with `path=<WORKTREE>`, then invoke that skill or start that task there.
2. Otherwise report the path and branch, and stop.

## Working in the worktree

- Every `unity` CLI call must run with cwd inside the worktree or pass `--project-path <worktree>`. With two editors open a bare call fails with `AMBIGUOUS_EDITOR`.
- Prefer batch mode (`unity test .`, `unity build .`) for verification; it needs no editor on that worktree. Open a GUI editor only for scene/prefab/play-mode work.
- Never symlink `Library/`.
- Give parallel agents disjoint scenes/prefabs; Unity YAML merges badly.
- Clean up with `remove-unity-worktree`.
