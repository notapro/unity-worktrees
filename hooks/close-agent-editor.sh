#!/usr/bin/env bash
# Saves and closes a Unity editor on a Claude-created worktree (<main>/.claude/worktrees/*)
# when the agent's work there ends: SubagentStop for the subagent's own isolated worktree,
# PreToolUse ExitWorktree when it removes the worktree, and SessionEnd. Never touches the main
# checkout or worktrees made outside Claude. Only a failed ExitWorktree close blocks (exit 2);
# subagent and session ends cannot be held, so an editor that will not save is force-quit there.
exec >&2
# \x1f, not tab: read collapses runs of whitespace separators, dropping empty fields.
IFS=$'\x1f' read -r event cwd agent action reason < <(python3 -c '
import json, sys
d = json.load(sys.stdin)
print("\x1f".join([d.get("hook_event_name", ""), d.get("cwd", ""), d.get("agent_id", ""),
                 (d.get("tool_input") or {}).get("action", ""), d.get("reason", "")]))')
close="${CLAUDE_PLUGIN_ROOT:?}/skills/remove-unity-worktree/close-editor.sh"

root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || exit 0
main=$(dirname "$(git -C "$root" rev-parse --path-format=absolute --git-common-dir)")
case $root in "$main/.claude/worktrees/"*) ;; *) exit 0;; esac

case $event in
  SubagentStop)
    [ "$(basename "$root")" = "agent-$agent" ] || exit 0
    "$close" "$root" || "$close" "$root" --discard || true;;
  PreToolUse)
    [ "$action" = remove ] || exit 0
    if ! reason=$("$close" "$root" 2>&1); then
      echo "Could not close the Unity editor on $root: ${reason##*$'\n'}. Save and close it, then retry."
      exit 2
    fi;;
  SessionEnd)
    # /clear also ends a session, but work goes on in the same worktree.
    [ "$reason" != clear ] || exit 0
    # Claude cancels SessionEnd hooks within seconds; let the close outlive this hook.
    nohup bash -c '"$0" "$1" || "$0" "$1" --discard' "$close" "$root" >/dev/null 2>&1 &;;
esac
exit 0
