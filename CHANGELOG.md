# Changelog

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow [SemVer](https://semver.org/).

## [1.0.0] - 2026-11-05

### Added
- SessionStart hook that seeds unseeded linked Unity worktrees.
- `new-unity-worktree` and `remove-unity-worktree` skills.
- `seed-worktree.sh`: APFS-clones `Library/` and copies uncommitted `Packages/`/`ProjectSettings/` edits.
- Optional Orca integration (`setup-orca-integration` skill, `docs/orca.md`).
