---
name: remove-unity-worktree
description: Remove a Unity git worktree created by new-unity-worktree, plus its branch, after checking for uncommitted work, unmerged commits and a running editor. Use when the user is done with a worktree, wants to clean up parallel branches, or says remove/delete/discard a worktree.
---

# remove-unity-worktree

## Run

From the main checkout (not from inside the worktree being removed):

```
~/.claude/unity-worktrees/skills/remove-unity-worktree/remove-worktree.sh <name|branch|path> [--force]
```

If the session's cwd is inside the target (for example after `EnterWorktree`), call `ExitWorktree` with `action: "keep"` first, then run the script from the main checkout.

The script refuses (exit 2) and prints why when:
- an editor holds the worktree's `Temp/UnityLockfile` (closing it would lose unsaved scene edits),
- there are uncommitted changes (files seeded by `new-unity-worktree` are ignored),
- the branch has commits that exist on no other branch,
- the target is the main checkout,
- the name matches more than one worktree (pass the path),
- the worktree is locked by anything other than a Claude agent or session that has exited.

On a refusal, show the user the reason and ask. Merge or commit first if they want the work kept.

`--force` closes the editor without saving (`close-editor.sh --discard`), unlocks the worktree, discards uncommitted changes and unmerged commits, and deletes the branch. Use it only when the user has said to discard the work.

Claude's own worktrees (`.claude/worktrees/<name>`) are unlocked and removed like any other once the Claude process holding the lock has exited. With the Unity CLI installed, removal goes through `unity vcs git worktree remove`, which also drops the Hub row.

Report the script's last line (`removed <path> and branch <name>`).
