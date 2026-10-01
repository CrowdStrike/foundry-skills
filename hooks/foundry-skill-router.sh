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
# It is scoped to the session, reset on every prompt, and removed after the
# first reminder (or when the Skill tool is invoked), so one detected prompt
# produces one reminder instead of one per tool call.
#
# Receives JSON on stdin with hook_event_name and event-specific fields.
# Outputs JSON with additionalContext or permissionDecision (deny blocks the call).

set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/host-output.sh"

INPUT=$(cat)

HOOK_EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty')
# Cursor names these beforeSubmitPrompt and preToolUse, and sends conversation_id.
case "$HOOK_EVENT" in
  beforeSubmitPrompt) HOOK_EVENT=UserPromptSubmit ;;
  preToolUse) HOOK_EVENT=PreToolUse ;;
esac
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // .conversation_id // empty')
MARKER="/tmp/.foundry-skill-router-active${SESSION_ID:+-$SESSION_ID}"

# Best-effort cross-host check. Claude Code records installed plugins in JSON;
# Codex records enabled marketplace plugins in config.toml; Antigravity in
# config.json; Cursor keeps a marketplace install in its plugin cache.
codex_plugin_enabled() {
  local plugin="$1"
  [ -f "$HOME/.codex/config.toml" ] || return 1
  # Only the plugin's own table counts, not a nested one such as
  # [plugins."<id>@<marketplace>".mcp_servers.x].
  awk -v prefix="[plugins.\"$plugin@" '
    /^\[/ { in_plugin = (index($0, prefix) == 1 && substr($0, length(prefix) + 1) ~ /^[^".]*"\][[:space:]]*(#.*)?$/); next }
    in_plugin && /^enabled[[:space:]]*=[[:space:]]*true[[:space:]]*(#.*)?$/ { found = 1 }
    END { exit found ? 0 : 1 }
  ' "$HOME/.codex/config.toml" 2>/dev/null
}

plugin_is_enabled() {
  local plugin="$1"
  # Cursor sets CURSOR_PLUGIN_ROOT. Codex sends turn_id. Check only that host
  # so a Claude registry on the same machine cannot mark a Codex-disabled
  # sibling as installed.
  if [ -n "${CURSOR_PLUGIN_ROOT:-}" ]; then
    [ -d "$HOME/.cursor/plugins/cache/cursor-public/$plugin" ]
    return
  fi
  if printf '%s' "$INPUT" | jq -e 'has("turn_id")' >/dev/null 2>&1; then
    codex_plugin_enabled "$plugin"
    return
  fi
  if [ -f "$HOME/.claude/plugins/installed_plugins.json" ] &&
     grep -q "$plugin" "$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null; then
    return 0
  fi
  if codex_plugin_enabled "$plugin"; then
    return 0
  fi
  if [ -d "$HOME/.gemini/config/plugins/$plugin" ]; then
    if [ ! -f "$HOME/.gemini/config/config.json" ] || ! python3 -c '
import json, os, sys
try:
    c = json.load(open(os.path.expanduser("~/.gemini/config/config.json")))
    if c.get("plugins", {}).get(sys.argv[1], {}).get("enabled") is False:
        sys.exit(1)
except Exception:
    pass
sys.exit(0)
' "$plugin" 2>/dev/null; then
      return 0
    fi
  fi
  if [ -d "$HOME/.cursor/plugins/cache/cursor-public/$plugin" ]; then
    return 0
  fi
  return 1
}

case "$HOOK_EVENT" in
  UserPromptSubmit)
    # Each prompt is classified on its own; never carry a detection forward.
    rm -f "$MARKER"
    USER_PROMPT=$(echo "$INPUT" | jq -r '.prompt // .user_prompt // empty')
    PROMPT_LOWER=$(echo "$USER_PROMPT" | tr '[:upper:]' '[:lower:]')

    FOUNDRY_MATCH=false

    # Require an action verb + Foundry noun to detect real development intent.
    # "create a foundry app" triggers; "if we were in a foundry app" does not.
    # The verb and noun must be at most five words apart, so a prompt that
    # fixes one thing and mentions Falcon Foundry later in the sentence doesn't match,
    # while "connect the OpenRouter API to a Foundry app" still does.
    VERBS="create|build|make|need|want|write|connect|deploy|release|scaffold|add|update|fix|debug|configure"
    NOUNS="foundry app|foundry function|foundry collection|foundry workflow|foundry ui|foundry page|foundry api|falcon foundry|falcon app|crowdstrike app|foundry extension|foundry agent|foundry knowledge base"
    GAP="([[:space:]]+[^[:space:]]+){0,5}[[:space:]]+"

    if echo "$PROMPT_LOWER" | grep -qE "\b(${VERBS})\b${GAP}(${NOUNS})"; then
      FOUNDRY_MATCH=true
    elif echo "$PROMPT_LOWER" | grep -qE "(${NOUNS})${GAP}(${VERBS})\b"; then
      # Also catch "foundry app ... deploy" word order
      FOUNDRY_MATCH=true
    fi

    # A verb anywhere in the prompt is enough to ask the Fusion classifier,
    # which only redirects standalone Fusion work: "Create a Falcon Fusion
    # workflow, no Foundry app" puts the verb far from the noun.
    LOOSE_MATCH=false
    if echo "$PROMPT_LOWER" | grep -qE "\b(${VERBS})\b.*(${NOUNS})|(${NOUNS}).*\b(${VERBS})\b"; then
      LOOSE_MATCH=true
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

    if [ "$FOUNDRY_MATCH" = true ] || [ "$LOOSE_MATCH" = true ]; then
      # Standalone Fusion workflow? Advise the sibling plugin instead of
      # steering into app scaffolding. Without this the classifier is never
      # consulted at runtime and the agent tends to quietly author the workflow
      # itself, never telling the user a better-suited plugin exists.
      REDIRECT_SCRIPT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/skills/development-workflow/scripts/detect_fusion_redirect.py"
      if [ -f "$REDIRECT_SCRIPT" ]; then
        VERDICT=$(printf '%s' "$USER_PROMPT" | python3 "$REDIRECT_SCRIPT" 2>/dev/null || true)
        if echo "$VERDICT" | grep -q '"redirect": true'; then
          # If the sibling plugin is already enabled, say "use it" rather than
          # "install it". Mirrors fusion-skills' fusion-foundry-bridge.sh.
          FUSION_HINT="Advise the crowdstrike-falcon-fusion plugin — install it from the plugin browser (/plugins in Codex; /plugin install crowdstrike-falcon-fusion in Claude Code; /add-plugin crowdstrike-falcon-fusion in Cursor; agy plugin install https://github.com/CrowdStrike/fusion-skills in Antigravity), or see https://github.com/CrowdStrike/fusion-skills."
          if plugin_is_enabled "crowdstrike-falcon-fusion"; then
            FUSION_HINT="The crowdstrike-falcon-fusion plugin is already installed — hand off to its workflows skill."
          fi
          emit_advisory "UserPromptSubmit" "STANDALONE FUSION WORKFLOW DETECTED: this request looks like a trigger plus actions that already exist in the CID — no UI, function, collection, or API integration to build. It does NOT need a Foundry app. ${FUSION_HINT} Do NOT scaffold a Foundry app. Naming the plugin is required output — declining to scaffold is only half the redirect, and hand-writing the workflow YAML yourself defeats the purpose since that plugin discovers real action IDs, validates against the platform schema, and imports to the CID. This detection is advisory: if the request genuinely needs an app capability built, proceed with crowdstrike-falcon-foundry:development-workflow instead."
          exit 0
        fi
      fi

      [ "$FOUNDRY_MATCH" = true ] || exit 0

      # Write marker so PreToolUse hook knows to inject advisory context. Only
      # on this path: after a Fusion redirect, a Foundry nudge would contradict it.
      echo "$$" > "$MARKER"

      emit_advisory "UserPromptSubmit" "FOUNDRY PLUGIN DETECTED: This prompt involves Falcon Foundry development. Do NOT enter plan mode. Immediately load and follow the crowdstrike-falcon-foundry:development-workflow skill. That skill handles requirements gathering, clarifying questions, CLI scaffolding, and sub-skill delegation."
      exit 0
    fi
    ;;

  PreToolUse)
    TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

    # Auto-adapt OpenAPI spec before allowing api-integrations create
    # Cursor's shell tool is Shell. Claude's is Bash.
    if [ "$TOOL_NAME" = "Bash" ] || [ "$TOOL_NAME" = "Shell" ]; then
      TOOL_INPUT=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
      if echo "$TOOL_INPUT" | grep -q 'foundry api-integrations create'; then
        # Extract the spec file path from --spec flag
        SPEC_FILE=$(echo "$TOOL_INPUT" | grep -oE '\-\-spec\s+[^ ]+' | awk '{print $2}')
        if [ -n "$SPEC_FILE" ] && [ -f "$SPEC_FILE" ]; then
          # Find the adapt script relative to the plugin root
          PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
          ADAPT_SCRIPT="$PLUGIN_ROOT/skills/api-integrations/scripts/adapt_spec_for_foundry.py"

          # Run the adapt script automatically to fix known issues
          if [ -f "$ADAPT_SCRIPT" ]; then
            if ! ADAPT_OUTPUT=$(python3 "$ADAPT_SCRIPT" "$SPEC_FILE" 2>&1); then
              emit_deny "PreToolUse" "BLOCKED: OpenAPI adaptation failed:
${ADAPT_OUTPUT}

Install the required Python packages, then retry:
python3 -m pip install -r ${PLUGIN_ROOT}/requirements.txt"
              exit 0
            fi
            if [ -n "$ADAPT_OUTPUT" ]; then
              # Check for validation-only warnings (block, don't auto-fix)
              if echo "$ADAPT_OUTPUT" | grep -qE 'expose_to_(workflow|agent).*directly under'; then
                emit_deny "PreToolUse" "BLOCKED: spec has structural issues that require manual fixes:
${ADAPT_OUTPUT}

Both exposure flags must be nested under their own key:

x-cs-operation-config:
  workflow:
    name: operationId
    description: What this operation does
    expose_to_workflow: true
    system: false
  agent_tools:
    name: operation_name
    description: What this operation does
    expose_to_agent: true"
                exit 0
              fi
              # Check if it made auto-fixes
              if echo "$ADAPT_OUTPUT" | grep -qE '(Stripped protocol|Removed default|Added bearerFormat|Removed .*oauth2|Removed duplicate param|Removed security)'; then
                emit_advisory "PreToolUse" "adapt_spec_for_foundry.py automatically fixed the spec before import:
${ADAPT_OUTPUT}
Proceeding with the corrected spec."
                exit 0
              fi
            fi
          else
            emit_deny "PreToolUse" "BLOCKED: adapt_spec_for_foundry.py not found at ${ADAPT_SCRIPT}. This script is required to validate OpenAPI specs before import."
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
          emit_advisory "PreToolUse" "WARNING: You are writing an OpenAPI spec from scratch. Most vendors publish official OpenAPI specs on GitHub or their developer portal. Download the real spec with gh or curl instead of hand-writing one — vendor specs include all endpoints, correct schemas, and proper auth configuration. A hand-written spec will be incomplete and may have wrong schemas. Search GitHub for the vendor name + openapi/swagger spec."
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
          emit_advisory "PreToolUse" "STOP: Do NOT edit path or entrypoint in manifest.yml. The CLI sets these correctly during scaffolding. The full path format (e.g., ui/extensions/my-ext/src/dist/index.html) is correct — it is NOT a doubled path. Shortening entrypoint to src/dist/index.html will break the app. If you have a path-related deploy error, fix vite.config.js (root and base) instead."
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

      # Advisory nudge, once per detected prompt — don't block tools
      rm -f "$MARKER"
      emit_advisory "PreToolUse" "Foundry plugin reminder: Consider invoking crowdstrike-falcon-foundry:development-workflow skill for Foundry development tasks. It handles CLI scaffolding, manifest coordination, and sub-skill delegation."
      exit 0
    fi
    ;;
esac
