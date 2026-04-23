#!/usr/bin/env bash
#
# verify-apps.sh — Verify that Foundry apps created by test-skill.sh actually work.
#
# Phase 1 (unattended): Discovery, spec analysis, release
# Phase 2 (interactive): Browser-based install → verify UI → workflow → uninstall
#
# Prerequisites:
#   - test-skill.sh has run successfully (apps exist in /tmp/foundry-skill-test/)
#   - Foundry CLI authenticated (`foundry login`)
#   - For Phase 2: Chrome open to Falcon console, Okta credentials set
#
# Environment variables:
#   OKTA_DOMAIN    — Okta domain (e.g. integrator-6849440.okta.com)
#   OKTA_API_KEY   — Okta API key
#   OKTA_INSTANCE  — Instance name (default: Okta)
#   FALCON_URL     — Falcon console URL (default: https://falcon.us-2.crowdstrike.com)
#   SKIP_RELEASE   — Set to 1 to skip release step
#   SKIP_BROWSER   — Set to 1 to run only Phase 1
#
set -euo pipefail

# ── Colors ──────────────────────────────────────────────────────
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Defaults ────────────────────────────────────────────────────
BASE_DIR="/tmp/foundry-skill-test"
OKTA_INSTANCE="${OKTA_INSTANCE:-Okta}"
FALCON_URL="${FALCON_URL:-https://falcon.us-2.crowdstrike.com}"
SKIP_RELEASE="${SKIP_RELEASE:-0}"
SKIP_BROWSER="${SKIP_BROWSER:-0}"

# ── Argument parsing ──────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)
      BASE_DIR="$2"
      shift 2
      ;;
    --green)
      BASE_DIR="/tmp/foundry-skill-ab/green-runs"
      shift
      ;;
    *)
      echo "Usage: $0 [--dir <path>] [--green]"
      echo "  --dir <path>  Verify apps in a specific directory (default: /tmp/foundry-skill-test)"
      echo "  --green       Shorthand for --dir /tmp/foundry-skill-ab/green-runs"
      exit 1
      ;;
  esac
done

REPORT_FILE="$BASE_DIR/verify-apps.json"

# ── Preflight ───────────────────────────────────────────────────
if [ ! -d "$BASE_DIR" ]; then
  printf "${RED}ERROR: %s does not exist. Run test-skill.sh first.${RESET}\n" "$BASE_DIR" >&2
  exit 1
fi

# Check for run directories
RUN_DIRS=()
for d in "$BASE_DIR"/run-*/; do
  [ -d "$d" ] && RUN_DIRS+=("$d")
done

if [ ${#RUN_DIRS[@]} -eq 0 ]; then
  printf "${RED}ERROR: No run-N directories found in %s${RESET}\n" "$BASE_DIR" >&2
  exit 1
fi

printf "${BLUE}==========================================${RESET}\n"
printf "${BLUE}  VERIFY-APPS — Phase 1: Discovery${RESET}\n"
printf "${BLUE}==========================================${RESET}\n"
printf "  Base directory: %s\n" "$BASE_DIR"
printf "  Runs found: %d\n\n" "${#RUN_DIRS[@]}"

# ── Phase 1: Discovery, spec analysis, release ─────────────────

# JSON array accumulator
APPS_JSON="[]"

for run_dir in "${RUN_DIRS[@]}"; do
  RUN_NUM=$(basename "$run_dir" | sed 's/run-//')

  # Find manifest.yml
  MANIFEST=$(find "$run_dir" -name "manifest.yml" -maxdepth 3 2>/dev/null | head -1)
  if [ -z "$MANIFEST" ]; then
    printf "${YELLOW}  Run %s: No manifest.yml found, skipping${RESET}\n" "$RUN_NUM"
    continue
  fi

  APP_DIR=$(dirname "$MANIFEST")
  APP_NAME=$(grep '^name:' "$MANIFEST" | head -1 | sed 's/^name:[[:space:]]*//')

  printf "${CYAN}── Run %s: %s ──${RESET}\n" "$RUN_NUM" "$APP_NAME"

  # Extract deployment info
  # Header line: "Deployments for App: name (app_id)"
  # Table row:   "| deployment_id | version | state |"
  DEPLOY_OUT=$(cd "$APP_DIR" && foundry apps list-deployments 2>&1) || true
  APP_ID=$(echo "$DEPLOY_OUT" | grep -oE '\([0-9a-f]{32}\)' | tr -d '()' | head -1 || echo "")
  DEPLOYMENT_ID=$(echo "$DEPLOY_OUT" | grep '^|' | grep -oE '[0-9a-f]{32}' | head -1 || echo "")
  DEPLOY_STATE=$(echo "$DEPLOY_OUT" | grep -oE 'Successful|Failed|In Progress' | head -1 || echo "Unknown")

  printf "  App ID:        %s\n" "${APP_ID:-NOT FOUND}"
  printf "  Deployment ID: %s\n" "${DEPLOYMENT_ID:-NOT FOUND}"
  printf "  Deploy state:  %s\n" "$DEPLOY_STATE"

  # ── Spec analysis ──
  DOMAIN_FIELD_TYPE="unknown"
  PREDICTED_INSTALL_SUCCESS=true

  SPEC_FILES=$(find "$APP_DIR/api-integrations" -name "*.yaml" -o -name "*.yml" -o -name "*.json" 2>/dev/null || true)
  if [ -n "$SPEC_FILES" ]; then
    for spec in $SPEC_FILES; do
      SERVERS_BLOCK=$(sed -n '/^servers:/,/^[a-z]/p' "$spec" | head -20)
      HAS_VARS=$(echo "$SERVERS_BLOCK" | grep -c 'variables:' || true)
      HAS_DEFAULT=$(echo "$SERVERS_BLOCK" | grep -c 'default:' || true)
      HAS_ENUM=$(echo "$SERVERS_BLOCK" | grep -c 'enum:' || true)

      if [ "$HAS_VARS" -gt 0 ]; then
        if [ "$HAS_ENUM" -gt 0 ]; then
          DOMAIN_FIELD_TYPE="combobox"
          PREDICTED_INSTALL_SUCCESS=false
          printf "  Spec analysis: ${YELLOW}combobox (enum present — can't enter custom domain)${RESET}\n"
        elif [ "$HAS_DEFAULT" -gt 0 ]; then
          DOMAIN_FIELD_TYPE="combobox"
          PREDICTED_INSTALL_SUCCESS=false
          printf "  Spec analysis: ${YELLOW}combobox (default without enum — unusable dropdown)${RESET}\n"
        else
          DOMAIN_FIELD_TYPE="textbox"
          printf "  Spec analysis: ${GREEN}textbox (description only — user can type domain)${RESET}\n"
        fi
      else
        DOMAIN_FIELD_TYPE="none"
        printf "  Spec analysis: no server variables\n"
      fi
    done
  else
    printf "  Spec analysis: ${YELLOW}no spec files found${RESET}\n"
  fi

  # ── Release ──
  RELEASED=false
  if [ "$SKIP_RELEASE" = "1" ]; then
    printf "  Release:       ${YELLOW}skipped (SKIP_RELEASE=1)${RESET}\n"
  elif [ -z "$DEPLOYMENT_ID" ]; then
    printf "  Release:       ${RED}skipped (no deployment)${RESET}\n"
  else
    printf "  Releasing...   "
    RELEASE_OUT=$(cd "$APP_DIR" && foundry apps release --change-type Patch --deployment-id "$DEPLOYMENT_ID" --notes "Automated release from verify-apps.sh" 2>&1) || true
    if echo "$RELEASE_OUT" | grep -qi "success\|release.*in progress\|released\|complete\|already.*released"; then
      RELEASED=true
      printf "${GREEN}done${RESET}\n"
    elif echo "$RELEASE_OUT" | grep -qi "already"; then
      RELEASED=true
      printf "${GREEN}already released${RESET}\n"
    else
      printf "${RED}failed${RESET}\n"
      # Show first meaningful error line
      echo "$RELEASE_OUT" | grep -iE "error|fail|cannot" | head -1 | sed 's/^/  /' || true
    fi
  fi

  # ── Manifest analysis: UI type and workflows ──
  HAS_PAGES=false
  HAS_EXTENSIONS=false
  EXTENSION_SOCKETS=""
  HAS_WORKFLOWS=false

  # Check for non-empty pages (pages: {} is empty, pages:\n  something: is non-empty)
  if grep -qE '^\s+pages:' "$MANIFEST"; then
    PAGES_CONTENT=$(sed -n '/^[[:space:]]*pages:/,/^[[:space:]]*[a-z_]*:/p' "$MANIFEST" | grep -v '^\s*pages:' | grep -v '^\s*{}' | grep -v '^[[:space:]]*[a-z_]*:$' | head -5)
    if [ -n "$PAGES_CONTENT" ] && ! echo "$PAGES_CONTENT" | grep -q '^[[:space:]]*{}$'; then
      # Check it's not just "pages: {}"
      PAGE_NAMES=$(grep -E '^\s{8,12}[a-z]' <<< "$PAGES_CONTENT" 2>/dev/null || true)
      [ -n "$PAGE_NAMES" ] && HAS_PAGES=true
    fi
  fi

  # Check for non-empty extensions
  if grep -qE '^\s+extensions:' "$MANIFEST"; then
    EXT_BLOCK=$(sed -n '/^[[:space:]]*extensions:/,/^[[:space:]]*[a-z]/p' "$MANIFEST")
    if ! echo "$EXT_BLOCK" | grep -q '\[\]'; then
      EXT_NAMES=$(echo "$EXT_BLOCK" | grep -E '^\s+- id:|name:' | head -5)
      if [ -n "$EXT_NAMES" ]; then
        HAS_EXTENSIONS=true
        EXTENSION_SOCKETS=$(grep -A1 'sockets:' "$MANIFEST" | grep -E '^\s+- ' | sed 's/.*- //' | head -1)
      fi
    fi
  fi

  # Check for workflows
  if grep -qE '^workflows:' "$MANIFEST"; then
    WF_ENTRIES=$(sed -n '/^workflows:/,/^[a-z]/p' "$MANIFEST" | grep -E '^\s+- id:' | head -5)
    [ -n "$WF_ENTRIES" ] && HAS_WORKFLOWS=true
  fi

  UI_TYPE="none"
  if [ "$HAS_EXTENSIONS" = true ]; then
    UI_TYPE="extension"
    printf "  UI type:       extension (socket: %s)\n" "${EXTENSION_SOCKETS:-unknown}"
  elif [ "$HAS_PAGES" = true ]; then
    UI_TYPE="page"
    printf "  UI type:       page (with navigation)\n"
  else
    printf "  UI type:       none\n"
  fi
  [ "$HAS_WORKFLOWS" = true ] && printf "  Workflows:     yes\n" || printf "  Workflows:     none\n"

  # ── Build JSON entry ──
  APP_ENTRY=$(jq -n \
    --argjson run "$RUN_NUM" \
    --arg name "$APP_NAME" \
    --arg app_id "$APP_ID" \
    --arg app_dir "$APP_DIR" \
    --arg deployment_id "$DEPLOYMENT_ID" \
    --argjson released "$RELEASED" \
    --arg domain_field_type "$DOMAIN_FIELD_TYPE" \
    --argjson predicted_install_success "$PREDICTED_INSTALL_SUCCESS" \
    --arg ui_type "$UI_TYPE" \
    --arg extension_sockets "${EXTENSION_SOCKETS:-}" \
    --argjson has_workflows "$HAS_WORKFLOWS" \
    '{
      run: $run,
      name: $name,
      app_id: $app_id,
      app_dir: $app_dir,
      deployment_id: $deployment_id,
      released: $released,
      domain_field_type: $domain_field_type,
      predicted_install_success: $predicted_install_success,
      ui_type: $ui_type,
      extension_sockets: $extension_sockets,
      has_workflows: $has_workflows
    }')

  APPS_JSON=$(echo "$APPS_JSON" | jq --argjson entry "$APP_ENTRY" '. + [$entry]')

  printf "\n"
done

# ── Write JSON report ──
jq -n \
  --argjson apps "$APPS_JSON" \
  '{
    apps: $apps,
    phase1_completed: true,
    phase2_completed: false
  }' > "$REPORT_FILE"

printf "${GREEN}JSON report written: %s${RESET}\n\n" "$REPORT_FILE"

# Set APP_COUNT for use in functions and Phase 2
APP_COUNT=$(echo "$APPS_JSON" | jq 'length')

# ── Phase 1 summary table ──
printf "${BLUE}==========================================${RESET}\n"
printf "${BLUE}  Phase 1 Summary${RESET}\n"
printf "${BLUE}==========================================${RESET}\n"

printf "  %-5s %-25s %-10s %-12s %-10s\n" "Run" "App Name" "Released" "Spec Type" "Predicted"
printf "  %-5s %-25s %-10s %-12s %-10s\n" "---" "--------" "--------" "---------" "---------"

echo "$APPS_JSON" | jq -r '.[] | "\(.run)|\(.name)|\(.released)|\(.domain_field_type)|\(.predicted_install_success)"' | \
while IFS='|' read -r run name released dtype predicted; do
  rel_icon="$( [ "$released" = "true" ] && echo "✅" || echo "❌" )"
  pred_icon="$( [ "$predicted" = "true" ] && echo "✅" || echo "⚠️ " )"
  printf "  %-5s %-25s %-10s %-12s %-10s\n" "$run" "$name" "$rel_icon" "$dtype" "$pred_icon"
done

printf "\n"

# ── Skill enhancement advice function (Phase 1 findings) ───────
print_phase1_advice() {
  printf "${BLUE}==========================================${RESET}\n"
  printf "${BLUE}  SKILL ENHANCEMENT ADVICE${RESET}\n"
  printf "${BLUE}==========================================${RESET}\n\n"

  local advice_count=0

  # Analyze spec issues across all apps
  local combobox_count=0
  local textbox_count=0
  for idx in $(seq 0 $((APP_COUNT - 1))); do
    local dtype
    dtype=$(echo "$APPS_JSON" | jq -r ".[$idx].domain_field_type")
    case "$dtype" in
      combobox) combobox_count=$((combobox_count + 1)) ;;
      textbox)  textbox_count=$((textbox_count + 1)) ;;
    esac
  done

  if [ "$combobox_count" -gt 0 ]; then
    advice_count=$((advice_count + 1))
    printf "  ${YELLOW}%d. Server variable 'default' causes unusable install UI${RESET}\n" "$advice_count"
    printf "     %d/%d apps have server variables with 'default' (renders as dropdown).\n" "$combobox_count" "$APP_COUNT"
    printf "     The install UI shows a combobox with one placeholder — users can't type a custom domain.\n"
    printf "     ${GREEN}Fix:${RESET} Remove 'default:' from server variables in the OpenAPI spec.\n"
    printf "     Keep only 'description:' under each variable name.\n"
    printf "     ${CYAN}Skill file:${RESET} api-integrations — add validation rule to server variable guidance.\n"
    printf "     ${CYAN}Hook file:${RESET} foundry-skill-router.sh already blocks this — ensure the skill teaches it too.\n\n"
  fi

  if [ "$textbox_count" -eq "$APP_COUNT" ] && [ "$APP_COUNT" -gt 0 ]; then
    printf "  ${GREEN}  Server variable spec pattern is correct across all %d apps.${RESET}\n\n" "$APP_COUNT"
  fi

  # Check if any apps failed to deploy
  local no_deploy_count=0
  for idx in $(seq 0 $((APP_COUNT - 1))); do
    local did
    did=$(echo "$APPS_JSON" | jq -r ".[$idx].deployment_id")
    [ -z "$did" ] && no_deploy_count=$((no_deploy_count + 1))
  done

  if [ "$no_deploy_count" -gt 0 ]; then
    advice_count=$((advice_count + 1))
    printf "  ${YELLOW}%d. %d/%d apps have no deployment${RESET}\n" "$advice_count" "$no_deploy_count" "$APP_COUNT"
    printf "     Apps without deployments can't be released or installed.\n"
    printf "     ${GREEN}Fix:${RESET} Ensure the skill always runs 'foundry apps deploy' after scaffolding.\n"
    printf "     ${CYAN}Skill file:${RESET} development-workflow — verify deploy step is mandatory.\n\n"
  fi

  # Check if any releases failed
  local no_release_count=0
  for idx in $(seq 0 $((APP_COUNT - 1))); do
    local rel
    rel=$(echo "$APPS_JSON" | jq -r ".[$idx].released")
    [ "$rel" != "true" ] && no_release_count=$((no_release_count + 1))
  done

  if [ "$no_release_count" -gt 0 ] && [ "$SKIP_RELEASE" != "1" ]; then
    advice_count=$((advice_count + 1))
    printf "  ${YELLOW}%d. %d/%d apps failed to release${RESET}\n" "$advice_count" "$no_release_count" "$APP_COUNT"
    printf "     Released apps are required for installation from the App Catalog.\n"
    printf "     ${GREEN}Fix:${RESET} Add 'foundry apps release --change-type Patch --deployment-id <id>' to the skill's deployment steps.\n"
    printf "     ${CYAN}Skill file:${RESET} development-workflow — add release as a post-deploy step.\n\n"
  fi

  if [ "$advice_count" -eq 0 ]; then
    printf "  ${GREEN}No issues detected from Phase 1 analysis.${RESET}\n\n"
  else
    printf "  ${BOLD}Total Phase 1 recommendations: %d${RESET}\n\n" "$advice_count"
  fi
}

# ── Skill enhancement advice function (Phase 2 findings) ───────
print_phase2_advice() {
  local report_block="$1"
  local advice_count=0

  printf "${BLUE}  Phase 2 Advice (Browser Results)${RESET}\n"
  printf "${BLUE}  ──────────────────────────────────${RESET}\n\n"

  # Count failures for a given status type
  count_failures() {
    local status_type="$1"
    local count=0
    for idx in $(seq 0 $((APP_COUNT - 1))); do
      local app_run app_name status
      app_run=$(echo "$APPS_JSON" | jq -r ".[$idx].run")
      app_name=$(echo "$APPS_JSON" | jq -r ".[$idx].name")
      status=$(parse_app_status "$app_run" "$status_type" "$report_block" "$app_name")
      echo "$status" | grep -qi "FAIL" && count=$((count + 1))
    done
    echo "$count"
  }

  # Check install failures
  local install_fail_count
  install_fail_count=$(count_failures "install")

  if [ "$install_fail_count" -gt 0 ]; then
    advice_count=$((advice_count + 1))
    printf "  ${YELLOW}%d. %d/%d apps failed to install${RESET}\n" "$advice_count" "$install_fail_count" "$APP_COUNT"
    printf "     Install failures typically stem from spec issues (combobox fields, invalid auth config).\n"
    printf "     ${GREEN}Fix:${RESET} Cross-reference with spec analysis above. Combobox fields are the #1 cause.\n"
    printf "     ${CYAN}Skill file:${RESET} api-integrations — strengthen server variable validation.\n\n"
  fi

  # Check UI failures
  local ui_fail_count
  ui_fail_count=$(count_failures "ui")

  if [ "$ui_fail_count" -gt 0 ]; then
    advice_count=$((advice_count + 1))
    printf "  ${YELLOW}%d. %d/%d apps show UI errors or empty state${RESET}\n" "$advice_count" "$ui_fail_count" "$APP_COUNT"
    printf "     UI failures may indicate: missing API credentials, incorrect API call patterns,\n"
    printf "     or UI component errors (e.g., wrong data binding).\n"
    printf "     ${GREEN}Fix:${RESET} Check if the UI extension correctly calls the API integration endpoint.\n"
    printf "     ${CYAN}Skill file:${RESET} ui-development — verify API call patterns in extensions.\n\n"
  fi

  # Check workflow failures
  local wf_fail_count
  wf_fail_count=$(count_failures "workflow")

  if [ "$wf_fail_count" -gt 0 ]; then
    advice_count=$((advice_count + 1))
    printf "  ${YELLOW}%d. %d/%d workflow executions failed${RESET}\n" "$advice_count" "$wf_fail_count" "$APP_COUNT"
    printf "     Workflow failures may indicate: incorrect action references, missing trigger config,\n"
    printf "     or YAML syntax issues (mustache vs \$ variable syntax).\n"
    printf "     ${GREEN}Fix:${RESET} Verify workflow YAML uses \$ prefix for variables, not {{mustache}}.\n"
    printf "     ${CYAN}Skill file:${RESET} workflows-development — strengthen variable syntax guidance.\n\n"
  fi

  if [ "$advice_count" -eq 0 ]; then
    printf "  ${GREEN}No additional issues from browser verification.${RESET}\n\n"
  else
    printf "  ${BOLD}Total Phase 2 recommendations: %d${RESET}\n\n" "$advice_count"
  fi
}
if [ "$SKIP_BROWSER" = "1" ]; then
  print_phase1_advice
  printf "${YELLOW}Phase 2 skipped (SKIP_BROWSER=1).${RESET}\n"
  printf "To run browser verification:\n"
  printf "  OKTA_DOMAIN=... OKTA_API_KEY=... ./verify-apps.sh\n"
  exit 0
fi

# Credential prompts (interactive) or validation
if [ -z "${OKTA_DOMAIN:-}" ]; then
  printf "${YELLOW}Okta domain not set.${RESET}\n"
  read -rp "  Enter Okta domain (e.g. your-org.okta.com): " OKTA_DOMAIN
  if [ -z "$OKTA_DOMAIN" ]; then
    printf "${RED}No domain provided. Exiting.${RESET}\n" >&2
    exit 1
  fi
fi

if [ -z "${OKTA_API_KEY:-}" ]; then
  printf "${YELLOW}Okta API key not set.${RESET}\n"
  read -rsp "  Enter Okta API key: " OKTA_API_KEY
  printf "\n"
  if [ -z "$OKTA_API_KEY" ]; then
    printf "${RED}No API key provided. Exiting.${RESET}\n" >&2
    exit 1
  fi
fi

printf "${BLUE}==========================================${RESET}\n"
printf "${BLUE}  VERIFY-APPS — Phase 2: Browser${RESET}\n"
printf "${BLUE}==========================================${RESET}\n"
printf "  Falcon URL:    %s\n" "$FALCON_URL"
printf "  Okta domain:   %s\n" "$OKTA_DOMAIN"
printf "  Okta instance: %s\n" "$OKTA_INSTANCE"
printf "\n"

# Ensure user is ready to log into Falcon console when browser opens
printf "${YELLOW}Phase 2 will open a browser and navigate to the Falcon console.${RESET}\n"
printf "  You'll need to log in manually when the SSO page appears.\n"
read -rp "  Ready to proceed? (Y/n): " ready
if [[ "$ready" =~ ^[Nn]$ ]]; then
  printf "\n  Re-run when ready.\n"
  exit 0
fi
printf "\n"

# ── Build Phase 2 prompt ────────────────────────────────────────
# Read the report and construct instructions for each app
APP_INSTRUCTIONS=""
APP_COUNT=$(echo "$APPS_JSON" | jq 'length')

for idx in $(seq 0 $((APP_COUNT - 1))); do
  APP=$(echo "$APPS_JSON" | jq ".[$idx]")
  APP_NAME=$(echo "$APP" | jq -r '.name')
  APP_RUN=$(echo "$APP" | jq -r '.run')
  DTYPE=$(echo "$APP" | jq -r '.domain_field_type')
  PREDICTED=$(echo "$APP" | jq -r '.predicted_install_success')
  UI_TYPE=$(echo "$APP" | jq -r '.ui_type')
  EXT_SOCKETS=$(echo "$APP" | jq -r '.extension_sockets')
  HAS_WF=$(echo "$APP" | jq -r '.has_workflows')

  DOMAIN_INSTRUCTIONS=""
  if [ "$DTYPE" = "textbox" ] || [ "$DTYPE" = "none" ]; then
    DOMAIN_INSTRUCTIONS="The domain field is a textbox — type '${OKTA_DOMAIN}' into it."
  else
    DOMAIN_INSTRUCTIONS="The domain field is a combobox/dropdown (default without enum). It may show a placeholder value you cannot edit. Try selecting the existing option or typing the domain. If you cannot enter a custom value, note 'INSTALL: FAILED (combobox field)' and proceed to uninstall."
  fi

  # Build UI verification instructions based on manifest content
  UI_INSTRUCTIONS=""
  if [ "$UI_TYPE" = "extension" ]; then
    # Map socket ID to navigation path and interaction steps
    SOCKET_NAV=""
    SOCKET_INTERACT=""
    case "$EXT_SOCKETS" in
      activity.detections.details)
        SOCKET_NAV="Endpoint security → Endpoint detections"
        SOCKET_INTERACT="Wait for the detections table to load. Click on the first detection button in the table row to open the details panel. Wait 3-5 seconds for socket extensions to load."
        ;;
      hosts.host.panel)
        SOCKET_NAV="Endpoint security → Host management"
        SOCKET_INTERACT="Click on the first host row (second column to avoid checkbox) to open the 'Host information' side panel. Scroll to the bottom of the panel (press End key twice) to reveal extension panels."
        ;;
      xdr.cases.panel|ngsiem.workbench.details)
        SOCKET_NAV="Next-Gen SIEM → Cases"
        SOCKET_INTERACT="Click on the first case, then click 'See full case' to open the Workbench. Click 'Search on graph', type 'e', and click the first result to select a node and reveal extension panels."
        ;;
      automated-leads.leads.details)
        SOCKET_NAV="Next-Gen SIEM → Automated leads"
        SOCKET_INTERACT="Click on the first lead to open the details panel."
        ;;
      workflows.executions.execution.details)
        SOCKET_NAV="Falcon Fusion SOAR → Workflows"
        SOCKET_INTERACT="Find a recent workflow execution and click on it to open details."
        ;;
      *)
        SOCKET_NAV="the console area where socket '${EXT_SOCKETS}' appears"
        SOCKET_INTERACT="Open a detail view to reveal the extension panel."
        ;;
    esac

    UI_INSTRUCTIONS="2. **Verify UI (Extension on ${EXT_SOCKETS})**
   - Open the hamburger menu
   - Navigate: ${SOCKET_NAV}
   - Wait for the page to load
   - ${SOCKET_INTERACT}
   - Look for the extension panel labeled '${APP_NAME}' or similar (may be a collapsible section or tab in the details sidebar)
   - If you see the extension panel (even if empty or showing an error fetching data), note 'UI: PASS'
   - If no extension panel appears after waiting, note 'UI: FAIL (extension not visible in socket)'
   - Take a screenshot showing the details view with the extension panel"
  elif [ "$UI_TYPE" = "page" ]; then
    UI_INSTRUCTIONS="2. **Verify UI (App Page)**
   - After install, look for the app in Custom Apps (hamburger menu → Falcon Foundry → Custom Apps) or check for a 'Launch' / 'Open' button on the app details page
   - Look for a table or list showing Okta user data (names, emails, statuses)
   - Take a screenshot of the UI showing data (or error state)
   - If you see user data or the page renders correctly, note 'UI: PASS'. If error or empty, note 'UI: FAIL' with the error."
  else
    UI_INSTRUCTIONS="2. **Verify UI**
   - This app has no UI pages or extensions. Note 'UI: SKIP (no UI in manifest)'"
  fi

  # Build workflow instructions based on manifest
  WF_INSTRUCTIONS=""
  if [ "$HAS_WF" = "true" ]; then
    WF_INSTRUCTIONS="3. **Workflow Verify**
   - Navigate to: Falcon Fusion SOAR (via hamburger menu → Falcon Fusion SOAR → Workflows)
   - Look for a workflow template associated with '${APP_NAME}' (may be called 'list-users', 'okta-users', 'list-okta-users', or similar)
   - If the workflow is a template (not yet provisioned), click 'Import' or 'Provision' to create an instance
   - If the workflow has an on-demand trigger, execute it and check the execution log
   - The listUsers API action should succeed. Email send may fail (example.com) — that is expected.
   - If there is no way to execute (no on-demand trigger, or workflow not found), note what you see
   - Take a screenshot of workflow results
   - Note 'WORKFLOW: PASS' if the API action succeeded, 'WORKFLOW: FAIL' if it failed, or 'WORKFLOW: SKIP (not found/not executable)'"
  else
    WF_INSTRUCTIONS="3. **Workflow Verify**
   - This app has no workflows in the manifest. Note 'WORKFLOW: SKIP (no workflows in manifest)'"
  fi

  APP_INSTRUCTIONS="${APP_INSTRUCTIONS}
### App ${APP_RUN}: ${APP_NAME}

1. **Install**
   - Navigate to: Falcon Foundry (via hamburger menu) → App catalog
   - Search for '${APP_NAME}' or scroll to find it
   - Click on the app card, then click 'Install' or 'Install now'
   - Fill in the configuration fields:
     - Name: '${OKTA_INSTANCE}'
     - ${DOMAIN_INSTRUCTIONS}
     - API Key: type the Okta API key (it is a password/secret field)
   - If there is a 'Next setting' button, click it and fill any additional fields the same way
   - Click 'Install app' to complete installation
   - Wait for the 'Installed' badge or success indication
   - Take a screenshot after installation completes

${UI_INSTRUCTIONS}

${WF_INSTRUCTIONS}

4. **Uninstall**
   - Navigate back to: Falcon Foundry → App catalog
   - Find '${APP_NAME}', click on it
   - Click the three-dot menu (or kebab menu) and select 'Uninstall'
   - Confirm the uninstall dialog
   - Wait for the 'Install now' link to appear (confirms uninstall complete)
   - Note 'UNINSTALL: PASS' or 'UNINSTALL: FAIL'
"
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERIFY_SCHEMA=$(cat "$SCRIPT_DIR/verify-result-schema.json")

BROWSER_PROMPT="You are verifying Foundry apps in the CrowdStrike Falcon console.

## Login
- First, navigate to ${FALCON_URL}
- If you see a login page or SSO redirect, DO NOT give up. The user will log in manually in the browser window.
- Poll every 15 seconds (up to 3 minutes) by taking a browser_snapshot and checking for dashboard elements like a 'Menu' button, 'Dashboard', or any Falcon console navigation.
- Only proceed once you confirm the user is logged in and on the Falcon console.

## Important Browser Interaction Guidelines
- Use browser_snapshot (not screenshots) for element discovery and interaction
- Use menu-based navigation (hamburger menu), NOT direct URLs — the Falcon console redirects unreliably
- Wait for page loads between navigation steps (use browser_wait_for or brief delays)
- For the App Catalog: Menu → Falcon Foundry → App catalog
- For Fusion SOAR: Menu → Falcon Fusion SOAR → Workflows
- Take screenshots at key verification points for evidence

## Credentials
- Okta Instance Name: ${OKTA_INSTANCE}
- Okta Domain: ${OKTA_DOMAIN}
- Okta API Key: ${OKTA_API_KEY}

## Apps to verify (${APP_COUNT} total)
${APP_INSTRUCTIONS}

## Output Format
After verifying all apps, respond with valid JSON matching this schema:
${VERIFY_SCHEMA}

Example for 2 apps:
{\"apps\":[{\"app_name\":\"okta-user-manager\",\"run\":1,\"install\":\"PASS\",\"ui\":\"PASS\",\"workflow\":\"PASS\",\"uninstall\":\"PASS\",\"notes\":\"All checks passed\"},{\"app_name\":\"okta-user-mgr\",\"run\":2,\"install\":\"PASS\",\"ui\":\"FAIL\",\"workflow\":\"SKIP\",\"uninstall\":\"PASS\",\"notes\":\"UI extension not found on detection details\"}],\"summary\":\"1/2 apps passed all checks\"}"

LOG_FILE="$BASE_DIR/verify-browser.log"
printf "  Launching browser verification...\n"
printf "  Log: %s\n\n" "$LOG_FILE"

env -u CLAUDECODE claude -p "$BROWSER_PROMPT" \
  --dangerously-skip-permissions \
  --model claude-4-6-opus \
  --verbose \
  --output-format stream-json \
  > "$LOG_FILE" 2>&1 || true

# ── Phase 2 output parsing ──────────────────────────────────────
printf "\n${BLUE}==========================================${RESET}\n"
printf "${BLUE}  Phase 2 Results${RESET}\n"
printf "${BLUE}==========================================${RESET}\n\n"

# Extract text from stream-json (same pattern as test-skill.sh)
TEXT_FILE="$BASE_DIR/verify-browser.text"
grep -o '{"type":"assistant".*' "$LOG_FILE" 2>/dev/null | \
  jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text' 2>/dev/null > "$TEXT_FILE" || true

# Extract JSON verification report from browser agent output
REPORT_JSON=""
if [ -s "$TEXT_FILE" ]; then
  REPORT_JSON=$(python3 -c "
import sys, json

text = open(sys.argv[1]).read()

def find_apps(obj):
    \"\"\"Recursively find an 'apps' or 'results' list in a parsed JSON object.\"\"\"
    if isinstance(obj, dict):
        for key in ('apps', 'results'):
            if key in obj and isinstance(obj[key], list) and len(obj[key]) > 0:
                first = obj[key][0]
                if isinstance(first, dict) and ('install' in first or 'ui' in first or 'ui_extension' in first):
                    return obj[key]
        for v in obj.values():
            result = find_apps(v)
            if result is not None:
                return result
    return None

def normalize(apps):
    \"\"\"Normalize field names to match verify-result-schema.json.\"\"\"
    out = []
    for a in apps:
        entry = {}
        entry['app_name'] = a.get('app_name') or a.get('name', '')
        entry['run'] = a.get('run', 0)
        entry['install'] = a.get('install', 'N/A')
        entry['ui'] = a.get('ui') or a.get('ui_extension', 'N/A')
        entry['workflow'] = a.get('workflow', 'N/A')
        entry['uninstall'] = a.get('uninstall', 'N/A')
        if 'notes' in a:
            entry['notes'] = a['notes']
        out.append(entry)
    return out

# Try parsing JSON from every '{' — handles nested structures and pretty-printed output
for i, ch in enumerate(text):
    if ch != '{':
        continue
    # Use raw_decode to parse exactly one JSON value starting at position i
    try:
        obj, end = json.JSONDecoder().raw_decode(text, i)
    except (json.JSONDecodeError, ValueError):
        continue
    if not isinstance(obj, dict):
        continue
    apps = find_apps(obj)
    if apps:
        summary = ''
        if isinstance(obj.get('summary'), str):
            summary = obj['summary']
        elif isinstance(obj.get('summary'), dict):
            summary = obj['summary'].get('known_issues', str(obj['summary']))
        print(json.dumps({'apps': normalize(apps), 'summary': summary}))
        break
" "$TEXT_FILE" 2>/dev/null || true)
fi

if [ -n "$REPORT_JSON" ]; then
  echo "$REPORT_JSON" | jq . 2>/dev/null
else
  # Fall back to old marker-based extraction for backwards compatibility
  REPORT_BLOCK=""
  if grep -q "VERIFY_REPORT_START" "$TEXT_FILE" 2>/dev/null; then
    REPORT_BLOCK=$(sed -n '/VERIFY_REPORT_START/,/VERIFY_REPORT_END/p' "$TEXT_FILE" | grep -v "VERIFY_REPORT")
  fi
  if [ -n "$REPORT_BLOCK" ]; then
    echo "$REPORT_BLOCK"
  else
    printf "${YELLOW}  No verification results found in output.${RESET}\n"
    printf "  Check log: %s\n" "$LOG_FILE"
    tail -20 "$TEXT_FILE" 2>/dev/null | head -10 || true
  fi
fi

# ── Parse per-app results ──
# JSON path: .apps[] | select(.app_name == "name") | .install/.ui/.workflow/.uninstall
# Falls back to old text-based parsing if no JSON found
parse_app_status() {
  local run="$1" field="$2" json="$3" name="${4:-}"
  local result=""
  # Try JSON extraction first
  if echo "$json" | jq -e '.apps' > /dev/null 2>&1; then
    result=$(echo "$json" | jq -r --arg name "$name" --arg field "$field" \
      '.apps[] | select(.app_name == $name) | .[$field] // empty' 2>/dev/null)
  fi
  echo "${result:-N/A}"
}

# ── Combined scorecard ──────────────────────────────────────────
printf "\n${BLUE}==========================================${RESET}\n"
printf "${BLUE}  VERIFY-APPS SCORECARD${RESET}\n"
printf "${BLUE}==========================================${RESET}\n"

FULLY_VERIFIED=0
TOTAL_APPS=$APP_COUNT

for idx in $(seq 0 $((APP_COUNT - 1))); do
  APP=$(echo "$APPS_JSON" | jq ".[$idx]")
  APP_NAME=$(echo "$APP" | jq -r '.name')
  APP_RUN=$(echo "$APP" | jq -r '.run')
  RELEASED=$(echo "$APP" | jq -r '.released')
  DTYPE=$(echo "$APP" | jq -r '.domain_field_type')

  REL_ICON="$( [ "$RELEASED" = "true" ] && echo "✅" || echo "❌" )"
  SPEC_LABEL="$DTYPE"
  [ "$DTYPE" = "textbox" ] && SPEC_LABEL="${DTYPE} (good)"
  [ "$DTYPE" = "combobox" ] && SPEC_LABEL="${DTYPE} (⚠️  enum/default)"

  # Parse browser results from JSON or fallback
  INSTALL_STATUS="N/A"
  UI_STATUS="N/A"
  WF_STATUS="N/A"
  UNINST_STATUS="N/A"

  PARSE_DATA="${REPORT_JSON:-}"
  if [ -n "$PARSE_DATA" ]; then
    INSTALL_STATUS=$(parse_app_status "$APP_RUN" "install" "$PARSE_DATA" "$APP_NAME")
    UI_STATUS=$(parse_app_status "$APP_RUN" "ui" "$PARSE_DATA" "$APP_NAME")
    WF_STATUS=$(parse_app_status "$APP_RUN" "workflow" "$PARSE_DATA" "$APP_NAME")
    UNINST_STATUS=$(parse_app_status "$APP_RUN" "uninstall" "$PARSE_DATA" "$APP_NAME")
  fi

  # Status to icon
  status_icon() {
    local s="$1"
    if echo "$s" | grep -qi "PASS"; then echo "✅"
    elif echo "$s" | grep -qi "SKIP"; then echo "⏭️ "
    elif echo "$s" | grep -qi "N/A"; then echo "—"
    else echo "❌"
    fi
  }

  inst_icon=$(status_icon "$INSTALL_STATUS")
  ui_icon=$(status_icon "$UI_STATUS")
  wf_icon=$(status_icon "$WF_STATUS")
  uninst_icon=$(status_icon "$UNINST_STATUS")

  [ "$SKIP_BROWSER" = "1" ] && inst_icon="—" && ui_icon="—" && wf_icon="—" && uninst_icon="—"

  printf "\n  ${BOLD}Run %s (%s):${RESET}\n" "$APP_RUN" "$APP_NAME"
  printf "    Release:   %s     Spec: %s\n" "$REL_ICON" "$SPEC_LABEL"
  printf "    Install:   %s     UI: %s\n" "$inst_icon" "$ui_icon"
  printf "    Workflow:  %s     Uninstall: %s\n" "$wf_icon" "$uninst_icon"

  # Count fully verified (all PASS)
  if echo "$INSTALL_STATUS" | grep -qi "PASS" && \
     echo "$UI_STATUS" | grep -qi "PASS" && \
     echo "$UNINST_STATUS" | grep -qi "PASS"; then
    FULLY_VERIFIED=$((FULLY_VERIFIED + 1))
  fi
done

printf "\n  ${BOLD}Overall: %d/%d fully verified${RESET}\n" "$FULLY_VERIFIED" "$TOTAL_APPS"
printf "${BLUE}==========================================${RESET}\n"
printf "\n  Phase 1 report: %s\n" "$REPORT_FILE"
[ "$SKIP_BROWSER" != "1" ] && printf "  Browser log:    %s\n" "$LOG_FILE"
printf "\n"

# Update JSON report with phase2 status
if [ "$SKIP_BROWSER" != "1" ]; then
  jq --argjson p2 true '.phase2_completed = $p2' "$REPORT_FILE" > "${REPORT_FILE}.tmp"
  mv "${REPORT_FILE}.tmp" "$REPORT_FILE"
fi

# ── Print advice ──
ADVICE_LOG="$BASE_DIR/verify-advice.log"
{
  print_phase1_advice
  if [ -n "${REPORT_JSON:-}" ]; then
    print_phase2_advice "$REPORT_JSON"
  fi
} 2>&1 | tee "$ADVICE_LOG"
printf "  Advice log: %s\n" "$ADVICE_LOG"
