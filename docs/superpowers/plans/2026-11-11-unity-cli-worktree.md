# Unity CLI + Claude Worktree Seeding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the skills' worktree create/remove on the Unity CLI's `unity vcs git worktree add/remove`, stop cloning the source editor's session files, and seed every worktree Claude Code creates (`claude --worktree`, `EnterWorktree`, subagent `isolation: "worktree"`, anything else) without taking over Claude's worktree creation.

**Architecture:** `new-worktree.sh` calls `unity vcs git worktree add --seed full` when `unity` is on PATH (else `git worktree add`), then `seed-worktree.sh` copies uncommitted `Packages/`+`ProjectSettings/` files. `remove-worktree.sh` keeps its checks and swaps only its final delete for `unity vcs git worktree remove`. The SessionStart script becomes `hooks/seed-if-needed.sh`, a cheap "is this an unseeded linked Unity worktree?" check on the hook's working directory (no JSON parsing, so the Bash backstop stays fast); it is registered on `SessionStart`, `PostToolUse` (`EnterWorktree`), `SubagentStart` and, as a backstop, `PreToolUse` (`Bash`). Claude keeps creating and removing worktrees itself. When an agent's work on a Claude-created worktree ends (`SubagentStop` for its isolated worktree, `ExitWorktree` removal, `SessionEnd`), `close-editor.sh` saves and closes any Unity editor open on it, so removal is not rejected.

**Tech Stack:** bash, git, python3 (stdin JSON; ships with the Xcode CLT that git needs), Unity CLI 1.0.0-beta.12, Unity 6000.3.10f1 (fixtures), Claude Code 2.1.322.

**Spec:** the comparison and hook probes in this session (no separate doc). Facts it rests on:
- `--seed full` opened in 18 s / 19 s, same as our whole-Library clone (17 / 19); default `--seed cache` took 38 / 26. Always `--seed full`.
- Unity's `add` does not copy uncommitted `Packages/`/`ProjectSettings/` edits. Its `remove` keeps the branch, calls seeded files dirty, and needs `-y` non-interactively.
- Probed on 2.1.322, each hook's stdin `cwd` (and `$PWD`) was the new worktree: `SessionStart` for `claude --worktree`; `PostToolUse` on `EnterWorktree` (its `tool_response` also names the path); `SubagentStart` and the subagent's `PreToolUse` Bash calls for `isolation: "worktree"`. `CLAUDE_PROJECT_DIR` stays at the main project root, so it must not be used to find the worktree.
- `SubagentStart` cannot block the subagent. `PreToolUse` exit 2 blocks the tool call.
- Claude's worktrees live at `<repo>/.claude/worktrees/<name>` on branch `worktree-<name>`, and git shows them as **locked**. A subagent's isolated worktree is named `agent-<id>`.
- `unity close <project>` closes the editor on a project **without saving**. macOS does not expose another process's environment (`ps eww` showed nothing), so a hook cannot tell who launched an editor; ownership is decided by path instead.

## Global Constraints

- Keep existing contracts: `new-worktree.sh <name> [--base REF] [--force]` prints `WORKTREE=<path>` / `BRANCH=<name>` last, path `<parent>/<repo>-<name>`; `remove-worktree.sh <name|branch|path> [--force]` prints `removed <path> and branch <name>` last.
- `unity` is optional everywhere; without it behaviour equals 1.0.0.
- Library clone keeps `PackageCache/` and `LastSceneManagerSetup.txt`; drops `Pipeline/`, `Temp/`, `ilpp.pid`, `*-lock`.
- Unity CLI calls use `--non-interactive --no-banner`; `remove` also `-y`.
- `seed-if-needed.sh` always exits 0 and prints nothing on stdout; its no-op path (non-Unity repo, main checkout, Library present) runs no copy and stays under ~50 ms, because it runs before every Bash call.
- Hooks never create or remove worktrees. They close a Unity editor only on a Claude-created worktree (path under `<repo>/.claude/worktrees/`), only after saving its open scenes and assets, and leave it open if saving fails.
- macOS only. Commits: `type: short description`, ≤50 chars, imperative, no body.

## Review Focus

1. Two seeders at once (subagent's `SubagentStart` and its first Bash call, or parallel Bash calls) → one complete Library, no half-copied state, both exit 0 (Task 4 test `seed_hook_concurrent`).
2. Bash backstop in a non-Unity repo or an already-seeded worktree → no visible effect and no noticeable delay (Task 4 tests `seed_hook_noop_*`, with a timing assertion).
3. Hook invoked from a subdirectory of the worktree (`cwd` = `<wt>/Assets`) → seeds the worktree root (Task 4 test `seed_hook_from_subdir`).
4. Seeding fails (unreadable source file) → hook still exits 0 and the Bash call proceeds; stderr says why (Task 4 test `seed_hook_failure_never_blocks`).
5. Editor open on the main project or on a non-Claude worktree (Orca, `new-unity-worktree`) when a subagent or session there ends → never closed (Task 5 tests `subagent_stop_shared_worktree`, `session_end_main_checkout`, `session_end_user_worktree`).

---

### Task 1: Test harness + drop editor-session files from the clone

**Files:**
- Create: `tests/run.sh`
- Modify: `skills/new-unity-worktree/seed-worktree.sh` (the `rm -rf "$tmp/Pipeline" "$tmp/Temp"` line)

**Interfaces:**
- Produces (in `tests/run.sh`, used by Tasks 2–5):
  - `make_fixture [plain]` → `$T/fake proj`: git repo, one commit on `main`, `.gitignore` ignoring `Library/`, `Temp/`, `.claude/worktrees/`. Unity form adds `ProjectSettings/ProjectVersion.txt` = `m_EditorVersion: 6000.3.10f1`, `Packages/manifest.json` = `{"dependencies":{}}`, `Assets/a.txt`, and an ignored `Library/` with `ilpp.pid`, `ArtifactDB-lock`, `SourceAssetDB-lock`, `LastSceneManagerSetup.txt`, `PackageCache/p/x`, `Artifacts/y`. `plain` form has none of the Unity files.
  - `no_unity <cmd...>` → runs cmd with `~/.unity/bin` stripped from PATH, asserting `! command -v unity`.
  - `hold_editor <dir>` → backgrounds a process holding `<dir>/Temp/UnityLockfile` open; `release_editor` kills it.
  - `hook_json <cwd> [extra-json-fields]` → prints `{"cwd": "<cwd>", "hook_event_name": "...", ...}` for piping into a hook.
  - `check <name> <cmd...>` → prints `ok <name>` / `FAIL <name>`; script exits non-zero on any failure.
  - `$T` = fresh `mktemp -d`; EXIT trap force-removes leftover worktrees (so no Hub rows leak) and deletes `$T`.
  - Tests are `test_*` functions; `bash tests/run.sh [name]` runs all or one.

- [ ] **Step 1: Write the failing test** `test_seed_drops_session_files`: fixture, `git worktree add "$T/fake proj-s" -b s`, run `seed-worktree.sh "$T/fake proj-s" "$T/fake proj"`; assert new Library lacks `ilpp.pid`, `ArtifactDB-lock`, `SourceAssetDB-lock`, and has `LastSceneManagerSetup.txt`, `PackageCache/p/x`, `Artifacts/y`.
- [ ] **Step 2: Run** `bash tests/run.sh test_seed_drops_session_files` — expect `FAIL`.
- [ ] **Step 3: Implement** — extend the existing `rm -rf` to also remove `"$tmp/ilpp.pid"` and `"$tmp"/*-lock`; update its comment: these belong to the source editor's session.
- [ ] **Step 4: Run** `bash tests/run.sh` — `ok`, exit 0.
- [ ] **Step 5: Commit** `git add tests/run.sh skills/new-unity-worktree/seed-worktree.sh && git commit -m "fix: skip source editor session files in seed"`

### Task 2: `new-worktree.sh` via Unity CLI

**Files:**
- Modify: `skills/new-unity-worktree/new-worktree.sh` (the `git -C "$src" worktree add ...` line)
- Test: `tests/run.sh`

**Interfaces:**
- Consumes: Task 1 helpers.
- Produces: unchanged contract.

- [ ] **Step 1: Write the failing tests:**
  - `test_new_with_unity`: fixture; uncommitted `manifest.json` edit and untracked `ProjectSettings/Probe.asset`; `new-worktree.sh w1`. Assert exit 0; last lines `WORKTREE=$T/fake proj-w1`, `BRANCH=w1`; checked-out branch `w1`; `Library/PackageCache/p/x` present, `Library/ilpp.pid` absent; `manifest.json` and `Probe.asset` byte-equal the source's; `unity projects --json` lists the worktree.
  - `test_new_base_ref`: second commit in fixture; `new-worktree.sh w2 --base HEAD~1`; worktree HEAD = source `HEAD~1`.
  - `test_new_existing_branch_refused`: `git branch w3`; `new-worktree.sh w3` exits non-zero, `$T/fake proj-w3` absent.
  - `test_new_without_unity`: `test_new_with_unity` minus the Hub check, under `no_unity`.
- [ ] **Step 2: Run** `bash tests/run.sh` — expect `FAIL test_new_with_unity` (Hub check).
- [ ] **Step 3: Implement:**
  - If `command -v unity`: `git -C "$src" branch "$name" "$base"` (refuses an existing branch, as today, and supplies the `--base` the Unity CLI lacks), then `unity vcs git worktree add "$name" "$src" --into "$dst" --seed full --non-interactive --no-banner --quiet`; on failure delete that branch and exit with its status.
  - Else: today's `git -C "$src" worktree add -b "$name" "$dst" "$base"`.
  - Keep the editor-open check before and `seed-worktree.sh "$dst" "$src"` after both paths.
  - First check by hand that `unity vcs git worktree add` checks out an existing branch instead of erroring; if it errors, report back before choosing another approach.
- [ ] **Step 4: Run** — all `ok`.
- [ ] **Step 5: Commit** `git commit -am "feat: create worktrees via unity CLI when present"` (include `tests/run.sh`).

### Task 3: `remove-worktree.sh` via Unity CLI, locked worktrees

**Files:**
- Modify: `skills/remove-unity-worktree/remove-worktree.sh` (the `git -C "$main" worktree remove --force "$wt"` line)
- Test: `tests/run.sh`

**Interfaces:**
- Consumes: Task 1 helpers, `new-worktree.sh`.
- Produces: unchanged contract.

- [ ] **Step 1: Write the failing tests:**
  - `test_remove_seeded_only`: uncommitted manifest edit; `new-worktree.sh r1`; `remove-worktree.sh r1` exits 0, last line `removed $T/fake proj-r1 and branch r1`, dir and branch gone, worktree absent from `unity projects --json`.
  - `test_remove_real_edit_refused`: add `Assets/new.txt` in `r2`; exits 2; dir and branch remain.
  - `test_remove_unmerged_refused`: commit in `r3`; exits 2; with `--force` exits 0 and branch gone.
  - `test_remove_plain_worktree`: `git worktree add "$T/fake proj-r4" -b r4`; `remove-worktree.sh r4` exits 0.
  - `test_remove_locked`: `git worktree add "$T/fake proj/.claude/worktrees/r5" -b worktree-r5` then `git worktree lock` it (as Claude does); `remove-worktree.sh r5` exits 0, dir and branch gone.
  - `test_remove_without_unity`: `test_remove_seeded_only` minus Hub check, under `no_unity`.
- [ ] **Step 2: Run** — expect `FAIL` for the Hub check and the locked case.
- [ ] **Step 3: Implement** — before removing, `git -C "$main" worktree unlock "$wt" 2>/dev/null || true` (comment: Claude locks its worktrees). Then if `command -v unity`, `(cd "$main" && unity vcs git worktree remove "$wt" --discard-changes -y --non-interactive --no-banner --quiet)`, else the existing git line. Comment: `--discard-changes` is safe because the checks above already cleared dirty state. Everything else unchanged.
- [ ] **Step 4: Run** — all `ok`.
- [ ] **Step 5: Commit** `git commit -am "feat: remove worktrees via unity CLI when present"`

### Task 4: Seed Claude-created worktrees from observing hooks

**Files:**
- Rename: `hooks/session-start.sh` → `hooks/seed-if-needed.sh` (`git mv`)
- Modify: `hooks/seed-if-needed.sh`, `skills/new-unity-worktree/seed-worktree.sh` (lock around the clone), `hooks/hooks.json`
- Test: `tests/run.sh`

**Interfaces:**
- Consumes: `seed-worktree.sh <worktree> [source]`.
- Produces: `hooks/seed-if-needed.sh` discards stdin, seeds the worktree containing `$PWD` if it is an unseeded linked Unity worktree; exit 0, empty stdout, always. (The probe showed `$PWD` = the hook's `cwd` for all four events.)
- `hooks.json` entries, all `command` `"${CLAUDE_PLUGIN_ROOT}/hooks/seed-if-needed.sh"`, `shell: bash`, `timeout: 300`:
  - `SessionStart`, matcher `startup|resume` (unchanged)
  - `PostToolUse`, matcher `EnterWorktree`
  - `SubagentStart`, no matcher
  - `PreToolUse`, matcher `Bash` (backstop)

- [ ] **Step 1: Write the failing tests** (run the hook with `cd "<cwd>"` and `hook_json` on stdin; "with that `cwd`" below means both):
  - `test_seed_hook_seeds_linked_worktree`: `git worktree add "$T/fake proj/.claude/worktrees/h1" -b worktree-h1`; hook with that `cwd` → exit 0, empty stdout, `Library/PackageCache/p/x` present.
  - `test_seed_hook_from_subdir`: same with `cwd` = `<wt>/Assets` → worktree root seeded.
  - `test_seed_hook_noop_main`, `test_seed_hook_noop_plain_repo`, `test_seed_hook_noop_seeded`: main checkout / `make_fixture plain` worktree / already-seeded worktree → exit 0, nothing changed, each run under 0.2 s (`date +%s%N` around 5 runs, averaged; loose bound for CI noise).
  - `test_seed_hook_concurrent`: start two hook runs on the same unseeded worktree in the background; both exit 0; Library complete (`PackageCache/p/x`, `Artifacts/y`); no `Library.seeding` left.
  - `test_seed_hook_failure_never_blocks`: `chmod 000` a file in the source Library → exit 0, stderr non-empty, no `Library.seeding` left; restore perms.
  - `test_seed_hook_ignores_project_dir`: `CLAUDE_PROJECT_DIR` = main checkout, `cwd` = worktree → worktree seeded.
- [ ] **Step 2: Run** — expect `FAIL` (no `seed-if-needed.sh`; old script reads `CLAUDE_PROJECT_DIR`).
- [ ] **Step 3: Implement:**
  - `git mv hooks/session-start.sh hooks/seed-if-needed.sh`; replace `${CLAUDE_PROJECT_DIR:-$PWD}` with `$PWD` and add `cat >/dev/null` to drain stdin; keep the existing checks in cheapest-first order (`Library` exists → exit before any other git call where possible); send all output to stderr; update the header comment to list the four events.
  - In `seed-worktree.sh`, serialize seeders with `mkdir "$gitdir/unity-seeding.lock"`: if the mkdir fails, wait (poll 1 s, up to 120 s) for the lock to go, then exit 0 if `Library` now exists; remove the lock on exit via `trap`. Comment: the Bash backstop and SubagentStart can fire together. A lock older than 10 min counts as stale and is removed.
  - Update `hooks.json` as in Interfaces.
- [ ] **Step 4: Run** — all `ok`, including Tasks 1–3 tests.
- [ ] **Step 5: Commit** `git add -A hooks skills tests && git commit -m "feat: seed Claude-created worktrees via hooks"`

### Task 5: Close agent editors when the agent's work ends

**Files:**
- Create: `skills/remove-unity-worktree/close-editor.sh`, `hooks/close-agent-editor.sh`
- Modify: `skills/remove-unity-worktree/remove-worktree.sh` (the `--force` block: inline `unity command eval … Exit(0)` + wait loop), `hooks/hooks.json`, `skills/new-unity-worktree/SKILL.md` ("Working in the worktree")
- Test: `tests/run.sh`

**Interfaces:**
- Consumes: `check-removable.sh <dir>` (exit 1 if an editor holds it); Task 1 helpers.
- Produces:
  - `close-editor.sh <worktree>` → exit 0 if no editor holds `<worktree>/Temp/UnityLockfile` (no `unity` calls) or it was saved and closed; exit 1 with a stderr reason if `unity` is missing, saving failed (editor left open), or the lock is still held after 90 s.
  - `hooks/close-agent-editor.sh` reads hook JSON (`hook_event_name`, `cwd`, `agent_id`, `tool_input`). Acts only when `root` = `git -C "$cwd" rev-parse --show-toplevel` is a linked worktree under `<main checkout>/.claude/worktrees/`, and:
    - `SubagentStop`: `basename "$root"` = `agent-$agent_id` (the subagent's own isolated worktree).
    - `PreToolUse` on `ExitWorktree`: the removal action (field confirmed in Step 1). On close failure → exit 2, stderr `Could not close the Unity editor on <root>: <reason>. Save and close it, then retry.`
    - `SessionEnd`: no extra condition.
    Otherwise, and for every non-blocking failure, exit 0 (reason on stderr). Stdout always empty.
  - `hooks.json`: `SubagentStop` (no matcher), `PreToolUse` matcher `ExitWorktree`, `SessionEnd` (no matcher); all `command` `"${CLAUDE_PLUGIN_ROOT}/hooks/close-agent-editor.sh"`, `shell: bash`, `timeout: 120`.
  - `tests/run.sh` gains `fake_unity [save-fails]`: puts a stub `unity` first on PATH that appends its args to `$T/unity.log`; `command eval` exits 1 when `save-fails` is set, else 0; `close` kills the `hold_editor` process.

- [ ] **Step 1: Verify hook inputs.** In a scratch repo whose `.claude/settings.json` logs stdin plus `[ -d "$cwd" ]` for `SubagentStop`, `SessionEnd` and `PreToolUse` (`ExitWorktree`), run headless with minimal tools, as in the session's probe: an Agent with `isolation: "worktree"` running `pwd`; `EnterWorktree` then `ExitWorktree` removing it; `--worktree s1`. Record: `agent_id` vs the `agent-<id>` dir name and `SubagentStop`'s `cwd`; the `ExitWorktree` removal field and value; whether the worktree dir still exists when `SessionEnd` fires; whether a `SessionEnd` hook that sleeps 60 s runs to completion (log a line after the sleep) or is killed. If it is killed early, `SessionEnd` can only start the close in the background (`nohup close-editor.sh … &`): use that and note it in the test header. If `SubagentStop` does not identify the isolated worktree, or `SessionEnd` fires after removal, write that in `tests/run.sh`'s header comment and report it before going on. Delete the scratch repo.
- [ ] **Step 2: Write the failing tests:**
  - `test_close_editor_saves_then_closes`: `hold_editor` + `fake_unity`; exit 0; `unity.log` shows `command eval` (save) before `close`, both with the worktree path; lock released.
  - `test_close_editor_save_fails_keeps_open`: `fake_unity save-fails`; exit 1; no `close` in the log; lock still held.
  - `test_close_editor_no_editor`: exit 0; `unity.log` empty.
  - `test_remove_force_closes_editor`: `remove-worktree.sh <wt> --force` with held editor + `fake_unity` → exit 0, log shows save then close, worktree removed.
  - `test_subagent_stop_own_worktree`: worktree at `.claude/worktrees/agent-abc`, `agent_id` `abc`, held editor → closed, exit 0.
  - `test_subagent_stop_shared_worktree`: `agent_id` `abc`, `cwd` = `.claude/worktrees/t1` and, separately, the main checkout → not closed, log empty.
  - `test_exit_worktree_remove_closes`: removal action → closed, exit 0.
  - `test_exit_worktree_keep_ignored`: keep action → exit 0, still open.
  - `test_exit_worktree_save_fails_blocks`: `fake_unity save-fails` → exit 2, stderr names the path, still open.
  - `test_session_end_claude_worktree`: `.claude/worktrees/s1` → closed.
  - `test_session_end_main_checkout`, `test_session_end_user_worktree` (sibling `fake proj-x` from `new-worktree.sh`) → not closed, log empty.
- [ ] **Step 3: Run** — all `FAIL`.
- [ ] **Step 4: Implement:**
  - `close-editor.sh`: `check-removable.sh` passes → exit 0. Else `unity command eval --project-path "$wt" --caller agent --skill unity-cli --result-only 'UnityEditor.SceneManagement.EditorSceneManager.SaveOpenScenes(); UnityEditor.AssetDatabase.SaveAssets(); return 0;'` (failure → exit 1, no close, comment: `unity close` discards unsaved work); then `unity close "$wt" --non-interactive --no-banner`; poll the lock every 3 s up to 90 s.
  - `remove-worktree.sh --force`: replace the inline eval + wait loop with `close-editor.sh "$wt" || exit 2`. Behaviour change: it now saves before closing (harmless, the worktree is deleted next).
  - `close-agent-editor.sh` as in Interfaces; parse JSON with one `python3 -c`.
  - `new-unity-worktree/SKILL.md`, "Working in the worktree": if you open a GUI editor on a worktree, save and close it (`close-editor.sh <worktree>`) when your work there is done; hooks do it for Claude-created worktrees, but not for others.
  - Update `hooks.json` as in Interfaces.
- [ ] **Step 5: Run** `bash tests/run.sh` — all `ok`.
- [ ] **Step 6: Commit** `git add -A hooks skills tests && git commit -m "feat: close agent editors when work ends"`

### Task 6: Docs and release 1.1.0

**Files:**
- Modify: `README.md`, `skills/new-unity-worktree/SKILL.md`, `skills/remove-unity-worktree/SKILL.md`, `CHANGELOG.md`, `.claude-plugin/plugin.json` (`"version": "1.1.0"`)

- [ ] **Step 1: Edit docs.**
  - README "What it does": rename the SessionStart bullet to `seed-if-needed.sh` and list its four events (SessionStart, `EnterWorktree`, subagent start, Bash backstop); say it never changes how Claude creates or removes worktrees; add `close-agent-editor.sh`: when a subagent finishes in its isolated worktree, `ExitWorktree` removes a worktree, or a session in a Claude-created worktree ends, an open Unity editor there is saved and closed (never on the main project or on worktrees made outside Claude); CLI-backed skills (editor-version check, Hub registration) when the Unity CLI is installed; dropped session files (one line: keeping `PackageCache` measured ~2x faster first open than Unity's default `--seed cache`). "Limits": if saving fails the editor is left open, so `ExitWorktree` is refused and a subagent/session end only warns; editors on worktrees made outside Claude must be closed by whoever opened them; `SubagentStart` cannot hold a subagent, so its first command may wait on the seeding lock. Add "Tests: `bash tests/run.sh`".
  - `new-unity-worktree/SKILL.md`: Unity CLI use; Claude-created worktrees are seeded automatically.
  - `remove-unity-worktree/SKILL.md`: handles Claude's locked worktrees; drops the Hub row when the Unity CLI is installed.
  - CHANGELOG `## [1.1.0] - <date>`: Added (worktree seeding hooks, agent editor closing, `close-editor.sh`, tests), Changed (CLI-backed create/remove, session files dropped, `session-start.sh` renamed, `remove-worktree.sh --force` saves before closing the editor).
- [ ] **Step 2: Verify** `bash tests/run.sh` exits 0; `python3 -m json.tool` succeeds on `.claude-plugin/plugin.json` and `hooks/hooks.json`.
- [ ] **Step 3: Commit** `git commit -am "docs: document worktree hooks for 1.1.0"`

### Task 7: End-to-end check in real Claude sessions (no code)

- [ ] **Step 1:** Install the branch build (reinstall the plugin from this checkout). In a scratchpad clone of a real Unity project (`git clone` + `cp -cR Library`), run headless with minimal tools, as in the session's probe (`claude -p --model haiku --allowedTools "Bash(ls *)" …`):
  - `--worktree e1` → `ls Library | head` shows a Library.
  - `EnterWorktree` named `e2` then `ls Library | head` → Library present.
  - Agent with `isolation: "worktree"` running `ls Library | head` → Library present.
- [ ] **Step 2:** Headless-open `e1` (`Unity -batchmode -quit -nographics -projectPath …`); expect an `InitialRefreshV2` total near the 12–13.5 s measured for `--seed full`.
- [ ] **Step 3:** Editor closing with a real GUI editor: an Agent with `isolation: "worktree"` (allowed tools `Bash(unity open *)`, `Bash(ls *)`) runs `unity open .` in its worktree, waits for `Temp/UnityLockfile`, and finishes. Expect the editor to be closed within ~90 s of the subagent finishing. Repeat with `EnterWorktree` + `unity open .` + `ExitWorktree` removal: the removal must succeed, not be refused.
- [ ] **Step 4:** Remove `e1`/`e2` and the agent worktree with `remove-worktree.sh` (exercises locked worktrees). Report the numbers; delete the scratch clone.
