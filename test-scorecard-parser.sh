#!/usr/bin/env bash
#
# test-scorecard-parser.sh — Unit tests for verify-apps.sh scorecard parsing
#
# Tests the parse_app_status function against JSON verification reports.
# Fast, no API calls needed.
#
# Usage: ./test-scorecard-parser.sh
#
set -euo pipefail

PASS=0
FAIL=0
TOTAL=0

GREEN='\033[0;32m'
RED='\033[0;31m'
BOLD='\033[1m'
RESET='\033[0m'

# ── parse_app_status: matches production code in verify-apps.sh ──
parse_app_status() {
  local run="$1" field="$2" json="$3" name="${4:-}"
  local result=""
  if echo "$json" | jq -e '.apps' > /dev/null 2>&1; then
    result=$(echo "$json" | jq -r --arg name "$name" --arg field "$field" \
      '.apps[] | select(.app_name == $name) | .[$field] // empty' 2>/dev/null)
  fi
  echo "${result:-N/A}"
}

# ── Test helpers ──
assert_eq() {
  local test_name="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf "${RED}  FAIL: %s${RESET}\n" "$test_name"
    printf "    expected: '%s'\n" "$expected"
    printf "    actual:   '%s'\n" "$actual"
  fi
}

# ── count_over_apps: matches the advice loops in verify-apps.sh ──
# The C-style form must not iterate when APP_COUNT is 0. The earlier
# `seq 0 $((APP_COUNT - 1))` form emitted "0" and "-1", so a zero-app
# report counted two phantom failures against a total of 0 ("2/0 apps
# failed to release") and printed "App null: null" scorecard rows.
count_over_apps() {
  local app_count="$1" json="$2" field="$3" expected="$4"
  local n=0
  for ((idx=0; idx<app_count; idx++)); do
    local val
    val=$(echo "$json" | jq -r ".[$idx].$field")
    [ "$val" != "$expected" ] && n=$((n + 1))
  done
  echo "$n"
}

# ══════════════════════════════════════════════════════════════
# JSON format: all fields present, all PASS
# ══════════════════════════════════════════════════════════════
printf "${BOLD}JSON: Basic parsing (all PASS)${RESET}\n"

ALL_PASS_JSON='{"apps":[
  {"app_name":"okta-user-manager","run":1,"install":"PASS","ui":"PASS","workflow":"PASS","uninstall":"PASS","notes":"All checks passed"},
  {"app_name":"okta-user-mgr","run":2,"install":"PASS","ui":"PASS","workflow":"PASS","uninstall":"PASS","notes":"All checks passed"}
],"summary":"2/2 apps passed all checks"}'

assert_eq "json: app1 install" "PASS" "$(parse_app_status 1 install "$ALL_PASS_JSON" "okta-user-manager")"
assert_eq "json: app1 ui" "PASS" "$(parse_app_status 1 ui "$ALL_PASS_JSON" "okta-user-manager")"
assert_eq "json: app1 workflow" "PASS" "$(parse_app_status 1 workflow "$ALL_PASS_JSON" "okta-user-manager")"
assert_eq "json: app1 uninstall" "PASS" "$(parse_app_status 1 uninstall "$ALL_PASS_JSON" "okta-user-manager")"
assert_eq "json: app2 install" "PASS" "$(parse_app_status 2 install "$ALL_PASS_JSON" "okta-user-mgr")"

# ══════════════════════════════════════════════════════════════
# JSON format: mixed results (PASS, FAIL, SKIP)
# ══════════════════════════════════════════════════════════════
printf "${BOLD}JSON: Mixed results (PASS, FAIL, SKIP)${RESET}\n"

MIXED_JSON='{"apps":[
  {"app_name":"okta-user-manager","run":1,"install":"PASS","ui":"PASS","workflow":"PASS","uninstall":"PASS"},
  {"app_name":"okta-user-mgr","run":2,"install":"FAIL","ui":"PASS","workflow":"SKIP","uninstall":"PASS","notes":"Install failed: combobox field"},
  {"app_name":"okta-user-dir","run":3,"install":"PASS","ui":"FAIL","workflow":"PASS","uninstall":"PASS","notes":"UI extension not found"}
],"summary":"1/3 apps passed all checks"}'

assert_eq "json: app2 install FAIL" "FAIL" "$(parse_app_status 2 install "$MIXED_JSON" "okta-user-mgr")"
assert_eq "json: app2 workflow SKIP" "SKIP" "$(parse_app_status 2 workflow "$MIXED_JSON" "okta-user-mgr")"
assert_eq "json: app3 ui FAIL" "FAIL" "$(parse_app_status 3 ui "$MIXED_JSON" "okta-user-dir")"
assert_eq "json: app3 install PASS" "PASS" "$(parse_app_status 3 install "$MIXED_JSON" "okta-user-dir")"

# ══════════════════════════════════════════════════════════════
# JSON format: similar app names (no greedy matching)
# ══════════════════════════════════════════════════════════════
printf "${BOLD}JSON: Similar app names${RESET}\n"

SIMILAR_JSON='{"apps":[
  {"app_name":"okta-integration","run":1,"install":"PASS","ui":"PASS","workflow":"PASS","uninstall":"PASS"},
  {"app_name":"okta-integration-ab","run":2,"install":"FAIL","ui":"FAIL","workflow":"FAIL","uninstall":"FAIL"}
],"summary":"1/2 passed"}'

assert_eq "json: exact name match" "PASS" "$(parse_app_status 1 install "$SIMILAR_JSON" "okta-integration")"
assert_eq "json: suffix name match" "FAIL" "$(parse_app_status 2 install "$SIMILAR_JSON" "okta-integration-ab")"

# ══════════════════════════════════════════════════════════════
# JSON format: 5 apps (typical A/B test run)
# ══════════════════════════════════════════════════════════════
printf "${BOLD}JSON: 5-app A/B test${RESET}\n"

FIVE_APP_JSON='{"apps":[
  {"app_name":"okta-user-manager","run":1,"install":"PASS","ui":"PASS","workflow":"PASS","uninstall":"PASS"},
  {"app_name":"okta-user-mgr","run":2,"install":"PASS","ui":"PASS","workflow":"PASS","uninstall":"PASS"},
  {"app_name":"okta-user-manager-ab3","run":3,"install":"PASS","ui":"PASS","workflow":"PASS","uninstall":"PASS"},
  {"app_name":"okta-user-directory","run":4,"install":"PASS","ui":"PASS","workflow":"PASS","uninstall":"PASS"},
  {"app_name":"okta-user-dir-1820","run":5,"install":"PASS","ui":"PASS","workflow":"PASS","uninstall":"PASS"}
],"summary":"5/5 apps passed all checks"}'

assert_eq "json: run1" "PASS" "$(parse_app_status 1 install "$FIVE_APP_JSON" "okta-user-manager")"
assert_eq "json: run3" "PASS" "$(parse_app_status 3 workflow "$FIVE_APP_JSON" "okta-user-manager-ab3")"
assert_eq "json: run5" "PASS" "$(parse_app_status 5 uninstall "$FIVE_APP_JSON" "okta-user-dir-1820")"

# ══════════════════════════════════════════════════════════════
# N/A fallback: app not found or empty input
# ══════════════════════════════════════════════════════════════
printf "${BOLD}N/A fallback${RESET}\n"

assert_eq "missing: nonexistent app" "N/A" "$(parse_app_status 1 install "$ALL_PASS_JSON" "nonexistent-app")"
assert_eq "missing: empty json" "N/A" "$(parse_app_status 1 install "" "my-app")"
assert_eq "missing: invalid json" "N/A" "$(parse_app_status 1 install "not json at all" "my-app")"
assert_eq "missing: no apps key" "N/A" "$(parse_app_status 1 install '{"foo":"bar"}' "my-app")"

# ══════════════════════════════════════════════════════════════
# Optional notes field
# ══════════════════════════════════════════════════════════════
printf "${BOLD}JSON: Notes field${RESET}\n"

assert_eq "json: notes present" "Install failed: combobox field" "$(parse_app_status 2 notes "$MIXED_JSON" "okta-user-mgr")"
assert_eq "json: notes absent" "N/A" "$(parse_app_status 1 notes "$MIXED_JSON" "okta-user-manager")"

# ══════════════════════════════════════════════════════════════
# Zero-app advice loops (regression: "2/0 apps failed to release")
# ══════════════════════════════════════════════════════════════
printf "${BOLD}Zero-app advice loops${RESET}\n"

assert_eq "zero apps: no phantom release failures" "0" "$(count_over_apps 0 '[]' released true)"
assert_eq "zero apps: no phantom deploy failures" "0" "$(count_over_apps 0 '[]' deployment_id abc)"
assert_eq "one app: counts a real failure" "1" "$(count_over_apps 1 '[{"released":false}]' released true)"
assert_eq "one app: counts a real pass" "0" "$(count_over_apps 1 '[{"released":true}]' released true)"
assert_eq "two apps: counts only the failure" "1" "$(count_over_apps 2 '[{"released":true},{"released":false}]' released true)"

# ══════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════
echo ""
printf "${BOLD}=========================================${RESET}\n"
if [ "$FAIL" -eq 0 ]; then
  printf "${GREEN}  ALL %d TESTS PASSED${RESET}\n" "$TOTAL"
else
  printf "${RED}  %d/%d FAILED${RESET}\n" "$FAIL" "$TOTAL"
fi
printf "${BOLD}=========================================${RESET}\n"

exit "$FAIL"
