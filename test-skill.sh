#!/usr/bin/env bash
#
# test-skill.sh — Run the Foundry skill N times unattended, deploy each, compare results.
#
# Usage:
#   ./test-skill.sh                                    # Normal run (5 trials, local plugin)
#   ./test-skill.sh --runs 3                           # Run 3 trials
#   ./test-skill.sh --plugin-dir /path/to/plugin       # Use a different plugin directory
#   ./test-skill.sh --no-plugin                        # Run without any plugin
#   ./test-skill.sh --save results.json                # Run and save results to JSON
#   ./test-skill.sh --baseline prev.json               # Run and compare against baseline
#   ./test-skill.sh --save new.json --baseline old.json --runs 5  # Full A/B comparison
#
set -euo pipefail

RUNS=5
BASE_DIR="/tmp/foundry-skill-test"
SAVE_FILE=""
BASELINE_FILE=""
PLUGIN_DIR="."
NO_PLUGIN=0
SKIP_PLUGIN_MANAGE=0

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --save)
      SAVE_FILE="$2"
      shift 2
      ;;
    --baseline)
      BASELINE_FILE="$2"
      if [ ! -f "$BASELINE_FILE" ]; then
        echo "ERROR: Baseline file not found: $BASELINE_FILE"
        exit 1
      fi
      shift 2
      ;;
    --runs)
      RUNS="$2"
      shift 2
      ;;
    --dir)
      BASE_DIR="$2"
      shift 2
      ;;
    --plugin-dir)
      PLUGIN_DIR="$2"
      shift 2
      ;;
    --no-plugin)
      NO_PLUGIN=1
      shift
      ;;
    --skip-plugin-manage)
      SKIP_PLUGIN_MANAGE=1
      shift
      ;;
    *)
      echo "Usage: $0 [--save <file.json>] [--baseline <file.json>] [--runs N] [--dir <path>] [--plugin-dir <path>] [--no-plugin] [--skip-plugin-manage]"
      exit 1
      ;;
  esac
done
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESULT_SCHEMA=$(cat "$SCRIPT_DIR/test-result-schema.json")

# Ensure headless mode for all Foundry CLI commands in this script
export FOUNDRY_UI_HEADLESS_MODE=true

PROMPT="Create a Falcon Foundry app for me that has an Okta API integration with openapi. Share its listusers endpoint with Falcon Fusion SOAR. Then, create a workflow that can be run on-demand to email or print the list of users. Finally, create a UI extension that calls the listusers endpoint and displays the results. Pick a reasonable app name and proceed without asking me any questions.

When done, respond with valid JSON matching this schema:
${RESULT_SCHEMA}

Example:
{\"app_name\":\"okta-users-run-RUN_NUMBER\",\"deploy_status\":\"SUCCESS\",\"deployment_id\":\"6b0f9a6c6ec841b8bcaffefc2b5a25aa\",\"spec_source\":\"DOWNLOADED\",\"capabilities\":[\"Okta API integration (listUsers shared with Falcon Fusion SOAR)\",\"On-demand workflow (list-okta-users)\",\"UI extension (okta-users on activity.detections.details)\"],\"errors\":\"NONE\"}"

# TODO: When `foundry apps validate` ships, add to PROMPT before the deploy step:
#   "Before deploying, run `foundry apps validate`. If validation fails,
#    skip the deploy, report DEPLOY_STATUS: FAILED, and stop immediately."
# This will cut no-skill baseline runs from ~30 min to ~5 min.

# Build --plugin-dir flags (empty array = no plugin loaded)
if [ "$NO_PLUGIN" = "1" ]; then
  PLUGIN_DIR_FLAGS=()
  echo "Plugin: none (--no-plugin)"
elif [ -n "$PLUGIN_DIR" ]; then
  PLUGIN_DIR=$(cd "$PLUGIN_DIR" && pwd)  # Resolve to absolute path (script cd's to run dir later)
  PLUGIN_DIR_FLAGS=(--plugin-dir "$PLUGIN_DIR")
  echo "Plugin dir: $PLUGIN_DIR"
else
  PLUGIN_DIR_FLAGS=()
fi

# Disable installed Foundry plugins when using --plugin-dir
# Installed marketplace plugins take priority over --plugin-dir, so we must
# disable them temporarily. Re-enable on exit (even if interrupted).
# Skipped when called from run-ab-test.sh (which manages plugins itself).
ENABLED_FOUNDRY_PLUGINS=()
if [ "$SKIP_PLUGIN_MANAGE" != "1" ] && [ "$NO_PLUGIN" != "1" ] && [ -n "$PLUGIN_DIR" ]; then
  PLUGIN_LIST=$(claude plugin list 2>/dev/null || true)
  while IFS= read -r plugin; do
    if [ -n "$plugin" ] && echo "$PLUGIN_LIST" | grep -A3 "$plugin" | grep -q "enabled"; then
      ENABLED_FOUNDRY_PLUGINS+=("$plugin")
    fi
  done < <(echo "$PLUGIN_LIST" | grep -o 'foundry@[^ ]*' || true)

  if [ ${#ENABLED_FOUNDRY_PLUGINS[@]} -gt 0 ]; then
    echo "Disabling installed Foundry plugins (using --plugin-dir instead):"
    for plugin in "${ENABLED_FOUNDRY_PLUGINS[@]}"; do
      echo "  Disabling: $plugin"
      claude plugin disable "$plugin" 2>/dev/null || true
    done
    trap 'echo ""; [ -n "${TIMER_PID:-}" ] && kill "$TIMER_PID" 2>/dev/null || true; if [ ${#ENABLED_FOUNDRY_PLUGINS[@]} -gt 0 ]; then echo "Re-enabling Foundry plugins..."; for p in "${ENABLED_FOUNDRY_PLUGINS[@]}"; do echo "  Enabling: $p"; claude plugin enable "$p" 2>/dev/null || true; done; fi' EXIT
    echo ""
  fi
fi

rm -rf "$BASE_DIR"
mkdir -p "$BASE_DIR"

# Extract token counts from a stream-json log file
# Returns "input_tokens output_tokens" on stdout
get_tokens() {
  local log_file="$1"
  local input output
  input=$(grep '"type":"assistant"' "$log_file" 2>/dev/null | \
    jq -r '[.message.usage.input_tokens // 0, .message.usage.cache_creation_input_tokens // 0, .message.usage.cache_read_input_tokens // 0] | add' 2>/dev/null | \
    awk '{s+=$1} END {printf "%d", s+0}' || echo "0")
  output=$(grep '"type":"assistant"' "$log_file" 2>/dev/null | \
    jq -r '.message.usage.output_tokens // 0' 2>/dev/null | \
    awk '{s+=$1} END {printf "%d", s+0}' || echo "0")
  echo "$input $output"
}

# Find the app directory (containing manifest.yml) under a run directory
# Returns "NOT FOUND" if no manifest exists
find_app_dir() {
  local dir="$1"
  local f
  f=$(find "$dir" -name "manifest.yml" -maxdepth 3 2>/dev/null | head -1)
  [ -n "$f" ] && dirname "$f" || echo "NOT FOUND"
}

# API health check: send a minimal request to verify connectivity before burning tokens
check_api_health() {
  # Use claude with a trivial prompt — just check if it exits successfully
  env -u CLAUDECODE claude -p "Reply with OK" \
    --model haiku > /dev/null 2>&1
  return $?
}

for i in $(seq 1 $RUNS); do
  RUN_DIR="$BASE_DIR/run-$i"
  mkdir -p "$RUN_DIR"
  LOG_FILE="$BASE_DIR/run-$i.log"
  RUN_PROMPT="${PROMPT//RUN_NUMBER/$i}"

  echo "========================================="
  echo "  RUN $i of $RUNS"
  echo "  Directory: $RUN_DIR"
  echo "  Log: $LOG_FILE"
  echo "========================================="

  # Pre-flight: verify API is reachable before starting an expensive run
  echo "  Checking API connectivity..."
  API_OK=false
  for attempt in 1 2 3; do
    if check_api_health "$attempt"; then
      API_OK=true
      echo "  API is reachable."
      break
    fi
    if [ "$attempt" -lt 3 ]; then
      echo "  API unreachable (attempt $attempt/3), retrying in 30s..."
      sleep 30
    fi
  done
  if [ "$API_OK" = false ]; then
    echo "  ERROR: API unreachable after 3 attempts. Aborting remaining runs."
    echo "  Check https://status.claude.com for outages."
    # Write a marker so the scorecard knows this was an API failure
    echo '{"error":"API ConnectionRefused"}' > "$LOG_FILE"
    break
  fi

  # Run claude in non-interactive pipe mode, bypassing permission prompts
  # Use stream-json to capture tool calls for anti-pattern analysis
  cd "$RUN_DIR"
  RUN_START=$(date +%s)
  FOUNDRY_SKIP_NAME_CONFIRM=1 env -u CLAUDECODE claude -p "$RUN_PROMPT" \
    ${PLUGIN_DIR_FLAGS[@]+"${PLUGIN_DIR_FLAGS[@]}"} \
    --dangerously-skip-permissions \
    --model claude-4-6-opus \
    --verbose \
    --output-format stream-json \
    > "$LOG_FILE" 2>&1 &
  CLAUDE_PID=$!
  # Live elapsed timer (updates every 10s on the same line)
  ( while kill -0 "$CLAUDE_PID" 2>/dev/null; do
      ELAPSED=$(( $(date +%s) - RUN_START ))
      printf "\r  ⏱  %d:%02d elapsed" $((ELAPSED/60)) $((ELAPSED%60))
      sleep 10
    done ) &
  TIMER_PID=$!
  wait "$CLAUDE_PID" 2>/dev/null || true
  kill "$TIMER_PID" 2>/dev/null || true
  wait "$TIMER_PID" 2>/dev/null || true
  RUN_ELAPSED=$(( $(date +%s) - RUN_START ))
  printf "\r  ⏱  %d:%02d total                \n" $((RUN_ELAPSED/60)) $((RUN_ELAPSED%60))

  # Verify skills loaded from --plugin-dir, not from installed cache
  if [ "$NO_PLUGIN" != "1" ] && [ -n "$PLUGIN_DIR" ]; then
    RESOLVED_PLUGIN_DIR=$(cd "$PLUGIN_DIR" && pwd)
    SKILL_SOURCE=$(grep -o 'Base directory for this skill: [^\\]*' "$LOG_FILE" 2>/dev/null | head -1 | sed 's/Base directory for this skill: //')
    if [ -n "$SKILL_SOURCE" ]; then
      if echo "$SKILL_SOURCE" | grep -q "plugins/cache"; then
        echo ""
        echo "  ❌ FATAL: Skills loaded from installed cache, not --plugin-dir!"
        echo "     Expected: $RESOLVED_PLUGIN_DIR/skills/..."
        echo "     Got:      $SKILL_SOURCE"
        echo ""
        echo "  The installed marketplace plugin overrides --plugin-dir."
        echo "  Fix: disable the installed plugin before running tests."
        echo "     Disable any installed Foundry plugin that overrides --plugin-dir"
        echo ""
        exit 1
      elif ! echo "$SKILL_SOURCE" | grep -q "$RESOLVED_PLUGIN_DIR"; then
        echo ""
        echo "  ⚠️  WARNING: Skills loaded from unexpected path:"
        echo "     Expected: $RESOLVED_PLUGIN_DIR/skills/..."
        echo "     Got:      $SKILL_SOURCE"
        echo ""
      fi
    fi
  fi

  # Extract and display the JSON result summary from stream-json log
  grep -o '{"type":"assistant".*' "$LOG_FILE" 2>/dev/null | \
    jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text' 2>/dev/null | \
    python3 -c "
import sys, json, re
text = sys.stdin.read()
# Find JSON objects containing deploy_status
for m in re.finditer(r'\{[^{}]*(?:\{[^{}]*\}[^{}]*)*(?:\[[^\[\]]*\][^{}]*)*\}', text):
    try:
        obj = json.loads(m.group())
        if 'deploy_status' in obj:
            print(json.dumps(obj, indent=2))
            break
    except: pass
" 2>/dev/null

  # Extract token usage from stream-json log
  read -r INPUT_TOKENS OUTPUT_TOKENS <<< "$(get_tokens "$LOG_FILE")"
  TOTAL_TOKENS=$((INPUT_TOKENS + OUTPUT_TOKENS))
  printf "  Token usage: %s input, %s output, %s total\n" \
    "${INPUT_TOKENS:-0}" "${OUTPUT_TOKENS:-0}" "$TOTAL_TOKENS"

  echo ""
  echo "--- Run $i complete ---"
  echo ""
done

echo ""
echo "========================================="
echo "  COMPARISON ACROSS ALL $RUNS RUNS"
echo "========================================="
echo ""

for i in $(seq 1 $RUNS); do
  RUN_DIR="$BASE_DIR/run-$i"
  LOG_FILE="$BASE_DIR/run-$i.log"

  echo "=== Run $i ==="

  # Extract text content and tool calls from stream-json log
  TEXT_FILE="$BASE_DIR/run-$i.text"
  TOOLS_FILE="$BASE_DIR/run-$i.tools"
  grep -o '{"type":"assistant".*' "$LOG_FILE" 2>/dev/null | \
    jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text' 2>/dev/null > "$TEXT_FILE" || true
  # Extract Bash tool commands from tool_use and result events
  grep -o '{"type":"assistant".*' "$LOG_FILE" 2>/dev/null | \
    jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use" and .name=="Bash") | .input.command' 2>/dev/null > "$TOOLS_FILE" || true
  # Also extract Skill tool invocations
  SKILLS_FILE="$BASE_DIR/run-$i.skills"
  grep -o '{"type":"assistant".*' "$LOG_FILE" 2>/dev/null | \
    jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use" and .name=="Skill") | .input.skill' 2>/dev/null > "$SKILLS_FILE" || true

  # Extract reference file reads (Read tool calls to references/*.md)
  REFS_FILE="$BASE_DIR/run-$i.refs"
  grep -o '{"type":"assistant".*' "$LOG_FILE" 2>/dev/null | \
    jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use" and .name=="Read") | .input.file_path' 2>/dev/null | \
    grep '/references/' > "$REFS_FILE" || true

  # Extract LSP tool calls (operation + file:line)
  LSP_FILE="$BASE_DIR/run-$i.lsp"
  grep -o '{"type":"assistant".*' "$LOG_FILE" 2>/dev/null | \
    jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use" and .name=="LSP") | "\(.input.operation) \(.input.filePath):\(.input.line)"' 2>/dev/null > "$LSP_FILE" || true

  # Fall back to raw text if stream-json parsing fails
  if [ ! -s "$TEXT_FILE" ] && [ -f "$LOG_FILE" ]; then
    cp "$LOG_FILE" "$TEXT_FILE"
  fi

  # Check if an app directory was created
  APP_DIR=$(find_app_dir "$RUN_DIR")
  echo "App directory: $APP_DIR"

  if [ "$APP_DIR" != "NOT FOUND" ] && [ -d "$APP_DIR" ]; then
    echo ""
    echo "Files created:"
    find "$APP_DIR" -type f ! -path "*/node_modules/*" ! -path "*/.git/*" | sort | sed 's|^|  |'

    echo ""
    echo "Manifest (first 30 lines):"
    head -30 "$APP_DIR/manifest.yml" 2>/dev/null | sed 's|^|  |'
  fi

  echo ""

  # Parse JSON result summary if present
  RESULT_JSON=$(python3 -c "
import sys, json, re
text = open(sys.argv[1]).read()
for m in re.finditer(r'\{[^{}]*(?:\{[^{}]*\}[^{}]*)*(?:\[[^\[\]]*(?:\[[^\[\]]*\][^\[\]]*)*\][^{}]*)*\}', text):
    try:
        obj = json.loads(m.group())
        if 'deploy_status' in obj:
            print(json.dumps(obj))
            break
    except: pass
" "$TEXT_FILE" 2>/dev/null || true)

  if [ -n "$RESULT_JSON" ]; then
    echo "Structured summary:"
    echo "$RESULT_JSON" | jq -r 'to_entries[] | "  \(.key | ascii_upcase): \(.value | if type == "array" then join(", ") else tostring end)"' 2>/dev/null
  else
    echo "No structured summary found — parsing logs:"

    # Check deploy result
    if grep -qi "deployment succeeded\|deploying to your\|deploy.*success\|in progress\|deployed\b" "$TEXT_FILE" 2>/dev/null; then
      echo "  Deploy: LIKELY SUCCESS"
    elif grep -qi "deploy.*fail\|deployment failed" "$TEXT_FILE" 2>/dev/null; then
      echo "  Deploy: FAILED"
    else
      echo "  Deploy: NOT ATTEMPTED or UNKNOWN"
    fi

    # Check release result
    if grep -qi "release.*success\|released\|release.*complete" "$TEXT_FILE" 2>/dev/null; then
      echo "  Release: LIKELY SUCCESS"
    elif grep -qi "release.*fail" "$TEXT_FILE" 2>/dev/null; then
      echo "  Release: FAILED"
    else
      echo "  Release: NOT ATTEMPTED or UNKNOWN"
    fi
  fi

  # Check for known anti-patterns
  echo ""
  echo "Anti-pattern checks:"

  if grep -qi "foundry apps validate" "$TEXT_FILE" "$TOOLS_FILE" 2>/dev/null; then
    echo "  ❌ Tried 'foundry apps validate' (does not exist)"
  else
    echo "  ✅ Did not try 'foundry apps validate'"
  fi

  if grep -qi "foundry apps init" "$TEXT_FILE" "$TOOLS_FILE" 2>/dev/null; then
    echo "  ❌ Tried 'foundry apps init' (does not exist)"
  else
    echo "  ✅ Did not try 'foundry apps init'"
  fi

  if grep -qi "gh.*search\|gh.*api\|curl.*github\|curl.*raw.githubusercontent\|download.*spec" "$TEXT_FILE" "$TOOLS_FILE" 2>/dev/null; then
    echo "  ✅ OpenAPI spec downloaded"
  elif grep -qi "Write.*/tmp/.*\.\(yaml\|json\|yml\)" "$TEXT_FILE" "$TOOLS_FILE" 2>/dev/null; then
    echo "  ❌ OpenAPI spec written from scratch"
  else
    echo "  ⚠️  OpenAPI spec source unclear"
  fi

  if grep -qi "switching.*oauth\|changed.*auth\|switch.*clientCredentials\|authorizationCode.*to.*clientCredentials" "$TEXT_FILE" 2>/dev/null; then
    echo "  ❌ Changed vendor auth scheme"
  else
    echo "  ✅ Did not change vendor auth scheme"
  fi

  if grep -qi "replace.*subdomain\|replace.*your-org\|replace.*okta\.com.*with" "$TEXT_FILE" 2>/dev/null; then
    echo "  ❌ Replaced server variable defaults"
  else
    echo "  ✅ Did not replace server variable defaults"
  fi

  # Check if the OpenAPI spec was Read into context (token waste)
  SPEC_READS=0
  SPEC_READ_FILES=""
  if [ -s "$BASE_DIR/run-$i.log" ]; then
    SPEC_READ_FILES=$(grep '"type":"assistant"' "$BASE_DIR/run-$i.log" 2>/dev/null | \
      jq -r '.message.content[]? | select(.type=="tool_use" and .name=="Read") | .input.file_path' 2>/dev/null | \
      grep -E 'api-integrations/' || true)
    if [ -n "$SPEC_READ_FILES" ]; then
      SPEC_READS=$(echo "$SPEC_READ_FILES" | wc -l | tr -d ' ')
    fi
  fi
  if [ "$SPEC_READS" -gt 0 ]; then
    echo "  ❌ Read API integration spec $SPEC_READS time(s) — use grep/python3 instead:"
    echo "$SPEC_READ_FILES" | sed 's|^|     |'
  else
    echo "  ✅ Did not Read API integration spec files (good — saves tokens)"
  fi

  # CLI guard enforcement checks (from tool call logs)
  echo ""
  echo "CLI guard checks:"

  # Check --no-prompt on create commands
  # Note: api-integrations create and workflows create work non-interactively
  # when --spec is provided (all input supplied via flags), same as deploy/release.
  CREATES_MISSING_FLAG=false
  if [ -s "$TOOLS_FILE" ]; then
    while IFS= read -r cmd; do
      if echo "$cmd" | grep -qE 'foundry\s+(apps|ui|functions|collections|workflows|api-integrations|rtr-scripts|profile)\b.*\bcreate\b'; then
        if ! echo "$cmd" | grep -qF -- '--no-prompt'; then
          # Skip false positives: --spec provides all input, no prompts needed
          if echo "$cmd" | grep -qE '(api-integrations|workflows)\s+create' && echo "$cmd" | grep -qF -- '--spec'; then
            continue
          fi
          echo "  ❌ Missing --no-prompt: $cmd"
          CREATES_MISSING_FLAG=true
        fi
      fi
    done < "$TOOLS_FILE"
  fi
  if [ "$CREATES_MISSING_FLAG" = false ]; then
    echo "  ✅ All foundry create commands include --no-prompt"
  fi

  # Check for manual mkdir of app structure
  MANUAL_MKDIR=false
  if [ -s "$TOOLS_FILE" ]; then
    if grep -qE 'mkdir.*(api-integrations|workflows|functions|collections|ui/)' "$TOOLS_FILE" 2>/dev/null; then
      echo "  ❌ Used mkdir for app structure (should use foundry CLI)"
      MANUAL_MKDIR=true
    fi
  fi
  if [ "$MANUAL_MKDIR" = false ]; then
    echo "  ✅ Did not manually create app structure directories"
  fi

  # Check for manual manifest.yml creation
  MANUAL_MANIFEST=false
  if [ -s "$TOOLS_FILE" ]; then
    if grep -qE 'touch manifest\.yml|echo.*>.*manifest\.yml|cat.*>.*manifest\.yml' "$TOOLS_FILE" 2>/dev/null; then
      echo "  ❌ Manually created manifest.yml (should use foundry CLI)"
      MANUAL_MANIFEST=true
    fi
  fi
  if [ "$MANUAL_MANIFEST" = false ]; then
    echo "  ✅ Did not manually create manifest.yml"
  fi

  # Check orchestrator skill usage
  if [ -s "$SKILLS_FILE" ] && grep -qi "foundry-development-workflow" "$SKILLS_FILE" 2>/dev/null; then
    echo "  ✅ Used Foundry orchestrator skill"
  elif grep -qi "foundry:foundry-development-workflow\|foundry-development-workflow" "$TEXT_FILE" 2>/dev/null; then
    echo "  ✅ Used Foundry orchestrator skill"
  else
    echo "  ⚠️  May not have used Foundry orchestrator skill"
  fi

  # LSP tool usage
  LSP_FILE="$BASE_DIR/run-$i.lsp"
  if [ -s "$LSP_FILE" ]; then
    LSP_COUNT=$(wc -l < "$LSP_FILE" | tr -d ' ')
    LSP_OPS=$(awk '{print $1}' "$LSP_FILE" | sort | uniq -c | sort -rn | awk '{printf "%s(%d) ", $2, $1}')
    echo ""
    echo "LSP usage: $LSP_COUNT calls — $LSP_OPS"
    sed 's|^|    |' "$LSP_FILE"
  else
    echo ""
    echo "LSP usage: none"
  fi

  # Static file checks (only if app was created)
  if [ "$APP_DIR" != "NOT FOUND" ] && [ -d "$APP_DIR" ]; then
    echo ""
    echo "Generated file checks:"

    # Check OpenAPI spec server variables
    SPEC_FILES=$(find "$APP_DIR/api-integrations" -name "*.yaml" -o -name "*.yml" -o -name "*.json" 2>/dev/null)
    if [ -n "$SPEC_FILES" ]; then
      SPEC_OK=true
      for spec in $SPEC_FILES; do
        if grep -q 'default:' "$spec" 2>/dev/null && grep -q 'variables:' "$spec" 2>/dev/null && ! grep -q 'enum:' "$spec" 2>/dev/null; then
          echo "  ❌ Server variable has 'default' without 'enum' — renders as dropdown with one unusable value ($spec)"
          SPEC_OK=false
        fi
        if grep -q 'variables:' "$spec" 2>/dev/null && \
           grep -A3 '^servers:' "$spec" 2>/dev/null | grep -qE 'url:.*https://'; then
          echo "  ❌ Server URL has https:// prefix with variables — causes double-protocol ($spec)"
          SPEC_OK=false
        fi
      done
      if [ "$SPEC_OK" = true ]; then
        echo "  ✅ OpenAPI server variables configured correctly"
      fi

      # Check for x-cs-operation-config (required for Fusion SOAR sharing)
      SOAR_OK=false
      for spec in $SPEC_FILES; do
        if grep -q 'x-cs-operation-config' "$spec" 2>/dev/null; then
          SOAR_OK=true
        fi
      done
      if [ "$SOAR_OK" = true ]; then
        echo "  ✅ x-cs-operation-config present (Fusion SOAR sharing enabled)"
      else
        echo "  ❌ Missing x-cs-operation-config — endpoints not shared with Falcon Fusion SOAR"
      fi
    else
      echo "  ⚠️  No API integration spec files found"
    fi

    # Check workflow YAML for email issues
    WF_FILES=$(find "$APP_DIR/workflows" -name "*.yaml" -o -name "*.yml" 2>/dev/null)
    if [ -n "$WF_FILES" ]; then
      WF_OK=true
      for wf in $WF_FILES; do
        # Check for empty email recipients (to: "", to: [], to: [""], recipients: [])
        # but allow variable references ($inputs.email, $trigger.input.email, etc.)
        if grep -qE 'to:\s*""' "$wf" 2>/dev/null; then
          echo "  ❌ Workflow has empty email 'to' field — will fail at execution ($wf)"
          WF_OK=false
        elif grep -qE "to:\s*''" "$wf" 2>/dev/null; then
          echo "  ❌ Workflow has empty email 'to' field — will fail at execution ($wf)"
          WF_OK=false
        elif grep -qE 'recipients:\s*\[\]' "$wf" 2>/dev/null; then
          echo "  ❌ Workflow has empty 'recipients' array — will fail at execution ($wf)"
          WF_OK=false
        fi

        # Check for {{mustache}} variable syntax (should be $ prefix)
        if grep -qE '\{\{[a-z_]+\.' "$wf" 2>/dev/null; then
          echo "  ❌ Workflow uses {{mustache}} variable syntax — Fusion requires \$ prefix ($wf)"
          WF_OK=false
        fi

        # Check for placeholder email addresses (example.com)
        if grep -qiE 'example\.(com|org|net)' "$wf" 2>/dev/null; then
          PLACEHOLDER_EMAIL=$(grep -oiE '[a-zA-Z0-9._%+-]+@example\.(com|org|net)' "$wf" 2>/dev/null | head -1)
          echo "  ⚠️  Workflow uses placeholder email: ${PLACEHOLDER_EMAIL:-example.com} — update before running"
          # Not a failure since --dangerously-skip-permissions can't prompt for real email
        fi
      done
      if [ "$WF_OK" = true ]; then
        echo "  ✅ Workflow YAML looks correct"
      fi
    else
      echo "  ⚠️  No workflow files found"
    fi
  fi

  echo ""
  echo "---"
  echo ""
done

# Check deploy status for a run. Returns: DEPLOYED, PENDING, or FAILED
# Polls list-deployments up to 90s for async completion when agent reported success.
check_deploy_status() {
  local app_dir="$1" text_file="$2"

  if grep -q '"deploy_status".*"SUCCESS"' "$text_file" 2>/dev/null; then
    # Agent reported success — verify with list-deployments
    for attempt in 1 2 3 4 5 6; do
      local deploy_out
      deploy_out=$(cd "$app_dir" && foundry apps list-deployments 2>&1)
      if echo "$deploy_out" | grep -q "Successful"; then
        echo "DEPLOYED_VERIFIED"; return
      elif echo "$deploy_out" | grep -qE "progress|Deploying|Building"; then
        sleep 15
      else
        break
      fi
    done
    # Agent said SUCCESS but can't confirm — trust it
    local deploy_out
    deploy_out=$(cd "$app_dir" && foundry apps list-deployments 2>&1)
    if echo "$deploy_out" | grep -q "DEPLOYMENT ID"; then
      echo "DEPLOYED_EXISTS"; return
    fi
    echo "DEPLOYED_UNVERIFIED"; return
  fi

  # No agent summary or agent reported failure
  local deploy_out
  deploy_out=$(cd "$app_dir" && foundry apps list-deployments 2>&1)
  if echo "$deploy_out" | grep -q "Successful"; then
    echo "DEPLOYED"; return
  elif echo "$deploy_out" | grep -q "DEPLOYMENT ID"; then
    echo "PENDING"; return
  fi
  echo "FAILED"
}

# Overall scorecard
echo "========================================="
echo "  SCORECARD"
echo "========================================="
PASS=0
TOTAL=0
for i in $(seq 1 $RUNS); do
  RUN_DIR="$BASE_DIR/run-$i"
  TOTAL=$((TOTAL + 1))
  APP_DIR=$(find_app_dir "$RUN_DIR")
  if [ "$APP_DIR" != "NOT FOUND" ] && [ -d "$APP_DIR" ]; then
    # TODO: When `foundry apps validate` ships, validate before checking deployments:
    #   VALIDATE_OUT=$(cd "$APP_DIR" && foundry apps validate 2>&1) || true
    #   if echo "$VALIDATE_OUT" | grep -qi "error\|invalid"; then
    #     echo "  Run $i: ❌ INVALID MANIFEST"
    #     continue
    #   fi

    TEXT_FILE="$BASE_DIR/run-$i.text"
    STATUS=$(check_deploy_status "$APP_DIR" "$TEXT_FILE")
    case "$STATUS" in
      DEPLOYED_VERIFIED)
        echo "  Run $i: ✅ DEPLOYED (verified)"; PASS=$((PASS + 1)) ;;
      DEPLOYED_EXISTS)
        echo "  Run $i: ✅ DEPLOYED (agent-reported, deployment exists)"; PASS=$((PASS + 1)) ;;
      DEPLOYED_UNVERIFIED)
        echo "  Run $i: ⚠️  DEPLOYED (agent-reported SUCCESS, not yet verified)"; PASS=$((PASS + 1)) ;;
      DEPLOYED)
        echo "  Run $i: ✅ DEPLOYED"; PASS=$((PASS + 1)) ;;
      PENDING)
        echo "  Run $i: ⚠️  DEPLOYED (non-successful state)" ;;
      *)
        echo "  Run $i: ❌ NOT DEPLOYED" ;;
    esac
  else
    echo "  Run $i: ❌ NO APP CREATED"
  fi
done
echo ""
echo "  $PASS/$TOTAL deployed"
echo ""

# Token usage summary
echo "========================================="
echo "  TOKEN USAGE"
echo "========================================="
for i in $(seq 1 $RUNS); do
  LOG_FILE="$BASE_DIR/run-$i.log"
  read -r INPUT_TOKENS OUTPUT_TOKENS <<< "$(get_tokens "$LOG_FILE")"
  TOTAL_TOKENS=$((INPUT_TOKENS + OUTPUT_TOKENS))
  printf "  Run %d: %7s input, %7s output, %7s total\n" \
    "$i" "${INPUT_TOKENS:-0}" "${OUTPUT_TOKENS:-0}" "$TOTAL_TOKENS"
done
echo ""
echo "Full logs: $BASE_DIR/run-*.log"

# Build results JSON
TOKENS_JSON=""
REFS_JSON=""
SKILLS_JSON=""
LSP_JSON=""
ANTI_PATTERN_COUNTS=""
SPEC_QUALITY_COUNTS=""
for i in $(seq 1 $RUNS); do
  LOG_FILE="$BASE_DIR/run-$i.log"
  TEXT_FILE="$BASE_DIR/run-$i.text"
  TOOLS_FILE="$BASE_DIR/run-$i.tools"
  REFS_FILE="$BASE_DIR/run-$i.refs"
  SKILLS_FILE="$BASE_DIR/run-$i.skills"

  IT=0; OT=0
  read -r IT OT <<< "$(get_tokens "$LOG_FILE")"
  SEP=""; [ "$i" -lt "$RUNS" ] && SEP=","
  TOKENS_JSON="${TOKENS_JSON}    {\"run\": $i, \"input\": ${IT}, \"output\": ${OT}, \"total\": $(( IT + OT ))}${SEP}
"

  # Reference file reads per run
  if [ -s "$REFS_FILE" ]; then
    REF_LIST=$(jq -R -s 'split("\n") | map(select(. != ""))' "$REFS_FILE" 2>/dev/null || echo "[]")
  else
    REF_LIST="[]"
  fi
  REFS_JSON="${REFS_JSON}    \"run_$i\": ${REF_LIST}${SEP}
"

  # Skill invocations per run
  if [ -s "$SKILLS_FILE" ]; then
    SKILL_LIST=$(jq -R -s 'split("\n") | map(select(. != ""))' "$SKILLS_FILE" 2>/dev/null || echo "[]")
  else
    SKILL_LIST="[]"
  fi
  SKILLS_JSON="${SKILLS_JSON}    \"run_$i\": ${SKILL_LIST}${SEP}
"

  # LSP calls per run
  LSP_FILE="$BASE_DIR/run-$i.lsp"
  if [ -s "$LSP_FILE" ]; then
    LSP_LIST=$(jq -R -s 'split("\n") | map(select(. != ""))' "$LSP_FILE" 2>/dev/null || echo "[]")
  else
    LSP_LIST="[]"
  fi
  LSP_JSON="${LSP_JSON}    \"run_$i\": ${LSP_LIST}${SEP}
"

  # Count anti-patterns per run
  AP_COUNT=0
  if [ -s "$TEXT_FILE" ] || [ -s "$TOOLS_FILE" ]; then
    grep -qi "foundry apps validate" "$TEXT_FILE" "$TOOLS_FILE" 2>/dev/null && AP_COUNT=$((AP_COUNT + 1))
    grep -qi "foundry apps init" "$TEXT_FILE" "$TOOLS_FILE" 2>/dev/null && AP_COUNT=$((AP_COUNT + 1))
    grep -qi "switching.*oauth\|changed.*auth\|switch.*clientCredentials" "$TEXT_FILE" 2>/dev/null && AP_COUNT=$((AP_COUNT + 1))
    grep -qi "replace.*subdomain\|replace.*your-org\|replace.*okta\.com.*with" "$TEXT_FILE" 2>/dev/null && AP_COUNT=$((AP_COUNT + 1))
    grep -qE 'mkdir.*(api-integrations|workflows|functions|collections|ui/)' "$TOOLS_FILE" 2>/dev/null && AP_COUNT=$((AP_COUNT + 1))
    grep -qE 'touch manifest\.yml|echo.*>.*manifest\.yml|cat.*>.*manifest\.yml' "$TOOLS_FILE" 2>/dev/null && AP_COUNT=$((AP_COUNT + 1))
  fi
  # Count spec file reads as anti-pattern (token waste)
  SPEC_READ_COUNT=$(grep '"type":"assistant"' "$LOG_FILE" 2>/dev/null | \
    jq -r '.message.content[]? | select(.type=="tool_use" and .name=="Read") | .input.file_path' 2>/dev/null | \
    grep -c 'api-integrations/' 2>/dev/null || echo "0")
  if [ "$SPEC_READ_COUNT" -gt 0 ] 2>/dev/null; then
    AP_COUNT=$((AP_COUNT + SPEC_READ_COUNT))
  fi
  ANTI_PATTERN_COUNTS="${ANTI_PATTERN_COUNTS}${AP_COUNT}${SEP}"

  # Count spec quality indicators per run
  SQ_COUNT=0
  RUN_DIR="$BASE_DIR/run-$i"
  APP_DIR=$(find_app_dir "$RUN_DIR")
  if [ "$APP_DIR" != "NOT FOUND" ] && [ -d "$APP_DIR" ]; then
    SPEC_FILES=$(find "$APP_DIR/api-integrations" -name "*.yaml" -o -name "*.yml" -o -name "*.json" 2>/dev/null || true)
    for spec in $SPEC_FILES; do
      grep -q 'x-cs-operation-config' "$spec" 2>/dev/null && SQ_COUNT=$((SQ_COUNT + 1))
    done
  fi
  SPEC_QUALITY_COUNTS="${SPEC_QUALITY_COUNTS}${SQ_COUNT}${SEP}"
done

RESULTS_JSON=$(cat <<ENDJSON
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "git_branch": "$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")",
  "git_commit": "$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")",
  "runs": $RUNS,
  "deploys": $PASS,
  "deploy_rate": "$(echo "scale=0; $PASS * 100 / $TOTAL" | bc)%",
  "tokens": [
${TOKENS_JSON}  ],
  "reference_reads": {
${REFS_JSON}  },
  "skill_invocations": {
${SKILLS_JSON}  },
  "lsp_calls": {
${LSP_JSON}  },
  "anti_pattern_counts": [${ANTI_PATTERN_COUNTS}],
  "spec_quality_counts": [${SPEC_QUALITY_COUNTS}]
}
ENDJSON
)

# Auto-save when --save is specified
if [ -n "$SAVE_FILE" ]; then
  mkdir -p "$(dirname "$SAVE_FILE")"
  echo "$RESULTS_JSON" > "$SAVE_FILE"
  echo ""
  echo "Results saved to: $SAVE_FILE"
fi

# Compare against baseline if --baseline was provided
if [ -n "$BASELINE_FILE" ]; then
  echo ""
  echo "========================================="
  echo "  A/B COMPARISON vs BASELINE"
  echo "========================================="
  echo "  Baseline: $BASELINE_FILE"
  echo ""

  B_DEPLOYS=$(jq -r '.deploys' "$BASELINE_FILE" 2>/dev/null || echo "?")
  B_RUNS=$(jq -r '.runs' "$BASELINE_FILE" 2>/dev/null || echo "?")
  B_RATE=$(jq -r '.deploy_rate' "$BASELINE_FILE" 2>/dev/null || echo "?")
  B_TOTAL_TOKENS=$(jq -r '[.tokens[].total] | add' "$BASELINE_FILE" 2>/dev/null || echo "?")
  B_AVG_TOKENS=$(jq -r '[.tokens[].total] | add / length | floor' "$BASELINE_FILE" 2>/dev/null || echo "?")
  B_AVG_AP=$(jq -r '[.anti_pattern_counts[]] | add / length' "$BASELINE_FILE" 2>/dev/null || echo "?")
  B_AVG_SQ=$(jq -r '[.spec_quality_counts[]] | add / length' "$BASELINE_FILE" 2>/dev/null || echo "?")
  B_REF_RUNS=$(jq -r '[.reference_reads | to_entries[] | select(.value | length > 0)] | length' "$BASELINE_FILE" 2>/dev/null || echo "?")

  C_TOTAL_TOKENS=$(echo "$RESULTS_JSON" | jq -r '[.tokens[].total] | add' 2>/dev/null || echo "?")
  C_AVG_TOKENS=$(echo "$RESULTS_JSON" | jq -r '[.tokens[].total] | add / length | floor' 2>/dev/null || echo "?")
  C_AVG_AP=$(echo "$RESULTS_JSON" | jq -r '[.anti_pattern_counts[]] | add / length' 2>/dev/null || echo "?")
  C_AVG_SQ=$(echo "$RESULTS_JSON" | jq -r '[.spec_quality_counts[]] | add / length' 2>/dev/null || echo "?")
  C_REF_RUNS=$(echo "$RESULTS_JSON" | jq -r '[.reference_reads | to_entries[] | select(.value | length > 0)] | length' 2>/dev/null || echo "?")

  printf "  %-24s %-15s %-15s\n" "" "Baseline" "Current"
  printf "  %-24s %-15s %-15s\n" "---" "---" "---"
  printf "  %-24s %-15s %-15s\n" "Deploy rate" "$B_RATE" "$(echo "scale=0; $PASS * 100 / $TOTAL" | bc)%"
  printf "  %-24s %-15s %-15s\n" "Deploys" "$B_DEPLOYS/$B_RUNS" "$PASS/$TOTAL"
  printf "  %-24s %-15s %-15s\n" "Total tokens" "$B_TOTAL_TOKENS" "$C_TOTAL_TOKENS"
  printf "  %-24s %-15s %-15s\n" "Avg tokens/run" "$B_AVG_TOKENS" "$C_AVG_TOKENS"
  printf "  %-24s %-15s %-15s\n" "Avg anti-patterns/run" "$B_AVG_AP" "$C_AVG_AP"
  printf "  %-24s %-15s %-15s\n" "Avg spec quality/run" "$B_AVG_SQ" "$C_AVG_SQ"
  printf "  %-24s %-15s %-15s\n" "Runs w/ ref reads" "$B_REF_RUNS" "$C_REF_RUNS"

  # Calculate token delta
  if [ "$B_AVG_TOKENS" != "?" ] && [ "$C_AVG_TOKENS" != "?" ]; then
    DELTA=$((C_AVG_TOKENS - B_AVG_TOKENS))
    if [ "$DELTA" -lt 0 ]; then
      PCT=$(echo "scale=1; $DELTA * 100 / $B_AVG_TOKENS" | bc)
      echo ""
      echo "  Token change: ${PCT}% (${DELTA} tokens/run)"
    elif [ "$DELTA" -gt 0 ]; then
      PCT=$(echo "scale=1; $DELTA * 100 / $B_AVG_TOKENS" | bc)
      echo ""
      echo "  Token change: +${PCT}% (+${DELTA} tokens/run)"
    else
      echo ""
      echo "  Token change: 0% (no change)"
    fi
  fi
  echo ""
fi
