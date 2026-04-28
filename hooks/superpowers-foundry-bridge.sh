#!/usr/bin/env bash
#
# superpowers-foundry-bridge.sh
#
# PreToolUse hook on the Skill tool. Blocks superpowers:brainstorming and
# redirects to development-workflow which owns the Foundry dev flow.
# Advisory context is injected for other superpowers planning skills.
#
# Receives JSON on stdin with tool_input.skill (the skill being invoked).
# Outputs JSON with decision or additionalContext.

set -euo pipefail

INPUT=$(cat)

SKILL_NAME=$(echo "$INPUT" | jq -r '.tool_input.skill // empty')

# Redirect brainstorming to the Foundry development workflow skill.
# Uses additionalContext for a clean UX (no error messages).
# ~75% reliable — when it misses, the model still has Foundry skills in its
# available skills list. deny is 100% reliable but shows ugly duplicate errors.
case "$SKILL_NAME" in
  superpowers:brainstorming|brainstorming)
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        additionalContext: "STOP. Do NOT proceed with brainstorming. The Foundry plugin is installed and crowdstrike-falcon-foundry:development-workflow MUST be used instead. It handles requirements gathering, CLI scaffolding, and manifest coordination for Foundry apps. Cancel this brainstorming skill invocation and invoke crowdstrike-falcon-foundry:development-workflow immediately."
      }
    }'
    exit 0
    ;;
esac

# Advisory context for other superpowers planning skills
case "$SKILL_NAME" in
  superpowers:writing-plans|writing-plans|\
  superpowers:executing-plans|executing-plans|\
  superpowers:subagent-driven-development|subagent-driven-development)
    CONTEXT=$(cat <<'FOUNDRY_CONTEXT'
FOUNDRY PLUGIN INSTALLED: If this task involves Falcon Foundry, invoke crowdstrike-falcon-foundry:development-workflow BEFORE this skill. That skill owns Foundry app creation — it uses CLI commands (foundry apps create, foundry api-integrations create, etc.) that generate manifest.yml and wire up capability IDs correctly. Hand-writing manifest.yml or workflow YAML without the CLI causes deploy failures.
FOUNDRY_CONTEXT
    )
    jq -n \
      --arg ctx "$CONTEXT" \
      '{
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          additionalContext: $ctx
        }
      }'
    exit 0
    ;;
esac
