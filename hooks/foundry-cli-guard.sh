#!/usr/bin/env bash
#
# foundry-cli-guard.sh
#
# PreToolUse hook that flags Foundry CLI commands missing --no-prompt,
# flags manual directory/file creation that should use the CLI, and
# reminds Claude to confirm resource names with the user before creating.
#
# Prevents common failures:
# 1. Running Foundry CLI commands without --no-prompt (causes Error: EOF)
# 2. Running foundry apps deploy without --change-type (causes 500 error)
# 3. Running ui extensions create without --sockets (interactive picker hangs)
# 4. Using mkdir/touch to create app structure (causes invalid manifests)
# 5. Creating resources without user confirmation of the name
# 6. Deleting an AI agent or knowledge base without user confirmation
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

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/host-output.sh"

INPUT=$(cat)

HOOK_EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty')
case "$HOOK_EVENT" in
  preToolUse) HOOK_EVENT=PreToolUse ;;
esac

if [ "$HOOK_EVENT" != "PreToolUse" ]; then
  exit 0
fi

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# Claude's shell tool is Bash. Cursor's is Shell.
if [ "$TOOL_NAME" != "Bash" ] && [ "$TOOL_NAME" != "Shell" ]; then
  exit 0
fi

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# The parts of COMMAND that actually invoke the Foundry CLI: heredoc bodies and
# quoted strings are blanked, the rest is split on ; & | ( ) ` and newlines, and
# only pieces whose first word is `foundry` are kept. Subcommand checks match
# against this, so `git commit -m "... foundry apps create ..."` doesn't trigger them.
FOUNDRY_CMDS=$(printf '%s' "$COMMAND" | jq -Rrs "$(cat <<'JQ'
gsub("<<-?[[:space:]]*[\"']?(?<w>[A-Za-z_][A-Za-z0-9_]*)[\"']?[^\n]*\n(?:.*?\n)??[[:space:]]*\\k<w>(?=[[:space:]]|\\)|$)"; ""; "s")
| gsub("\"(?:\\\\.|[^\"\\\\])*\""; "\"\"")
| gsub("'[^']*'"; "''")
| [splits("[\n;&|()\\x60]+")
   | sub("^[[:space:]]*(?:[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*"; "")
   | select(test("^(?:[^[:space:]]*/)?foundry(?:[[:space:]]|$)"))]
| join("\n")
JQ
)")

# Set by reminders that must not short-circuit a later, more important advisory.
# Whichever advisory fires next prepends it; if none does, it is flushed at the end.
PENDING_REMINDER=""

# Check for Foundry CLI commands that need --no-prompt
# Nearly all Foundry CLI commands support --no-prompt:
#   apps create/validate/release/delete, functions create, collections create,
#   workflows create, api-integrations create, agents create/delete,
#   knowledge-bases create/delete (alias: kb), ui pages create, ui extensions create,
#   rtr-scripts create, profile create/delete
#   functions exec (incl. exec list / exec status), functions logs, functions test
if echo "$FOUNDRY_CMDS" | grep -qE 'foundry\s+apps\b.*\b(create|validate|release|delete)\b|foundry\s+(functions|collections|workflows|api-integrations|rtr-scripts)\b.*\bcreate\b|foundry\s+(agents|knowledge-bases|kb)\b.*\b(create|delete)\b|foundry\s+functions\s+(exec|logs|test)\b|foundry\s+profile\b.*\b(create|delete)\b|foundry\s+ui\s+(pages|extensions)\b.*\bcreate\b'; then
  # Check if --no-prompt is missing
  if ! echo "$COMMAND" | grep -qF -- '--no-prompt'; then
    emit_advisory "PreToolUse" "The command is missing --no-prompt. Foundry CLI commands (create/validate/release/delete, functions exec/logs/test) run non-interactively in coding assistants and will hang with Error: EOF without it. Add --no-prompt before retrying. Example: foundry apps create --name \"app-name\" --no-prompt"
    exit 0
  fi
fi

# Check for foundry apps deploy without --change-type
# Omitting --change-type causes a 500 error (server-side panic) because the
# Foundry API requires a change_type field in deploy requests.
if echo "$FOUNDRY_CMDS" | grep -qE 'foundry\s+apps\s+deploy\b'; then
  if ! echo "$COMMAND" | grep -qF -- '--change-type'; then
    emit_advisory "PreToolUse" "The command is missing --change-type. Foundry apps deploy requires --change-type and --change-log to avoid a 500 error. Add both flags before retrying. Example: foundry apps deploy --change-type Patch --change-log \"description of changes\" --no-prompt"
    exit 0
  fi
  if ! echo "$COMMAND" | grep -qF -- '--change-log'; then
    emit_advisory "PreToolUse" "The command is missing --change-log. Foundry apps deploy requires --change-type and --change-log. Add both flags before retrying. Example: foundry apps deploy --change-type Patch --change-log \"description of changes\" --no-prompt"
    exit 0
  fi
fi

# Check for foundry knowledge-bases create without --files
# A knowledge base must ship at least one file. With --no-prompt the CLI rejects
# the command outright: "flag --files is required when --no-prompt flag is used".
if echo "$FOUNDRY_CMDS" | grep -qE 'foundry\s+(knowledge-bases|kb)\b.*\bcreate\b'; then
  if ! echo "$COMMAND" | grep -qF -- '--files'; then
    emit_advisory "PreToolUse" "The command is missing --files. A knowledge base must contain at least one file, and the CLI rejects knowledge-bases create with --no-prompt and no --files. Pass local paths or HTTP(S) URLs, comma-separated. Example: foundry knowledge-bases create --name \"Runbook Docs\" --description \"desc\" --files ./runbook.md,./iocs.csv --no-prompt"
    exit 0
  fi
fi

# Check for foundry agents create referencing knowledge bases — order matters.
# The agent create command validates KB references against the manifest and fails
# the whole command if the KB does not exist yet.
if echo "$FOUNDRY_CMDS" | grep -qE 'foundry\s+agents\b.*\bcreate\b'; then
  # --expose-agent-as-tool requires --input-schema: a calling agent needs the
  # callee's signature. Rejected before any files are written.
  if echo "$COMMAND" | grep -qF -- '--expose-agent-as-tool'; then
    if ! echo "$COMMAND" | grep -qF -- '--input-schema'; then
      emit_advisory "PreToolUse" "--expose-agent-as-tool requires --input-schema. An agent callable by other agents must declare its input signature, and the CLI rejects the command outright: --input-schema is required when --expose-agent-as-tool is set. Add --input-format json --input-schema /path/to/input_schema.json, or drop the exposure flag."
      exit 0
    fi
  fi
  # A reminder, not a rejection — the command still runs. Advisories are read as
  # a single JSON object, so printing this one here and letting the block below
  # print too yields two objects and a parse error, while returning early
  # swallows the name-confirmation STOP. Park it and let that block carry it.
  if echo "$COMMAND" | grep -qF -- '--knowledge-bases'; then
    PENDING_REMINDER="Build order reminder: every name passed to --knowledge-bases must ALREADY exist in manifest.yml under ai.knowledge_bases, and must be the knowledge base name (not its id or path). Otherwise this fails with: agent \"X\" references knowledge base \"K\" which is not defined in the manifest. Run foundry knowledge-bases create first. Also note --system-prompt falls back to treating its value as inline prompt text when the path cannot be read, so verify agents/<path>/system_prompt.txt after creating."
  fi
  # The deploy backend reads only input_schema.json / output_schema.json from the
  # agent directory. CLIs newer than 2.1.1 rename the file on create; 2.1.1 and
  # earlier keep the source basename, which validates and then fails deploy.
  # Same advice for both.
  # Read flags from the agents create segment only, so a chained
  # `foundry functions create --input-schema ...` isn't mistaken for the agent's.
  AGENT_CMD=$(echo "$COMMAND" | awk '{ gsub(/&&|\|\||;|\|/, "\n"); print }' | grep -E 'foundry\s+agents\b.*\bcreate\b' | head -1 || true)
  for SCHEMA_FLAG in input output; do
    SCHEMA_VAL=$(echo "$AGENT_CMD" | grep -oE -- "--${SCHEMA_FLAG}-schema[= ]+(\"[^\"]*\"|'[^']*'|[^ ]+)" | head -1 | sed -E "s/^--${SCHEMA_FLAG}-schema[= ]+//" | tr -d "\"'" || true)
    # Empty or another flag means the value was left off; the CLI reports that itself.
    case "$SCHEMA_VAL" in ''|-*) continue ;; esac
    WANT="${SCHEMA_FLAG}_schema.json"
    case "$SCHEMA_VAL" in
      '{'*|'['*) GOT="an inline schema" ;;
      */) GOT="a directory" ;;
      *)
        SCHEMA_FILE="${SCHEMA_VAL%%[?#]*}"
        SCHEMA_FILE="${SCHEMA_FILE##*/}"
        [ "$SCHEMA_FILE" = "$WANT" ] && continue
        GOT="$SCHEMA_FILE"
        ;;
    esac
    SCHEMA_NOTE="--${SCHEMA_FLAG}-schema points at ${GOT}, but the deploy backend only reads agents/<path>/${WANT}. Save the schema as a local file named ${WANT} (download it first if it is a URL) and pass that path, so the agent deploys with any CLI version."
    PENDING_REMINDER="${PENDING_REMINDER:+$PENDING_REMINDER }$SCHEMA_NOTE"
  done
fi

# Check for foundry ui extensions create without --sockets
# Omitting --sockets launches an interactive picker that hangs with Error: EOF.
if echo "$FOUNDRY_CMDS" | grep -qE 'foundry\s+ui\s+extensions\b.*\bcreate\b'; then
  if ! echo "$COMMAND" | grep -qF -- '--sockets'; then
    emit_advisory "PreToolUse" "The command is missing --sockets. Without it, the CLI launches an interactive socket picker that will hang with Error: EOF. Run \`foundry ui extensions list-sockets\` to see available sockets. Example: foundry ui extensions create --name \"my-ext\" --from-template React --sockets \"activity.detections.details\" --no-prompt"
    exit 0
  fi
  # Validate --sockets value against known valid socket IDs
  SOCKET_VAL=$(echo "$COMMAND" | grep -oE -- '--sockets\s+"?[^"[:space:]]+"?' | sed 's/--sockets[[:space:]]*//' | tr -d '"')
  if [ -n "$SOCKET_VAL" ]; then
    VALID_SOCKETS="activity.detections.details identity.detections.details automated-leads.leads.details hosts.host.panel xdr.cases.panel ngsiem.workbench.details workflows.executions.execution.details"
    IS_VALID=false
    for vs in $VALID_SOCKETS; do
      if [ "$SOCKET_VAL" = "$vs" ]; then
        IS_VALID=true
        break
      fi
    done
    if [ "$IS_VALID" = "false" ]; then
      emit_advisory "PreToolUse" "Invalid socket ID: \"${SOCKET_VAL}\". Run \`foundry ui extensions list-sockets\` for available sockets. Known IDs: activity.detections.details, identity.detections.details, automated-leads.leads.details, hosts.host.panel, xdr.cases.panel, ngsiem.workbench.details, workflows.executions.execution.details."
      exit 0
    fi
  fi
fi

# Check for foundry workflows actions/triggers view without --no-prompt
# The CLI currently ignores --no-prompt for these commands (FOUNDRY-3049) and
# always launches an interactive Select() prompt. Adding --no-prompt is still
# correct (for when the bug is fixed), but the real workaround is
# the workflow skill's bundled action_search.py, which queries the API directly.
if echo "$FOUNDRY_CMDS" | grep -qE 'foundry\s+workflows\s+(actions|triggers)\s+view\b'; then
  if ! echo "$COMMAND" | grep -qF -- '--no-prompt'; then
    emit_advisory "PreToolUse" "The command is missing --no-prompt. The CLI currently ignores this flag for actions/triggers view (known bug), but add it anyway. If the command fails or hangs, use the bundled action_search.py from workflows-development instead — it queries the API directly and works in headless environments."
    exit 0
  fi
fi

# Check for Foundry resource commands — remind Claude to confirm the target with the user.
# Covers creation (wrong name means a wasted deploy) and AI artifact deletion (removes
# the manifest entry and the directory, with no undo and no `edit` to fall back on).
# Only matches resource types (not profile create, which is local config).
# Handles: --name "val", --name 'val', --name val, --name=val, --name="val", --name='val'
# Skips when FOUNDRY_SKIP_NAME_CONFIRM=1 (automated testing).
if [ "${FOUNDRY_SKIP_NAME_CONFIRM:-}" != "1" ]; then
  RESOURCE_CREATE_RE='foundry\s+(apps|functions|collections|workflows|api-integrations|rtr-scripts|agents|knowledge-bases|kb)\b.*\bcreate\b|foundry\s+ui\s+(pages|extensions)\b.*\bcreate\b'
  RESOURCE_DELETE_RE='foundry\s+(agents|knowledge-bases|kb)\b.*\bdelete\b'
  if echo "$FOUNDRY_CMDS" | grep -qE "$RESOURCE_CREATE_RE|$RESOURCE_DELETE_RE"; then
    # Extract resource name from --name flag (multiple syntax forms)
    RESOURCE_NAME=""
    if echo "$COMMAND" | grep -qE -- '--name[= ]'; then
      RESOURCE_NAME=$(echo "$COMMAND" | grep -oE -- '--name[= ]+("[^"]*"|'"'"'[^'"'"']*'"'"'|[^ ]+)' | head -1 | sed 's/^--name[= ]*//' | tr -d "\"'" || true)
    fi
    # Only fire if we extracted a real name (not empty, not a flag)
    if [ -n "$RESOURCE_NAME" ] && ! echo "$RESOURCE_NAME" | grep -qE '^-'; then
      if echo "$FOUNDRY_CMDS" | grep -qE "$RESOURCE_DELETE_RE"; then
        CONFIRM_MSG="STOP — Confirm the deletion with the user before running this. You are about to delete the Foundry AI artifact \"${RESOURCE_NAME}\", which removes its manifest entry AND its entire directory from disk. There is no undo and no \`edit\` command to fall back on. Ask the user to confirm first, unless they already explicitly asked to delete this exact artifact."
      else
        CONFIRM_MSG="STOP — Confirm the resource name with the user before creating. You are about to create a Foundry resource named \"${RESOURCE_NAME}\". Ask the user to confirm the name and description BEFORE running this command. If the user already explicitly confirmed this exact name in this conversation, proceed."
      fi
      if [ -n "$PENDING_REMINDER" ]; then
        CONFIRM_MSG="${PENDING_REMINDER}

${CONFIRM_MSG}"
      fi
      emit_advisory "PreToolUse" "$CONFIRM_MSG"
      exit 0
    fi
  fi
fi

# Check for forbidden manual directory/file creation
FORBIDDEN_PATTERNS=(
  'mkdir.*\b(api-integrations|workflows|functions|collections|ui|agents|knowledge-bases|knowledge_bases)\b'
  'touch.*manifest\.yml'
  'mkdir.*\bapp\b.*&&.*touch.*manifest'
  'echo.*>.*manifest\.yml'
  'cat.*>.*manifest\.yml'
)

for pattern in "${FORBIDDEN_PATTERNS[@]}"; do
  if echo "$COMMAND" | grep -qE "$pattern"; then
    emit_advisory "PreToolUse" "Manual creation of Foundry app structure detected. Use the Foundry CLI instead — it generates manifest.yml with correct schema version, app ID, and auth context. Run: foundry apps create --name \"app-name\" --no-prompt"
    exit 0
  fi
done

# Nothing else fired — emit a parked reminder on its own, if there is one.
if [ -n "$PENDING_REMINDER" ]; then
  emit_advisory "PreToolUse" "$PENDING_REMINDER"
  exit 0
fi

# Command is valid
exit 0
