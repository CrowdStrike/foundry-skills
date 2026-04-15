#!/usr/bin/env bash
#
# foundry-cli-guard.sh
#
# PreToolUse hook that enforces --no-prompt on all Foundry CLI commands,
# blocks manual directory/file creation that should use the CLI, and
# reminds Claude to confirm resource names with the user before creating.
#
# Prevents common failures:
# 1. Running Foundry CLI commands without --no-prompt (causes Error: EOF)
# 2. Running ui extensions create without --sockets (interactive picker hangs)
# 3. Using mkdir/touch to create app structure (causes invalid manifests)
# 4. Creating resources without user confirmation of the name
# 5. Running deploy/release/list-deployments without FOUNDRY_UI_HEADLESS_MODE=true (TUI hangs)
#    Note: The SessionStart hook (set-foundry-env.sh) sets this env var automatically.
#    This guard is a fallback for edge cases where the env var isn't set.
#
# Receives JSON on stdin with hook_event_name and tool-specific fields.
# Outputs JSON with additionalContext (advisory nudge, not blocking).
#
# Environment variables:
#   FOUNDRY_SKIP_NAME_CONFIRM=1  Bypass name confirmation (for automated tests)
#
# Note: foundry-skill-router.sh also fires on `api-integrations create` for
# OpenAPI spec adaptation. Both hooks produce independent advisories.

set -euo pipefail

INPUT=$(cat)

HOOK_EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty')

if [ "$HOOK_EVENT" != "PreToolUse" ]; then
  exit 0
fi

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# Only validate Bash commands
if [ "$TOOL_NAME" != "Bash" ]; then
  exit 0
fi

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Check for Foundry CLI create commands that need --no-prompt
# Nearly all Foundry CLI commands support --no-prompt:
#   apps create/release/delete, functions create, collections create,
#   workflows create, api-integrations create,
#   ui pages create, ui extensions create, rtr-scripts create, profile create/delete
if echo "$COMMAND" | grep -qE 'foundry\s+apps\b.*\b(create|release|delete)\b|foundry\s+(functions|collections|workflows|api-integrations|rtr-scripts)\b.*\bcreate\b|foundry\s+profile\b.*\b(create|delete)\b|foundry\s+ui\s+(pages|extensions)\b.*\bcreate\b'; then
  # Check if --no-prompt is missing
  if ! echo "$COMMAND" | grep -qF -- '--no-prompt'; then
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        additionalContext: "The command is missing --no-prompt. Foundry CLI create/release commands run non-interactively in Claude Code and will hang with Error: EOF without it. Add --no-prompt before retrying. Example: foundry apps create --name \"app-name\" --no-prompt"
      }
    }'
    exit 0
  fi
fi

# Check for foundry ui extensions create without --sockets
# Omitting --sockets launches an interactive picker that hangs with Error: EOF.
if echo "$COMMAND" | grep -qE 'foundry\s+ui\s+extensions\b.*\bcreate\b'; then
  if ! echo "$COMMAND" | grep -qF -- '--sockets'; then
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        additionalContext: "The command is missing --sockets. Without it, the CLI launches an interactive socket picker that will hang with Error: EOF. Add --sockets with the target socket ID. Example: foundry ui extensions create --name \"my-ext\" --from-template React --sockets \"activity.detections.details\" --no-prompt"
      }
    }'
    exit 0
  fi
  # Validate --sockets value against known valid socket IDs
  SOCKET_VAL=$(echo "$COMMAND" | grep -oE -- '--sockets\s+"?[^"[:space:]]+"?' | sed 's/--sockets[[:space:]]*//' | tr -d '"')
  if [ -n "$SOCKET_VAL" ]; then
    VALID_SOCKETS="activity.detections.details automated-leads.leads.details hosts.host.panel xdr.cases.panel ngsiem.workbench.details workflows.executions.execution.details"
    IS_VALID=false
    for vs in $VALID_SOCKETS; do
      if [ "$SOCKET_VAL" = "$vs" ]; then
        IS_VALID=true
        break
      fi
    done
    if [ "$IS_VALID" = "false" ]; then
      jq -n --arg val "$SOCKET_VAL" '{
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          additionalContext: ("Invalid socket ID: \"" + $val + "\". Valid socket IDs are: activity.detections.details, automated-leads.leads.details, hosts.host.panel, xdr.cases.panel, ngsiem.workbench.details, workflows.executions.execution.details. Use the exact ID from this list.")
        }
      }'
      exit 0
    fi
  fi
fi

# Check for foundry apps deploy/release/list-deployments without FOUNDRY_UI_HEADLESS_MODE=true
# Normally the SessionStart hook sets this env var, but this guard catches edge cases.
# The enhanced UI (TUI progress monitor) requires a TTY and hangs in non-interactive environments.
# Skip advisory only when the env var is explicitly "true" — unset or "false" both need the prefix.
if echo "$COMMAND" | grep -qE 'foundry\s+apps\s+(deploy|release|list-deployments)\b'; then
  if [ "${FOUNDRY_UI_HEADLESS_MODE:-}" != "true" ] && ! echo "$COMMAND" | grep -qF 'FOUNDRY_UI_HEADLESS_MODE=true'; then
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        additionalContext: "The command is missing FOUNDRY_UI_HEADLESS_MODE=true. The enhanced UI (TUI progress monitor) requires a TTY and will hang in Claude Code. Prepend FOUNDRY_UI_HEADLESS_MODE=true to the command. Example: FOUNDRY_UI_HEADLESS_MODE=true foundry apps deploy --change-type Patch --change-log \"msg\""
      }
    }'
    exit 0
  fi
fi

# Check for Foundry resource-creation commands — remind Claude to confirm name with user.
# Only matches resource types (not profile create, which is local config).
# Handles: --name "val", --name 'val', --name val, --name=val, --name="val", --name='val'
# Skips when FOUNDRY_SKIP_NAME_CONFIRM=1 (automated testing).
if [ "${FOUNDRY_SKIP_NAME_CONFIRM:-}" != "1" ]; then
  RESOURCE_CREATE_RE='foundry\s+(apps|functions|collections|workflows|api-integrations|rtr-scripts)\b.*\bcreate\b|foundry\s+ui\s+(pages|extensions)\b.*\bcreate\b'
  if echo "$COMMAND" | grep -qE "$RESOURCE_CREATE_RE"; then
    # Extract resource name from --name flag (multiple syntax forms)
    RESOURCE_NAME=""
    if echo "$COMMAND" | grep -qE -- '--name[= ]'; then
      RESOURCE_NAME=$(echo "$COMMAND" | grep -oE -- '--name[= ]+("[^"]*"|'"'"'[^'"'"']*'"'"'|[^ ]+)' | head -1 | sed 's/^--name[= ]*//' | tr -d "\"'")
    fi
    # Only fire if we extracted a real name (not empty, not a flag)
    if [ -n "$RESOURCE_NAME" ] && ! echo "$RESOURCE_NAME" | grep -qE '^-'; then
      jq -n --arg name "$RESOURCE_NAME" '{
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          additionalContext: ("STOP — Confirm the resource name with the user before creating. You are about to create a Foundry resource named \"\($name)\". Use AskUserQuestion to confirm the name and description are what the user wants BEFORE running this command. If the user has already explicitly confirmed this exact name in this conversation, proceed.")
        }
      }'
      exit 0
    fi
  fi
fi

# Check for forbidden manual directory/file creation
FORBIDDEN_PATTERNS=(
  'mkdir.*\b(api-integrations|workflows|functions|collections|ui)\b'
  'touch.*manifest\.yml'
  'mkdir.*\bapp\b.*&&.*touch.*manifest'
  'echo.*>.*manifest\.yml'
  'cat.*>.*manifest\.yml'
)

for pattern in "${FORBIDDEN_PATTERNS[@]}"; do
  if echo "$COMMAND" | grep -qE "$pattern"; then
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        additionalContext: "Manual creation of Foundry app structure detected. Use the Foundry CLI instead — it generates manifest.yml with correct schema version, app ID, and auth context. Run: foundry apps create --name \"app-name\" --no-prompt"
      }
    }'
    exit 0
  fi
done

# Command is valid
exit 0
