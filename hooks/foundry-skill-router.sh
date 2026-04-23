#!/usr/bin/env bash
#
# foundry-skill-router.sh
#
# Two-hook system for Foundry skill routing:
# 1. UserPromptSubmit: Detects specific Foundry keywords → writes marker file + injects context
# 2. PreToolUse (all tools): Reads marker → injects advisory reminder to use
#    the Foundry development workflow skill (non-blocking)
#
# The marker file bridges the two hooks since they run at different times.
# Cleaned up once the Skill tool is invoked.
#
# Receives JSON on stdin with hook_event_name and event-specific fields.
# Outputs JSON with additionalContext or permissionDecision.

set -euo pipefail

INPUT=$(cat)

HOOK_EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty')
MARKER="/tmp/.foundry-skill-router-active"

case "$HOOK_EVENT" in
  UserPromptSubmit)
    USER_PROMPT=$(echo "$INPUT" | jq -r '.prompt // .user_prompt // empty')
    PROMPT_LOWER=$(echo "$USER_PROMPT" | tr '[:upper:]' '[:lower:]')

    FOUNDRY_MATCH=false

    # Require an action verb + Foundry noun to detect real development intent.
    # "create a foundry app" triggers; "if we were in a foundry app" does not.
    VERBS="create|build|deploy|release|scaffold|add|update|fix|debug|configure"
    NOUNS="foundry app|foundry function|foundry collection|foundry workflow|foundry ui|foundry page|foundry api|falcon foundry|falcon app|crowdstrike app|foundry extension"

    if echo "$PROMPT_LOWER" | grep -qE "\b(${VERBS})\b.*(${NOUNS})"; then
      FOUNDRY_MATCH=true
    elif echo "$PROMPT_LOWER" | grep -qE "(${NOUNS}).*\b(${VERBS})\b"; then
      # Also catch "foundry app ... deploy" word order
      FOUNDRY_MATCH=true
    fi

    # Explicit CLI commands always trigger
    for cmd in "foundry apps create" "foundry apps deploy" "foundry apps release" \
               "foundry apps run" "foundry login"; do
      if echo "$PROMPT_LOWER" | grep -qF "$cmd"; then
        FOUNDRY_MATCH=true
        break
      fi
    done

    # Explicit skill requests always trigger
    if echo "$PROMPT_LOWER" | grep -qE "(use|invoke|run) foundry (skill|plugin)"; then
      FOUNDRY_MATCH=true
    fi

    if [ "$FOUNDRY_MATCH" = true ]; then
      # Write marker so PreToolUse hook knows to inject advisory context
      echo "$$" > "$MARKER"

      jq -n '{
        hookSpecificOutput: {
          hookEventName: "UserPromptSubmit",
          additionalContext: "FOUNDRY PLUGIN DETECTED: This prompt involves Falcon Foundry development. Do NOT enter plan mode. IMMEDIATELY invoke falcon-foundry:development-workflow using the Skill tool. That skill handles requirements gathering, clarifying questions, CLI scaffolding, and sub-skill delegation."
        }
      }'
      exit 0
    fi
    ;;

  PreToolUse)
    TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

    # Auto-adapt OpenAPI spec before allowing api-integrations create
    if [ "$TOOL_NAME" = "Bash" ]; then
      TOOL_INPUT=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
      if echo "$TOOL_INPUT" | grep -q 'foundry api-integrations create'; then
        # Extract the spec file path from --spec flag
        SPEC_FILE=$(echo "$TOOL_INPUT" | grep -oE '\-\-spec\s+[^ ]+' | awk '{print $2}')
        if [ -n "$SPEC_FILE" ] && [ -f "$SPEC_FILE" ]; then
          # Find the adapt script relative to the plugin root
          PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
          ADAPT_SCRIPT="$PLUGIN_ROOT/scripts/adapt-spec-for-foundry.py"

          # Run the adapt script automatically to fix known issues
          if [ -f "$ADAPT_SCRIPT" ]; then
            ADAPT_OUTPUT=$(python3 "$ADAPT_SCRIPT" "$SPEC_FILE" 2>&1) || true
            if [ -n "$ADAPT_OUTPUT" ]; then
              # Check for validation-only warnings (block, don't auto-fix)
              if echo "$ADAPT_OUTPUT" | grep -q 'expose_to_workflow.*directly under'; then
                jq -n --arg output "$ADAPT_OUTPUT" '{
                  hookSpecificOutput: {
                    hookEventName: "PreToolUse",
                    decision: "block",
                    reason: ("BLOCKED: spec has structural issues that require manual fixes:\n" + $output + "\n\nFix x-cs-operation-config: nest expose_to_workflow under a workflow: key:\n\nx-cs-operation-config:\n  workflow:\n    name: operationId\n    description: What this operation does\n    expose_to_workflow: true\n    system: false")
                  }
                }'
                exit 0
              fi
              # Check if it made auto-fixes
              if echo "$ADAPT_OUTPUT" | grep -qE '(Stripped protocol|Removed default|Added bearerFormat|Removed .*oauth2|Removed duplicate param|Removed security)'; then
                jq -n --arg output "$ADAPT_OUTPUT" '{
                  hookSpecificOutput: {
                    hookEventName: "PreToolUse",
                    additionalContext: ("adapt-spec-for-foundry.py automatically fixed the spec before import:\n" + $output + "\nProceeding with the corrected spec.")
                  }
                }'
                exit 0
              fi
            fi
          else
            jq -n --arg script "$ADAPT_SCRIPT" '{
              hookSpecificOutput: {
                hookEventName: "PreToolUse",
                decision: "block",
                reason: ("BLOCKED: adapt-spec-for-foundry.py not found at " + $script + ". This script is required to validate OpenAPI specs before import.")
              }
            }'
            exit 0
          fi
        fi
      fi
    fi

    # Detect hand-written OpenAPI specs — nudge to download the vendor's real spec
    if [ "$TOOL_NAME" = "Write" ]; then
      FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
      CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty')
      if echo "$FILE_PATH" | grep -qiE '\.(yaml|yml|json)$'; then
        if echo "$CONTENT" | head -20 | grep -qiE '^openapi:|"openapi"'; then
          jq -n '{
            hookSpecificOutput: {
              hookEventName: "PreToolUse",
              additionalContext: "WARNING: You are writing an OpenAPI spec from scratch. Most vendors publish official OpenAPI specs on GitHub or their developer portal. Download the real spec with gh or curl instead of hand-writing one — vendor specs include all endpoints, correct schemas, and proper auth configuration. A hand-written spec will be incomplete and may have wrong schemas. Search GitHub for the vendor name + openapi/swagger spec."
            }
          }'
          exit 0
        fi
      fi
    fi

    # Detect manifest.yml entrypoint/path edits — these values are CLI-generated and must not be changed
    if [ "$TOOL_NAME" = "Edit" ]; then
      FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
      OLD_STRING=$(echo "$INPUT" | jq -r '.tool_input.old_string // empty')
      NEW_STRING=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty')
      if echo "$FILE_PATH" | grep -qF 'manifest.yml'; then
        if echo "$OLD_STRING$NEW_STRING" | grep -qE '\bentrypoint:|\bpath:.*ui/(pages|extensions)/'; then
          jq -n '{
            hookSpecificOutput: {
              hookEventName: "PreToolUse",
              additionalContext: "STOP: Do NOT edit path or entrypoint in manifest.yml. The CLI sets these correctly during scaffolding. The full path format (e.g., ui/extensions/my-ext/src/dist/index.html) is correct — it is NOT a doubled path. Shortening entrypoint to src/dist/index.html will break the app. If you have a path-related deploy error, fix vite.config.js (root and base) instead."
            }
          }'
          exit 0
        fi
      fi
    fi

    # Only intercept when a Foundry prompt was detected
    if [ -f "$MARKER" ]; then
      # Allow the Skill tool through — that's the goal. Clean up marker.
      if [ "$TOOL_NAME" = "Skill" ]; then
        rm -f "$MARKER"
        exit 0
      fi

      # Advisory nudge — don't block tools, just remind the model
      jq -n '{
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          additionalContext: "Foundry plugin reminder: Consider invoking falcon-foundry:development-workflow skill for Foundry development tasks. It handles CLI scaffolding, manifest coordination, and sub-skill delegation."
        }
      }'
      exit 0
    fi
    ;;
esac
