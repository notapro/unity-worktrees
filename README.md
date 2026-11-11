# unity-worktrees

Claude Code plugin for git worktrees of Unity projects. A plain `git worktree add` has no `Library/`
(10-30 min cold import) and drops uncommitted `Packages/`/`ProjectSettings/` edits.

## What it does

- **Seeding hook** (`hooks/seed-if-needed.sh`): when Claude is working in a *linked* Unity worktree
  with no `Library/`, runs `seed-worktree.sh`. Fires on session start (`claude --worktree`, Orca,
  plain `git worktree add`), after `EnterWorktree`, on subagent start (`isolation: "worktree"`), and
  before each Bash call as a backstop (a no-op in ~10-25 ms once seeded). It only observes: Claude
  still creates and removes its worktrees itself.
- **Editor-closing hook** (`hooks/close-agent-editor.sh`): when a subagent finishes in its isolated
  worktree, `ExitWorktree` removes a worktree, or a session in a Claude-created worktree ends, an
  open Unity editor there is saved and closed (`close-editor.sh`). Never on the main project or on
  worktrees made outside Claude (`<repo>/.claude/worktrees/` only).
- **`new-unity-worktree` skill**: creates a sibling worktree + branch, then seeds it.
- **`remove-unity-worktree` skill**: removes a worktree and its branch; refuses on an open editor,
  uncommitted changes or unmerged commits. Handles Claude's locked worktrees.
- **Unity CLI**, when installed: both skills go through `unity vcs git worktree add/remove`
  (editor-version check, Hub registration and removal). Without it they use plain git.
- **`seed-worktree.sh`**: APFS-clones `Library/` (~4 s, ~free; falls back to reflink/plain copy),
  copies uncommitted `Packages/`+`ProjectSettings/` files when the base's copies match the source's
  HEAD. Drops the source editor's session files (`Pipeline/`, `ilpp.pid`, `*-lock`) but keeps
  `PackageCache/`: a full Library measured ~2x faster first open than Unity's default
  `--seed cache`. No-op outside Unity projects.

## Install

```
claude plugin marketplace add notapro/unity-worktrees
claude plugin install unity-worktrees@agentic-workflows
```

The hook also keeps a symlink `~/.claude/unity-worktrees` -> the installed plugin, so skills and
other tools can use a path that survives plugin version bumps.

## Limits

- Opening Unity by hand in an unseeded worktree, with no Claude session started there, gets no
  Library; run `seed-worktree.sh` yourself.
- Cloning a `Library/` while its editor is open is untested: `new-worktree.sh` refuses unless
  `--force`; the seeding hook only warns.
- If saving fails (for example the editor is still loading or shows a modal dialog), the editor is
  left open: `ExitWorktree` removal is refused, but a subagent or session end cannot be held, and
  Claude may then delete a subagent's worktree under the running editor. Close it with
  `unity close <path>` (discards unsaved work).
- `SessionEnd` from `/clear` is ignored, so the editor stays open while the session continues. Editors on worktrees made outside Claude must be closed by whoever
  opened them.
- `SubagentStart` cannot hold a subagent, so its first command may wait on the seeding lock.
- Verified on macOS only for now (the APFS clone is macOS-specific; other platforms are untested).
- Orca users: see [docs/orca.md](docs/orca.md) for the optional removal guard.

## Tests

`bash tests/run.sh [test_name]` (macOS; tests that need the Unity CLI register and remove Hub rows).

## License

[MIT](LICENSE). See [CHANGELOG.md](CHANGELOG.md) for release notes.
