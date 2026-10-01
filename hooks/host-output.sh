# shellcheck shell=bash
# host-output.sh — JSON shape the current host actually injects.
#
# Sourced by the hook scripts. Cursor sets CURSOR_PLUGIN_ROOT and injects
# top-level additional_context; it does not inject Claude's nested
# hookSpecificOutput.additionalContext. Claude Code also reads additional_context,
# so emitting both duplicates the advisory there. Deny decisions use Cursor's
# permission/agent_message fields on Cursor and Claude's permissionDecision
# everywhere else. Codex and Copilot keep the Claude shape.

cursor_hooks() {
  [ -n "${CURSOR_PLUGIN_ROOT:-}" ]
}

emit_advisory() {
  local event="$1"
  local text="$2"
  if cursor_hooks; then
    jq -n --arg text "$text" '{additional_context: $text}'
  else
    jq -n --arg event "$event" --arg text "$text" '{
      hookSpecificOutput: {
        hookEventName: $event,
        additionalContext: $text
      }
    }'
  fi
}

emit_deny() {
  local event="$1"
  local reason="$2"
  if cursor_hooks; then
    jq -n --arg reason "$reason" '{
      permission: "deny",
      agent_message: $reason,
      user_message: $reason
    }'
  else
    jq -n --arg event "$event" --arg reason "$reason" '{
      hookSpecificOutput: {
        hookEventName: $event,
        permissionDecision: "deny",
        permissionDecisionReason: $reason
      }
    }'
  fi
}
