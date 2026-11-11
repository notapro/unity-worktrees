#!/usr/bin/env bash
# usage: close-editor.sh <worktree>
# Saves open scenes and assets in the Unity editor on <worktree>, then closes it.
# Exit 0 if no editor is open or it closed; 1 (reason on stderr) if it is still open.
set -euo pipefail

wt=${1:?usage: close-editor.sh <worktree>}
here=$(dirname "$0")

"$here/check-removable.sh" "$wt" 2>/dev/null && exit 0
command -v unity >/dev/null || { echo "Unity CLI not found, so the editor on $wt cannot be closed" >&2; exit 1; }

# `unity close` exits without saving, so never close after a failed save.
unity command eval --project-path "$wt" --caller agent --skill unity-cli --result-only \
  'UnityEditor.SceneManagement.EditorSceneManager.SaveOpenScenes(); UnityEditor.AssetDatabase.SaveAssets(); return 0;' \
  >/dev/null || { echo "saving the editor on $wt failed; left it open" >&2; exit 1; }
unity close "$wt" --non-interactive --no-banner >/dev/null || true

for _ in $(seq 1 30); do
  "$here/check-removable.sh" "$wt" 2>/dev/null && exit 0
  sleep 3
done
echo "editor on $wt still open after 90 s" >&2
exit 1
