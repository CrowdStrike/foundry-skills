#!/usr/bin/env bash
#
# test-skill-scoring.sh — Unit tests for the token, cost, and reference-doc
# scoring in test-skill.sh
#
# Loads the functions straight from test-skill.sh, so these tests can't drift
# from the code they cover. Fast, no API calls needed.
#
# Usage: ./test-skill-scoring.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
eval "$(sed -n -e '/^get_tokens() {/,/^}/p' -e '/^get_cost() {/,/^}/p' \
  -e '/^list_reference_docs() {/,/^}/p' "$SCRIPT_DIR/test-skill.sh")"

PASS=0
FAIL=0
TOTAL=0

GREEN='\033[0;32m'
RED='\033[0;31m'
BOLD='\033[1m'
RESET='\033[0m'

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

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

# ══════════════════════════════════════════════════════════════
# get_tokens / get_cost
# ══════════════════════════════════════════════════════════════
printf "${BOLD}Token and cost extraction${RESET}\n"

# Two assistant events for ONE message (two content blocks) repeat its usage,
# and the result event has the session's true totals. The result wins.
RESULT_LOG="$TMP_DIR/result.log"
{
  printf '%s\n' '{"type":"assistant","message":{"id":"m1","usage":{"input_tokens":5,"cache_read_input_tokens":100,"output_tokens":2}}}'
  printf '%s\n' '{"type":"assistant","message":{"id":"m1","usage":{"input_tokens":5,"cache_read_input_tokens":100,"output_tokens":2}}}'
  printf '%s\n' '{"type":"result","total_cost_usd":0.42,"usage":{"input_tokens":10,"cache_creation_input_tokens":20,"cache_read_input_tokens":300,"output_tokens":900}}'
} > "$RESULT_LOG"
assert_eq "tokens come from the result event" "330 900" "$(get_tokens "$RESULT_LOG")"
assert_eq "cost comes from the result event" "0.42" "$(get_cost "$RESULT_LOG")"

# A killed run has no result event: count each message's usage once.
NO_RESULT_LOG="$TMP_DIR/noresult.log"
{
  printf '%s\n' '{"type":"assistant","message":{"id":"m1","usage":{"input_tokens":5,"cache_read_input_tokens":100,"output_tokens":2}}}'
  printf '%s\n' '{"type":"assistant","message":{"id":"m1","usage":{"input_tokens":5,"cache_read_input_tokens":100,"output_tokens":2}}}'
  printf '%s\n' '{"type":"assistant","message":{"id":"m2","usage":{"input_tokens":1,"cache_read_input_tokens":200,"output_tokens":3}}}'
} > "$NO_RESULT_LOG"
assert_eq "without a result event, each message counts once" "306 5" "$(get_tokens "$NO_RESULT_LOG")"
assert_eq "without a result event, cost is null" "null" "$(get_cost "$NO_RESULT_LOG")"

# The log captures stderr too (> log 2>&1), so non-JSON lines must not break parsing.
NOISY_LOG="$TMP_DIR/noisy.log"
{
  printf '%s\n' 'Warning: something printed to stderr'
  cat "$RESULT_LOG"
} > "$NOISY_LOG"
assert_eq "stderr lines in the log are skipped" "330 900" "$(get_tokens "$NOISY_LOG")"
assert_eq "stderr lines don't hide the cost" "0.42" "$(get_cost "$NOISY_LOG")"

# An API-down run writes a stub instead of a session.
STUB_LOG="$TMP_DIR/stub.log"
printf '%s\n' '{"error":"API ConnectionRefused"}' > "$STUB_LOG"
assert_eq "API-down stub scores 0 0" "0 0" "$(get_tokens "$STUB_LOG")"
assert_eq "API-down stub has null cost" "null" "$(get_cost "$STUB_LOG")"

assert_eq "missing log scores 0 0" "0 0" "$(get_tokens "$TMP_DIR/nope.log")"
assert_eq "missing log has null cost" "null" "$(get_cost "$TMP_DIR/nope.log")"

# ══════════════════════════════════════════════════════════════
# list_reference_docs
# ══════════════════════════════════════════════════════════════
printf "${BOLD}Reference doc reads${RESET}\n"

REFS_LOG="$TMP_DIR/refs.log"
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"/p/skills/ui-development/references/foundry-js.md"}}]}}' > "$REFS_LOG"
REFS_TOOLS="$TMP_DIR/refs.tools"
cat > "$REFS_TOOLS" <<'EOF'
sed -n '/## Standard Trigger/,/^## /p' /p/skills/workflows-development/references/workflow-examples.md
grep -n '^#' /p/skills/workflows-development/references/workflow-examples.md
cd /p/skills/workflows-development/references && sed -n 1,93p cel-expressions.md
cd /p/skills/workflows-development && cat SKILL.md; ls references
EOF
assert_eq "Read, Bash paths, and cd-relative names, each once" \
  "foundry-js.md workflow-examples.md cel-expressions.md" \
  "$(list_reference_docs "$REFS_LOG" "$REFS_TOOLS" | tr '\n' ' ' | sed 's/ $//')"

NO_REFS_TOOLS="$TMP_DIR/norefs.tools"
printf '%s\n' 'cd /p/skills/workflows-development && cat SKILL.md' 'foundry apps deploy --no-prompt' > "$NO_REFS_TOOLS"
assert_eq "SKILL.md reads don't count as reference docs" "" "$(list_reference_docs "$TMP_DIR/nope.log" "$NO_REFS_TOOLS")"

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
