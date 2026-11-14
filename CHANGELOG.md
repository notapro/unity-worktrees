# Changelog

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow [SemVer](https://semver.org/).

## [1.1.0] - 2026-11-14

### Added
- Worktree seeding hooks: `seed-if-needed.sh` on SessionStart, `EnterWorktree`, SubagentStart and a Bash backstop, with a lock so concurrent seeders produce one complete Library.
- Agent editor closing: `close-agent-editor.sh` saves and closes a Unity editor on a Claude-created worktree when a subagent finishes there, `ExitWorktree` removes it, or the session ends. When saving fails, `ExitWorktree` is refused and subagent or session ends force-quit the editor.
- `close-editor.sh`: save each dirty scene (an untitled one as `Assets/Untitled.unity`, so no Save dialog blocks), then close the editor on a worktree; `--discard` skips the save and force-quits.
- Tests: `bash tests/run.sh`.

### Changed
- `new-worktree.sh` and `remove-worktree.sh` use `unity vcs git worktree add/remove` when the Unity CLI is installed (Hub registration and removal); `remove-worktree.sh` unlocks Claude's worktrees once the locking process has exited, and refuses other locks and ambiguous names without `--force`.
- `seed-worktree.sh` no longer copies the source editor's session files (`ilpp.pid`, `*-lock`).
- `hooks/session-start.sh` renamed to `hooks/seed-if-needed.sh`.
- `remove-worktree.sh` deletes the branch with `-D` once its commits are known to be on another branch.

### Fixed
- Re-seeding a worktree (for example after deleting its `Library/`) no longer overwrites its `Packages/`/`ProjectSettings/` edits.
- A seeding lock left by a killed seeder is reclaimed at once instead of stalling each Bash call.
- `new-worktree.sh` removes the half-made worktree and branch when the Unity CLI fails, drops the copied `Library/Pipeline` and `Library/Temp`, and keeps `Library/LastSceneManagerSetup.txt` so the worktree opens on the source's scene.

## [1.0.0] - 2026-11-05

### Added
- SessionStart hook that seeds unseeded linked Unity worktrees.
- `new-unity-worktree` and `remove-unity-worktree` skills.
- `seed-worktree.sh`: APFS-clones `Library/` and copies uncommitted `Packages/`/`ProjectSettings/` edits.
- Optional Orca integration (`setup-orca-integration` skill, `docs/orca.md`).
