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
    touch "$P/Library/ilpp.pid" "$P/Library/ArtifactDB-lock" "$P/Library/SourceAssetDB-lock" \
      "$P/Library/LastSceneManagerSetup.txt"
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
  if [ $? = 0 ]; then echo "ok $name"; else echo "FAIL $name"; sed 's/^/    /' "$LOGS/$name.log" | tail -20; failed=1; fi
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
  cmp "$P/Packages/manifest.json" "$W/Packages/manifest.json"
  cmp "$P/ProjectSettings/Probe.asset" "$W/ProjectSettings/Probe.asset"
}
test_new_with_unity() { new_worktree_common; hub_has "$W"; }
test_new_without_unity() { no_unity new_worktree_common; }

test_new_base_ref() {
  make_fixture
  echo b > "$P/Assets/b.txt"; git -C "$P" add -A; git -C "$P" commit -qm second
  (cd "$P" && "$NEW" w2 --base HEAD~1)
  [ "$(git -C "$T/fake proj-w2" rev-parse HEAD)" = "$(git -C "$P" rev-parse HEAD~1)" ]
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
test_remove_seeded_only() { remove_seeded_common; refute hub_has "$W"; }
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
  git -C "$P" worktree lock "$W"
  (cd "$P" && "$REMOVE" r5)
  [ ! -e "$W" ]
  refute git -C "$P" rev-parse -q --verify refs/heads/worktree-r5
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

tests=${1:-$(declare -F | awk '$3 ~ /^test_/ {print $3}')}
for t in $tests; do run_test "$t"; done
exit $failed
