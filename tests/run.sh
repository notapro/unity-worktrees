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

tests=${1:-$(declare -F | awk '$3 ~ /^test_/ {print $3}')}
for t in $tests; do run_test "$t"; done
exit $failed
