# Using unity-worktrees with Orca (optional)

The plugin works without Orca: its SessionStart hook seeds any unseeded linked Unity worktree when a
Claude session starts in it. Orca adds one thing the plugin cannot: a guard against removing a
worktree while a Unity editor has it open. Claude Code cannot see Orca deleting a worktree, and
Orca plugins only receive `worktree.removed` after the fact.

## Quick setup

Ask Claude to "set up Orca integration for this project" (skill `setup-orca-integration`), or run
`~/.claude/unity-worktrees/skills/setup-orca-integration/setup-orca.sh`. It copies a ready-made
`orca.yaml` (both hooks below plus `wait-for-setup`) into the project root; commit it on the branch
you create Orca worktrees from. The sections below explain what it contains.

## Removal guard (archive hook)

Set Orca's archive script for the repo (Settings > Repository Hooks, or a committed `orca.yaml`):

```yaml
scripts:
  archive: |
    S=~/.claude/unity-worktrees/skills/remove-unity-worktree/check-removable.sh
    if [ -x "$S" ]; then "$S"; fi
```

- The script exits 1 if an editor holds the worktree's `Temp/UnityLockfile`; Orca then refuses the
  removal (`worktree_archive_hook_failed`). "Delete Anyway" / `--allow-failed-archive-hook` overrides.
- The CLI runs the archive hook only with `orca worktree rm --run-hooks`; the app runs it always
  (app path not yet verified).
- Orca reads `orca.yaml` from the new worktree, so a committed file must be on the base commit.
  Repo-local settings in the app avoid the commit.
- Orca's `rm` leaves the branch behind; the app's delete removed it.

## Seeding at creation (optional)

The SessionStart hook is enough when an agent starts in the worktree. To seed at creation instead
(also covers opening Unity without a Claude session), add a setup script and hold the agent until it
finishes:

```yaml
scripts:
  setup: |
    S=~/.claude/unity-worktrees/skills/new-unity-worktree/seed-worktree.sh
    if [ -x "$S" ]; then "$S"; fi
setupAgentStartupPolicy: wait-for-setup
```

`seed-worktree.sh` reads `$ORCA_WORKTREE_PATH` / `$ORCA_ROOT_PATH` when set. Create with
`orca worktree create ... --setup run`.
