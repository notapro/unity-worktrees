# unity-worktrees

Claude Code plugin for git worktrees of Unity projects. A plain `git worktree add` has no `Library/`
(10-30 min cold import) and drops uncommitted `Packages/`/`ProjectSettings/` edits.

## What it does

- **SessionStart hook** (`hooks/session-start.sh`): when a session opens in a *linked* Unity worktree
  with no `Library/`, runs `seed-worktree.sh`. Works for worktrees from any tool, with no per-repo
  config and nothing committed.
- **`new-unity-worktree` skill**: creates a sibling worktree + branch, then seeds it.
- **`remove-unity-worktree` skill**: removes a worktree and its branch; refuses on an open editor,
  uncommitted changes or unmerged commits.
- **`seed-worktree.sh`**: APFS-clones `Library/` (~4 s, ~free; falls back to reflink/plain copy),
  deletes `Library/Pipeline` (stale CLI port/token), copies uncommitted `Packages/`+`ProjectSettings/`
  files when the base's copies match the source's HEAD. No-op outside Unity projects.

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
  `--force`; the SessionStart hook only warns.
- macOS tested only.
- Orca users: see [docs/orca.md](docs/orca.md) for the optional removal guard.

## License

[MIT](LICENSE). See [CHANGELOG.md](CHANGELOG.md) for release notes.
