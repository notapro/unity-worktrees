#!/usr/bin/env bash
# usage: close-editor.sh <worktree> [--discard]
# Saves open scenes and assets in the Unity editor on <worktree>, then closes it.
# --discard skips the save and terminates the editor if it will not quit (modal dialog, play mode,
# no com.unity.pipeline), for a worktree about to be deleted or an editor nobody can save.
# Exit 0 if no editor is open or it closed; 1 (reason on stderr) if it is still open.
set -euo pipefail

wt=${1:?usage: close-editor.sh <worktree>}
here=$(dirname "$0")
discard=; [ "${2:-}" != --discard ] || discard=1

"$here/check-removable.sh" "$wt" 2>/dev/null && exit 0
command -v unity >/dev/null || { echo "Unity CLI not found, so the editor on $wt cannot be closed" >&2; exit 1; }

# `unity close` exits without saving, so never close after a failed save.
# Not SaveOpenScenes(): it opens a Save dialog for an untitled scene, which blocks the eval.
# A dirty untitled scene is saved under Assets/ instead; a clean one has nothing to keep.
[ -n "$discard" ] || unity command eval --project-path "$wt" --caller agent --skill unity-cli --result-only '
  for (int i = 0; i < UnityEngine.SceneManagement.SceneManager.sceneCount; i++) {
    var s = UnityEngine.SceneManagement.SceneManager.GetSceneAt(i);
    if (!s.isDirty) continue;
    var p = s.path != "" ? s.path : UnityEditor.AssetDatabase.GenerateUniqueAssetPath("Assets/Untitled.unity");
    if (!UnityEditor.SceneManagement.EditorSceneManager.SaveScene(s, p)) throw new System.Exception("could not save " + p);
  }
  UnityEditor.AssetDatabase.SaveAssets(); return 0;' \
  >/dev/null || { echo "saving the editor on $wt failed; left it open" >&2; exit 1; }
unity close "$wt" --non-interactive --no-banner ${discard:+--force} >/dev/null || true

for _ in $(seq 1 30); do
  "$here/check-removable.sh" "$wt" 2>/dev/null && exit 0
  sleep 3
done
echo "editor on $wt still open after 90 s" >&2
exit 1
