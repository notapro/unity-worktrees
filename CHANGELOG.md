# Changelog

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow [SemVer](https://semver.org/).

## [1.1.0] - 2026-11-11

### Added
- Worktree seeding hooks: `seed-if-needed.sh` on SessionStart, `EnterWorktree`, SubagentStart and a Bash backstop, with a lock so concurrent seeders produce one complete Library.
- Agent editor closing: `close-agent-editor.sh` saves and closes a Unity editor on a Claude-created worktree when a subagent finishes there, `ExitWorktree` removes it, or the session ends.
- `close-editor.sh`: save, then close, an editor on a worktree.
- Tests: `bash tests/run.sh`.

### Changed
- `new-worktree.sh` and `remove-worktree.sh` use `unity vcs git worktree add/remove` when the Unity CLI is installed (Hub registration and removal); `remove-worktree.sh` handles Claude's locked worktrees.
- `seed-worktree.sh` no longer copies the source editor's session files (`ilpp.pid`, `*-lock`).
- `hooks/session-start.sh` renamed to `hooks/seed-if-needed.sh`.
- `remove-worktree.sh --force` saves before closing the editor.

## [1.0.0] - 2026-11-05

### Added
- SessionStart hook that seeds unseeded linked Unity worktrees.
- `new-unity-worktree` and `remove-unity-worktree` skills.
- `seed-worktree.sh`: APFS-clones `Library/` and copies uncommitted `Packages/`/`ProjectSettings/` edits.
- Optional Orca integration (`setup-orca-integration` skill, `docs/orca.md`).
