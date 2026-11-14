#!/usr/bin/env bash
# usage: bash tests/run.sh [test_name]
# Each test_* runs in its own subshell with `set -e` and a fresh $T; exits non-zero on any FAIL.
# Put each assertion on its own line: `set -e` ignores a failure on the left of `&&`.
# Tests that call the real Unity CLI register worktrees in the Hub; cleanup removes them again.
here=$(cd "$(dirname "$0")/.." && pwd -P)
NEW="$here/skills/new-unity-worktree/new-worktree.sh"
SEED="$here/skills/new-unity-worktree/seed-worktree.sh"
REMOVE="$here/skills/remove-unity-worktree/remove-worktree.sh"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export UNITY_NO_BANNER=1 UNITY_NON_INTERACTIVE=1
LOGS=$(mktemp -d)

make_fixture() {
  P="$T/fake proj"
  mkdir -p "$P"
  git -C "$P" init -q -b main
  printf 'Library/\nTemp/\n.claude/worktrees/\n' > "$P/.gitignore"
  if [ "${1:-}" != plain ]; then
    mkdir -p "$P/ProjectSettings" "$P/Packages" "$P/Assets"
    echo "m_EditorVersion: 6000.3.10f1" > "$P/ProjectSettings/ProjectVersion.txt"
    echo '{"dependencies":{}}' > "$P/Packages/manifest.json"
    echo a > "$P/Assets/a.txt"
  fi
  git -C "$P" add -A && git -C "$P" commit -qm init
  if [ "${1:-}" != plain ]; then
    mkdir -p "$P/Library/PackageCache/p" "$P/Library/Artifacts"
    mkdir -p "$P/Library/Pipeline" "$P/Library/Temp"
    touch "$P/Library/ilpp.pid" "$P/Library/ArtifactDB-lock" "$P/Library/SourceAssetDB-lock" \
      "$P/Library/LastSceneManagerSetup.txt" "$P/Library/Pipeline/port" "$P/Library/Temp/t"
    echo x > "$P/Library/PackageCache/p/x"
    echo y > "$P/Library/Artifacts/y"
  fi
}

no_unity() (
  PATH=$(printf %s "$PATH" | tr : '\n' | grep -vx "$HOME/.unity/bin" | paste -sd: -)
  if command -v unity >/dev/null; then echo "unity still on PATH" >&2; exit 1; fi
  "$@"
)

hold_editor() { mkdir -p "$1/Temp"; sleep 600 3>"$1/Temp/UnityLockfile" & echo $! > "$T/editor.pid"; }
release_editor() { [ ! -f "$T/editor.pid" ] || kill "$(cat "$T/editor.pid")" 2>/dev/null || true; rm -f "$T/editor.pid"; }
editor_held() { [ -n "$(lsof -t "$1/Temp/UnityLockfile" 2>/dev/null || true)" ]; }

hook_json() { printf '{"session_id": "t", "cwd": "%s"%s}\n' "$1" "${2:+, $2}"; }

# Exit code 77 marks a skip.
need_unity() { command -v unity >/dev/null || { echo "Unity CLI not on PATH"; exit 77; }; }
dead_pid() { sh -c 'echo $$'; }

refute() { if "$@"; then echo "refute failed: $*" >&2; return 1; fi; }
hub_has() { unity projects list --json 2>/dev/null | grep -qF "\"$1\""; }

cleanup() {
  release_editor
  [ -n "${T:-}" ] && [ -d "$T" ] || return 0
  chmod -R u+rwx "$T" 2>/dev/null
  local main wt
  for main in "$T/fake proj"; do
    [ -d "$main/.git" ] || continue
    git -C "$main" worktree list --porcelain | sed -n 's/^worktree //p' | tail -n +2 | while IFS= read -r wt; do
      git -C "$main" worktree unlock "$wt" 2>/dev/null
      if command -v unity >/dev/null; then
        (cd "$main" && unity vcs git worktree remove "$wt" --discard-changes --force -y --quiet >/dev/null 2>&1)
      fi
      git -C "$main" worktree remove --force "$wt" 2>/dev/null
    done
  done
  rm -rf "$T"
}
trap 'cleanup; rm -rf "$LOGS"' EXIT

failed=0
check() {
  local name=$1; shift
  ( set -e; "$@" ) > "$LOGS/$name.log" 2>&1
  local rc=$?
  if [ $rc = 0 ]; then echo "ok $name"; elif [ $rc = 77 ]; then echo "skip $name"; else echo "FAIL $name"; sed 's/^/    /' "$LOGS/$name.log" | tail -20; failed=1; fi
}
run_test() { T=$(cd "$(mktemp -d)" && pwd -P); check "$1" "$1"; cleanup; }

# --- Task 1 ---

test_seed_drops_session_files() {
  make_fixture
  git -C "$P" worktree add -q "$T/fake proj-s" -b s
  "$SEED" "$T/fake proj-s" "$P"
  L="$T/fake proj-s/Library"
  [ ! -e "$L/ilpp.pid" ]
  [ ! -e "$L/ArtifactDB-lock" ]
  [ ! -e "$L/SourceAssetDB-lock" ]
  [ ! -e "$L/Pipeline" ]
  [ ! -e "$L/Temp" ]
  [ -f "$L/LastSceneManagerSetup.txt" ]
  [ -f "$L/PackageCache/p/x" ]
  [ -f "$L/Artifacts/y" ]
}

# --- Task 2 ---

new_worktree_common() {
  make_fixture
  echo '{"dependencies":{"x":"1"}}' > "$P/Packages/manifest.json"
  echo probe > "$P/ProjectSettings/Probe.asset"
  out=$(cd "$P" && "$NEW" w1)
  W="$T/fake proj-w1"
  [ "$(echo "$out" | tail -2)" = "WORKTREE=$W
BRANCH=w1" ]
  [ "$(git -C "$W" branch --show-current)" = w1 ]
  [ -f "$W/Library/PackageCache/p/x" ]
  [ ! -e "$W/Library/ilpp.pid" ]
  [ ! -e "$W/Library/Pipeline" ]
  [ ! -e "$W/Library/Temp" ]
  cmp "$P/Packages/manifest.json" "$W/Packages/manifest.json"
  cmp "$P/ProjectSettings/Probe.asset" "$W/ProjectSettings/Probe.asset"
}
test_new_with_unity() { need_unity; new_worktree_common; hub_has "$W"; }
test_new_without_unity() { no_unity new_worktree_common; }

test_new_base_ref() {
  make_fixture
  echo b > "$P/Assets/b.txt"; git -C "$P" add -A; git -C "$P" commit -qm second
  (cd "$P" && "$NEW" w2 --base HEAD~1)
  [ "$(git -C "$T/fake proj-w2" rev-parse HEAD)" = "$(git -C "$P" rev-parse HEAD~1)" ]
}

# A CLI failure after `worktree add` must leave no worktree or branch behind.
test_new_cli_failure_cleans_up() {
  make_fixture
  mkdir -p "$T/bin"
  printf '#!/bin/bash\ngit -C "$6" worktree add -q "$8" "$5"; exit 3\n' > "$T/bin/unity"
  chmod +x "$T/bin/unity"
  set +e; (cd "$P" && PATH="$T/bin:$PATH" "$NEW" w4); rc=$?; set -e
  [ "$rc" = 3 ]
  [ ! -e "$T/fake proj-w4" ]
  refute git -C "$P" rev-parse -q --verify refs/heads/w4
}

test_new_existing_branch_refused() {
  make_fixture
  git -C "$P" branch w3
  refute bash -c 'cd "$1" && "$2" w3' _ "$P" "$NEW"
  [ ! -e "$T/fake proj-w3" ]
}

# --- Task 3 ---

remove_seeded_common() {
  make_fixture
  echo '{"dependencies":{"x":"1"}}' > "$P/Packages/manifest.json"
  (cd "$P" && "$NEW" r1)
  W="$T/fake proj-r1"
  out=$(cd "$P" && "$REMOVE" r1)
  [ "$(echo "$out" | tail -1)" = "removed $W and branch r1" ]
  [ ! -e "$W" ]
  refute git -C "$P" rev-parse -q --verify refs/heads/r1
}
test_remove_seeded_only() { need_unity; remove_seeded_common; refute hub_has "$W"; }
test_remove_without_unity() { no_unity remove_seeded_common; }

test_remove_real_edit_refused() {
  make_fixture
  (cd "$P" && "$NEW" r2)
  echo n > "$T/fake proj-r2/Assets/new.txt"
  set +e; (cd "$P" && "$REMOVE" r2); rc=$?; set -e
  [ "$rc" = 2 ]
  [ -d "$T/fake proj-r2" ]
  git -C "$P" rev-parse -q --verify refs/heads/r2
}

test_remove_unmerged_refused() {
  make_fixture
  (cd "$P" && "$NEW" r3)
  echo c > "$T/fake proj-r3/Assets/c.txt"
  git -C "$T/fake proj-r3" add Assets/c.txt; git -C "$T/fake proj-r3" commit -qm c
  set +e; (cd "$P" && "$REMOVE" r3); rc=$?; set -e
  [ "$rc" = 2 ]
  (cd "$P" && "$REMOVE" r3 --force)
  refute git -C "$P" rev-parse -q --verify refs/heads/r3
}

# Commits kept on another branch are safe, so the branch goes even though -d would refuse it.
test_remove_commits_on_other_branch() {
  make_fixture
  (cd "$P" && "$NEW" r7)
  echo c > "$T/fake proj-r7/Assets/c.txt"
  git -C "$T/fake proj-r7" add Assets/c.txt; git -C "$T/fake proj-r7" commit -qm c
  git -C "$P" branch keep r7
  (cd "$P" && "$REMOVE" r7)
  refute git -C "$P" rev-parse -q --verify refs/heads/r7
}

test_remove_ambiguous_refused() {
  make_fixture
  git -C "$P" worktree add -q "$T/x" -b other
  git -C "$P" worktree add -q "$T/y" -b x
  set +e; (cd "$P" && "$REMOVE" x); rc=$?; set -e
  [ "$rc" = 2 ]
  [ -d "$T/x" ]
  [ -d "$T/y" ]
}

test_remove_plain_worktree() {
  make_fixture
  git -C "$P" worktree add -q "$T/fake proj-r4" -b r4
  (cd "$P" && "$REMOVE" r4)
  [ ! -e "$T/fake proj-r4" ]
}

test_remove_locked() {
  make_fixture
  W="$P/.claude/worktrees/r5"
  git -C "$P" worktree add -q "$W" -b worktree-r5
  git -C "$P" worktree lock --reason "claude agent a1 (pid $(dead_pid) start 1)" "$W"
  (cd "$P" && "$REMOVE" r5)
  [ ! -e "$W" ]
  refute git -C "$P" rev-parse -q --verify refs/heads/worktree-r5
}

test_remove_live_or_foreign_lock_refused() {
  make_fixture
  W="$P/.claude/worktrees/r8"
  git -C "$P" worktree add -q "$W" -b worktree-r8
  git -C "$P" worktree lock --reason "claude session s1 (pid $$ start 1)" "$W"
  refute bash -c 'cd "$1" && "$2" r8' _ "$P" "$REMOVE"
  git -C "$P" worktree unlock "$W"
  git -C "$P" worktree lock --reason mine "$W"
  refute bash -c 'cd "$1" && "$2" r8' _ "$P" "$REMOVE"
  [ -d "$W" ]
  (cd "$P" && "$REMOVE" r8 --force)
  [ ! -e "$W" ]
}

# --- Task 4 ---

# run_hook <script> <cwd> [extra-json]: hook stdout goes to $T/hook.out. HOME is faked so the
# hook's stable-path symlink never touches the real ~/.claude.
run_hook() {
  mkdir -p "$T/home/.claude"
  (cd "$2" && hook_json "$2" "${3:-}" | HOME="$T/home" CLAUDE_PLUGIN_ROOT="$here" "$here/hooks/$1") > "$T/hook.out"
}
seed_hook() { run_hook seed-if-needed.sh "$@"; }

claude_wt() { W="$P/.claude/worktrees/$1"; git -C "$P" worktree add -q "$W" -b "worktree-$1"; }

test_seed_hook_seeds_linked_worktree() {
  make_fixture; claude_wt h1
  seed_hook "$W"
  [ ! -s "$T/hook.out" ]
  [ -f "$W/Library/PackageCache/p/x" ]
}

test_seed_hook_from_subdir() {
  make_fixture; claude_wt h2
  seed_hook "$W/Assets"
  [ -f "$W/Library/PackageCache/p/x" ]
  [ ! -e "$W/Assets/Library" ]
}

# Average of 5 runs must stay under 0.2 s: this hook runs before every Bash call.
assert_fast_noop() {
  local t0 t1
  t0=$(date +%s%N)
  for _ in 1 2 3 4 5; do seed_hook "$1"; [ ! -s "$T/hook.out" ]; done
  t1=$(date +%s%N)
  echo "avg $(( (t1 - t0) / 5000000 )) ms"
  [ $(( (t1 - t0) / 5 )) -lt 200000000 ]
}
test_seed_hook_noop_main() {
  make_fixture
  assert_fast_noop "$P"
  [ -f "$P/Library/ilpp.pid" ]
}
test_seed_hook_noop_plain_repo() {
  make_fixture plain
  git -C "$P" worktree add -q "$T/fake proj-p" -b p
  assert_fast_noop "$T/fake proj-p"
  [ ! -e "$T/fake proj-p/Library" ]
}
test_seed_hook_noop_seeded() {
  make_fixture; claude_wt h3
  "$SEED" "$W" "$P" >/dev/null
  echo marker > "$W/Library/marker"
  assert_fast_noop "$W"
  [ -f "$W/Library/marker" ]
}

# Re-seeding (Library deleted) must not overwrite Packages/ edits made in the worktree.
test_seed_hook_keeps_worktree_edits() {
  make_fixture
  echo '{"dependencies":{"x":"1"}}' > "$P/Packages/manifest.json"
  claude_wt h7
  seed_hook "$W"
  echo '{"dependencies":{"mine":"1"}}' > "$W/Packages/manifest.json"
  rm -rf "$W/Library"
  seed_hook "$W"
  grep -q mine "$W/Packages/manifest.json"
  [ -f "$W/Library/PackageCache/p/x" ]
}

# A lock left by a killed seeder must not stall the next one.
test_seed_dead_pid_lock() {
  make_fixture; claude_wt h8
  lock="$(git -C "$W" rev-parse --absolute-git-dir)/unity-seeding.lock"
  mkdir "$lock"; dead_pid > "$lock/pid"
  t0=$(date +%s)
  "$SEED" "$W" "$P"
  [ $(( $(date +%s) - t0 )) -lt 10 ]
  [ -f "$W/Library/PackageCache/p/x" ]
  [ ! -e "$lock" ]
}

test_seed_hook_concurrent() {
  make_fixture; claude_wt h4
  (cd "$W" && hook_json "$W" | HOME="$T/home" CLAUDE_PLUGIN_ROOT="$here" "$here/hooks/seed-if-needed.sh") & a=$!
  (cd "$W" && hook_json "$W" | HOME="$T/home" CLAUDE_PLUGIN_ROOT="$here" "$here/hooks/seed-if-needed.sh") & b=$!
  wait $a
  wait $b
  [ -f "$W/Library/PackageCache/p/x" ]
  [ -f "$W/Library/Artifacts/y" ]
  [ ! -e "$W/Library.seeding" ]
  [ ! -e "$W/Library/Library.seeding" ]
}

test_seed_hook_failure_never_blocks() {
  make_fixture; claude_wt h5
  chmod 000 "$P/Library/Artifacts/y"
  (cd "$W" && hook_json "$W" | HOME="$T/home" CLAUDE_PLUGIN_ROOT="$here" "$here/hooks/seed-if-needed.sh") \
    > "$T/hook.out" 2> "$T/hook.err"
  chmod 644 "$P/Library/Artifacts/y"
  cat "$T/hook.err"
  [ ! -s "$T/hook.out" ]
  [ -s "$T/hook.err" ]
  [ ! -e "$W/Library.seeding" ]
}

test_seed_hook_ignores_project_dir() {
  make_fixture; claude_wt h6
  CLAUDE_PROJECT_DIR="$P" seed_hook "$W"
  [ -f "$W/Library/PackageCache/p/x" ]
}

# --- Task 5 ---
# Probed on Claude Code 2.1.322: SubagentStop's cwd is the subagent's isolated worktree
# (.claude/worktrees/agent-<agent_id>, still present); ExitWorktree's tool_input is
# {"action": "remove"}; SessionEnd's cwd is a --worktree session's worktree, still present,
# but SessionEnd hooks are cancelled within seconds, so close-agent-editor.sh starts the
# close in the background (nohup) there and the tests poll for it.

CLOSE="$here/skills/remove-unity-worktree/close-editor.sh"

# fake_unity [save-fails]: stub `unity` that logs its args; other subcommands go to the real CLI.
fake_unity() {
  local real; real=$(command -v unity || true)
  mkdir -p "$T/bin"
  cat > "$T/bin/unity" <<EOF
#!/bin/bash
echo "\$*" >> "$T/unity.log"
case "\$1 \$2" in
  "command eval") [ "${1:-}" != save-fails ];;
  close*) kill "\$(cat "$T/editor.pid")" 2>/dev/null; rm -f "$T/editor.pid";;
  *) [ -n "$real" ] && exec "$real" "\$@";;
esac
EOF
  chmod +x "$T/bin/unity"
  export PATH="$T/bin:$PATH"
}
unity_log() { cat "$T/unity.log" 2>/dev/null || true; }
wait_released() { for _ in $(seq 1 50); do editor_held "$1" || return 0; sleep 0.2; done; return 1; }

test_close_editor_saves_then_closes() {
  make_fixture; claude_wt c1; hold_editor "$W"; fake_unity
  "$CLOSE" "$W"
  unity_log
  [ "$(unity_log | sed -n 1p | grep -F "$W" | cut -d' ' -f1-2)" = "command eval" ]
  [ "$(unity_log | tail -1)" = "close $W --non-interactive --no-banner" ]
  refute editor_held "$W"
}

test_close_editor_save_fails_keeps_open() {
  make_fixture; claude_wt c2; hold_editor "$W"; fake_unity save-fails
  refute "$CLOSE" "$W"
  refute grep -q '^close' "$T/unity.log"
  editor_held "$W"
}

test_close_editor_no_editor() {
  make_fixture; claude_wt c3; fake_unity
  "$CLOSE" "$W"
  [ -z "$(unity_log)" ]
}

test_remove_force_closes_editor() {
  make_fixture
  git -C "$P" worktree add -q "$T/fake proj-r6" -b r6
  hold_editor "$T/fake proj-r6"; fake_unity
  (cd "$P" && "$REMOVE" r6 --force)
  # --force discards the worktree, so it skips the save that play mode or a dialog could fail.
  refute grep -q '^command eval' "$T/unity.log"
  grep -q '^close' "$T/unity.log"
  [ ! -e "$T/fake proj-r6" ]
}

agent_hook() { run_hook close-agent-editor.sh "$@"; }

test_subagent_stop_own_worktree() {
  make_fixture; claude_wt agent-abc; hold_editor "$W"; fake_unity
  agent_hook "$W" '"hook_event_name": "SubagentStop", "agent_id": "abc"'
  [ ! -s "$T/hook.out" ]
  refute editor_held "$W"
}

# Subagent and session ends cannot be held, so an editor that will not save is force-quit.
test_subagent_stop_save_fails_force_quits() {
  make_fixture; claude_wt agent-def; hold_editor "$W"; fake_unity save-fails
  agent_hook "$W" '"hook_event_name": "SubagentStop", "agent_id": "def"'
  grep -qx "close $W --non-interactive --no-banner --force" "$T/unity.log"
  refute editor_held "$W"
}

test_session_end_save_fails_force_quits() {
  make_fixture; claude_wt s3; hold_editor "$W"; fake_unity save-fails
  agent_hook "$W" '"hook_event_name": "SessionEnd", "reason": "other"'
  wait_released "$W"
  grep -qx "close $W --non-interactive --no-banner --force" "$T/unity.log"
}

test_subagent_stop_shared_worktree() {
  make_fixture; claude_wt t1; hold_editor "$W"; fake_unity
  agent_hook "$W" '"hook_event_name": "SubagentStop", "agent_id": "abc"'
  editor_held "$W"
  release_editor; hold_editor "$P"
  agent_hook "$P" '"hook_event_name": "SubagentStop", "agent_id": "abc"'
  editor_held "$P"
  [ -z "$(unity_log)" ]
}

test_exit_worktree_remove_closes() {
  make_fixture; claude_wt e1; hold_editor "$W"; fake_unity
  agent_hook "$W" '"hook_event_name": "PreToolUse", "tool_name": "ExitWorktree", "tool_input": {"action": "remove"}'
  refute editor_held "$W"
}

test_exit_worktree_keep_ignored() {
  make_fixture; claude_wt e2; hold_editor "$W"; fake_unity
  agent_hook "$W" '"hook_event_name": "PreToolUse", "tool_name": "ExitWorktree", "tool_input": {"action": "keep"}'
  editor_held "$W"
}

test_exit_worktree_save_fails_blocks() {
  make_fixture; claude_wt e3; hold_editor "$W"; fake_unity save-fails
  set +e
  agent_hook "$W" '"hook_event_name": "PreToolUse", "tool_name": "ExitWorktree", "tool_input": {"action": "remove"}' 2> "$T/err"
  rc=$?; set -e
  cat "$T/err"
  [ "$rc" = 2 ]
  grep -qF "Could not close the Unity editor on $W" "$T/err"
  editor_held "$W"
}

test_session_end_claude_worktree() {
  make_fixture; claude_wt s1; hold_editor "$W"; fake_unity
  agent_hook "$W" '"hook_event_name": "SessionEnd", "reason": "other"'
  wait_released "$W"
}

# SessionEnd also fires on /clear, where the session goes on in the same worktree.
test_session_end_clear_ignored() {
  make_fixture; claude_wt s2; hold_editor "$W"; fake_unity
  agent_hook "$W" '"hook_event_name": "SessionEnd", "reason": "clear"'
  sleep 1
  editor_held "$W"
  [ -z "$(unity_log)" ]
}

# The hook must outlive close-editor.sh's worst case (save + 30 s `unity close` + 90 s poll),
# or Claude kills it and ExitWorktree removes the worktree under a running editor. SubagentStop
# then force-quits (another 30 s close + poll), so it needs more.
test_close_hook_timeout_covers_close() {
  python3 - "$here/hooks/hooks.json" <<'EOF'
import json, sys
for event, groups in json.load(open(sys.argv[1]))["hooks"].items():
    for g in groups:
        for h in g["hooks"]:
            if "close-agent-editor" in h["command"]:
                assert h["timeout"] >= (270 if event == "SubagentStop" else 180), (event, h)
EOF
}

test_session_end_main_checkout() {
  make_fixture; hold_editor "$P"; fake_unity
  agent_hook "$P" '"hook_event_name": "SessionEnd", "reason": "other"'
  sleep 1
  editor_held "$P"
  [ -z "$(unity_log)" ]
}

test_session_end_user_worktree() {
  make_fixture
  (cd "$P" && "$NEW" x)
  W="$T/fake proj-x"; hold_editor "$W"; fake_unity
  agent_hook "$W" '"hook_event_name": "SessionEnd", "reason": "other"'
  sleep 1
  editor_held "$W"
  [ -z "$(unity_log)" ]
}

tests=${1:-$(declare -F | awk '$3 ~ /^test_/ {print $3}')}
for t in $tests; do run_test "$t"; done
exit $failed
