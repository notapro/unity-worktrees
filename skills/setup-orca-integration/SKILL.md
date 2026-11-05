---
name: setup-orca-integration
description: Add the unity-worktrees Orca hooks (Library seeding on worktree creation, editor-open guard on removal) to the current Unity project by copying orca.yaml into its root. Use when the user wants to integrate this plugin with Orca, or asks for Orca setup/archive hooks for a Unity project.
---

# setup-orca-integration

Orca runs repo hooks from an `orca.yaml` at the project root. This copies the plugin's template there.

## Run

From the Unity project (or pass its path):

```
~/.claude/unity-worktrees/skills/setup-orca-integration/setup-orca.sh [project-dir] [--force]
```

- Refuses outside a Unity project, and if `orca.yaml` already exists. Show the user the existing file and ask before using `--force`; do not merge by hand unless asked.
- It does not commit. Tell the user the file must be committed on the branch they create Orca worktrees from, because Orca reads `orca.yaml` from the new worktree. Commit only if they ask.
- If it warns that `~/.claude/unity-worktrees` is missing, the plugin's SessionStart hook has not run yet: a new Claude session fixes it.

What the template does is explained in the plugin's `docs/orca.md`.
