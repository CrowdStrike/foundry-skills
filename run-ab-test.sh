#!/usr/bin/env bash
#
# run-ab-test.sh — A/B test: main branch (baseline) vs local branch (optimized)
#
# Usage:
#   ./run-ab-test.sh              # main skills vs local skills (5 runs each)
#   ./run-ab-test.sh 3            # 3 runs per phase
#   ./run-ab-test.sh --ref v1.2.2 # compare local branch against a specific release tag
#   ./run-ab-test.sh --no-skill   # no plugins at all vs local skills (1 baseline run with timeout)
#   ./run-ab-test.sh --fresh      # force baseline re-run even if cached
#
# Smart baseline caching:
#   First run:  RED (baseline ref) + GREEN (local branch)
#   Next runs:  Reuses cached baseline if ref hasn't changed, runs GREEN only
#   ref moves:  Detects stale baseline, re-runs RED automatically
#
# Uses claude --plugin-dir to load the plugin from either:
#   RED:   a temp checkout of the baseline ref (default: main)
#   GREEN: the local working tree
# No cache manipulation required.
#
set -euo pipefail

# ── Argument parsing ──────────────────────────────────────────
RUNS=5
NO_SKILL=0
FRESH=0
BASELINE_REF=main
BASELINE_TIMEOUT=1800  # 30 minutes default for no-skill baseline

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-skill)
      NO_SKILL=1
      shift
      ;;
    --fresh)
      FRESH=1
      shift
      ;;
    --ref)
      BASELINE_REF="$2"
      shift 2
      ;;
    --timeout)
      BASELINE_TIMEOUT="$2"
      shift 2
      ;;
    [0-9]*)
      RUNS="$1"
      shift
      ;;
    *)
      echo "Usage: $0 [--no-skill] [--fresh] [--ref <git-ref>] [--timeout <seconds>] [N]"
      exit 1
      ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
AB_RESULTS_DIR="/tmp/foundry-skill-ab"
RED_DIR="$AB_RESULTS_DIR/red-runs"
GREEN_DIR="$AB_RESULTS_DIR/green-runs"
BASELINE_JSON="$AB_RESULTS_DIR/baseline.json"

# Delete Foundry apps from a phase directory
cleanup_phase_apps() {
  local phase_dir="$1"
  for dir in "$phase_dir"/run-*/; do
    [ -d "$dir" ] || continue
    local app_dir
    app_dir=$(f=$(find "$dir" -name "manifest.yml" -maxdepth 3 2>/dev/null | head -1); [ -n "$f" ] && dirname "$f" || true)
    if [ -n "$app_dir" ] && [ -d "$app_dir" ]; then
      local app_name
      app_name=$(grep -m1 '^name:' "$app_dir/manifest.yml" 2>/dev/null | sed 's/^name:\s*//')
      echo "  Deleting: ${app_name:-unknown}..."
      (cd "$app_dir" && foundry apps delete --force-delete 2>&1) || true
    fi
  done
}
BASELINE_SHA_FILE="$AB_RESULTS_DIR/baseline-main-sha"
OPTIMIZED_JSON="$AB_RESULTS_DIR/optimized.json"
MAIN_EXTRACT_DIR="$AB_RESULTS_DIR/main-branch"
mkdir -p "$AB_RESULTS_DIR"

# Copy test-skill.sh and its schema to /tmp so it works regardless of branch
cp "$REPO_ROOT/test-skill.sh" /tmp/test-skill-enhanced.sh
cp "$REPO_ROOT/test-result-schema.json" /tmp/test-result-schema.json
chmod +x /tmp/test-skill-enhanced.sh

# ── Baseline staleness check ─────────────────────────────────
SKIP_RED=0
if [ "$NO_SKILL" != "1" ] && [ "$FRESH" != "1" ]; then
  CURRENT_BASELINE_SHA=$(git -C "$REPO_ROOT" rev-parse "$BASELINE_REF" 2>/dev/null)

  if [ -f "$BASELINE_JSON" ] && [ -f "$BASELINE_SHA_FILE" ]; then
    CACHED_SHA=$(cat "$BASELINE_SHA_FILE")
    if [ "$CACHED_SHA" = "$CURRENT_BASELINE_SHA" ]; then
      SKIP_RED=1
      BASELINE_RUNS=$(jq -r '.runs // 0' "$BASELINE_JSON" 2>/dev/null || echo "?")
      echo "========================================="
      echo "  CACHED BASELINE FOUND"
      echo "========================================="
      echo "  Baseline ref:  $BASELINE_REF"
      echo "  Baseline SHA:  ${CURRENT_BASELINE_SHA:0:10}"
      echo "  Baseline runs: $BASELINE_RUNS"
      echo "  Baseline file: $BASELINE_JSON"
      echo ""
      echo "  Skipping RED phase — baseline ref hasn't changed."
      echo "  Use --fresh to force a new baseline."
      echo ""
    else
      echo "========================================="
      echo "  STALE BASELINE DETECTED"
      echo "========================================="
      echo "  Cached SHA:  ${CACHED_SHA:0:10}"
      echo "  Current SHA: ${CURRENT_BASELINE_SHA:0:10}"
      echo ""
      echo "  Baseline ref ($BASELINE_REF) has moved. Re-running RED phase."
      echo ""
    fi
  fi
fi

# ── Extract main branch to temp dir ──────────────────────────
if [ "$NO_SKILL" != "1" ]; then
  if [ "$SKIP_RED" != "1" ]; then
    echo "Extracting $BASELINE_REF plugin..."
    rm -rf "$MAIN_EXTRACT_DIR"
    mkdir -p "$MAIN_EXTRACT_DIR"
    # Extract the full plugin structure (skills, hooks, .claude-plugin, CLAUDE.md, etc.)
    git -C "$REPO_ROOT" archive "$BASELINE_REF" | tar -x -C "$MAIN_EXTRACT_DIR"
    echo "  Extracted to: $MAIN_EXTRACT_DIR"
    echo ""
  fi
fi

if [ "$NO_SKILL" = "1" ]; then
  RUNS=1
  echo "========================================="
  echo "  A/B TEST: no-skill vs with-skill (1 run each)"
  echo "========================================="
  echo "  Baseline timeout: ${BASELINE_TIMEOUT}s"
  echo ""
  echo "  No-skill mode runs 1 vs 1 since the no-skill run is"
  echo "     expected to fail. Increase runs when foundry apps validate"
  echo "     is available for faster fail-fast detection."
else
  echo "========================================="
  if [ "$SKIP_RED" = "1" ]; then
    echo "  A/B TEST: GREEN only (${RUNS} runs, cached baseline)"
  else
    echo "  A/B TEST: ${RUNS} runs per phase"
  fi
  echo "========================================="
fi
echo "  Repo root:     $REPO_ROOT"
echo "  Baseline ref:  $BASELINE_REF (${MAIN_EXTRACT_DIR:-N/A})"
echo "  Local branch:  $REPO_ROOT"
if [ "$SKIP_RED" != "1" ]; then
  echo "  RED results:   $RED_DIR"
fi
echo "  GREEN results: $GREEN_DIR"
echo ""

# ── Pre-flight: ensure local skills differ from main ─────────
if [ "$NO_SKILL" != "1" ]; then
  # Need main extracted for diff check even when skipping RED
  if [ "$SKIP_RED" = "1" ] && [ ! -d "$MAIN_EXTRACT_DIR" ]; then
    echo "Extracting $BASELINE_REF for pre-flight check..."
    rm -rf "$MAIN_EXTRACT_DIR"
    mkdir -p "$MAIN_EXTRACT_DIR"
    git -C "$REPO_ROOT" archive "$BASELINE_REF" | tar -x -C "$MAIN_EXTRACT_DIR"
  fi

  PREFLIGHT_DIFF=0
  for dir in skills hooks use-cases; do
    if [ -d "$MAIN_EXTRACT_DIR/$dir" ] || [ -d "$REPO_ROOT/$dir" ]; then
      if ! diff -rq "$MAIN_EXTRACT_DIR/$dir" "$REPO_ROOT/$dir" >/dev/null 2>&1; then
        PREFLIGHT_DIFF=1
        break
      fi
    fi
  done
  # Also check top-level files that affect plugin behavior
  for f in CLAUDE.md hooks.json; do
    if [ -f "$MAIN_EXTRACT_DIR/$f" ] || [ -f "$REPO_ROOT/$f" ]; then
      if ! diff -q "$MAIN_EXTRACT_DIR/$f" "$REPO_ROOT/$f" >/dev/null 2>&1; then
        PREFLIGHT_DIFF=1
        break
      fi
    fi
  done
  if [ "$PREFLIGHT_DIFF" = "0" ]; then
    echo "ERROR: Local plugin files are identical to $BASELINE_REF."
    echo ""
    echo "  The A/B test compares baseline ref ($BASELINE_REF) skills (RED) vs local skills (GREEN)."
    echo "  If they're the same, the test is meaningless."
    echo ""
    echo "  Directories checked: skills/, hooks/, use-cases/"
    echo "  Files checked: CLAUDE.md, hooks.json"
    echo ""
    echo "  Common causes:"
    echo "    - Working tree was reset to $BASELINE_REF"
    echo "    - Branch has no skill/hook changes"
    echo ""
    exit 1
  fi
  echo "Pre-flight: local plugin files differ from $BASELINE_REF. Good."
  echo ""
fi

# ── Fresh run: prompt for tenant cleanup ─────────────────────
if [ "$FRESH" = "1" ]; then
  echo "⚠️  Fresh run requested. Delete all test apps from the Falcon console"
  echo "   (Foundry → App manager) to avoid name collisions."
  echo ""
  # Clean up apps from any existing phase directories before deleting them
  if [ -d "$RED_DIR" ]; then
    echo "  Cleaning up RED phase apps..."
    cleanup_phase_apps "$RED_DIR"
  fi
  if [ -d "$GREEN_DIR" ]; then
    echo "  Cleaning up GREEN phase apps..."
    cleanup_phase_apps "$GREEN_DIR"
  fi
  echo ""
  read -p "  Press Enter when ready (or Ctrl+C to abort)... "
  echo ""
fi

# ── Disable installed Foundry plugins ─────────────────────────
# --plugin-dir adds a plugin, but installed marketplace plugins take priority.
# Disable them so --plugin-dir is the only source of Foundry skills/hooks.
# For --no-skill mode, RED phase runs with no plugins at all.
ENABLED_FOUNDRY_PLUGINS=()
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
  # Re-enable on exit (even if interrupted)
  trap 'echo ""; [ -n "${TIMER_PID:-}" ] && kill "$TIMER_PID" 2>/dev/null || true; echo "Re-enabling Foundry plugins..."; for p in "${ENABLED_FOUNDRY_PLUGINS[@]}"; do echo "  Enabling: $p"; claude plugin enable "$p" 2>/dev/null || true; done' EXIT
  echo ""
fi

# ── RED Phase ─────────────────────────────────────────────────
if [ "$SKIP_RED" = "1" ]; then
  echo "========================================="
  echo "  RED PHASE: Skipped (using cached baseline)"
  echo "========================================="
  echo ""
  echo "  Baseline: $BASELINE_JSON"
  echo ""

elif [ "$NO_SKILL" = "1" ]; then
  echo "========================================="
  echo "  RED PHASE: No skills (Foundry plugins disabled)"
  echo "========================================="
  echo ""
  echo "  Running 1 baseline test with ${BASELINE_TIMEOUT}s timeout..."
  echo ""

  # Run with timeout (macOS compatible: background + kill)
  /tmp/test-skill-enhanced.sh --save "$BASELINE_JSON" --runs 1 --dir "$RED_DIR" --no-plugin --skip-plugin-manage &
  TEST_PID=$!
  ( sleep "$BASELINE_TIMEOUT" && kill "$TEST_PID" 2>/dev/null && echo "" && echo "  Baseline timed out after ${BASELINE_TIMEOUT}s" ) &
  TIMER_PID=$!
  wait "$TEST_PID" 2>/dev/null || true
  kill "$TIMER_PID" 2>/dev/null || true
  wait "$TIMER_PID" 2>/dev/null || true

else
  echo "========================================="
  echo "  RED PHASE: Baseline ($BASELINE_REF)"
  echo "========================================="
  echo ""

  /tmp/test-skill-enhanced.sh --save "$BASELINE_JSON" --runs "$RUNS" --dir "$RED_DIR" \
    --plugin-dir "$MAIN_EXTRACT_DIR" --skip-plugin-manage

  # Save baseline SHA so we can detect staleness later
  git -C "$REPO_ROOT" rev-parse "$BASELINE_REF" > "$BASELINE_SHA_FILE"
  echo ""
  echo "  Baseline SHA saved: $(cat "$BASELINE_SHA_FILE")"
fi

if [ "$SKIP_RED" != "1" ]; then
  echo ""
  echo "Baseline saved to: $BASELINE_JSON"
  echo ""

  # Clean up RED phase apps from Foundry cloud so GREEN phase can use same names
  echo "Cleaning up RED phase apps from Falcon console..."
  cleanup_phase_apps "$RED_DIR"
  echo "  Done."
  echo ""
fi

# ── GREEN Phase: local branch ────────────────────────────────
# Clean up previous GREEN phase apps before starting
if [ -d "$GREEN_DIR" ]; then
  echo "Cleaning up previous GREEN phase apps..."
  cleanup_phase_apps "$GREEN_DIR"
  rm -rf "$GREEN_DIR"
  echo "  Done."
  echo ""
fi

echo "========================================="
echo "  GREEN PHASE: Local branch skills"
echo "========================================="
echo ""

/tmp/test-skill-enhanced.sh --save "$OPTIMIZED_JSON" --baseline "$BASELINE_JSON" --runs "$RUNS" --dir "$GREEN_DIR" \
  --plugin-dir "$REPO_ROOT" --skip-plugin-manage

echo ""
echo "========================================="
echo "  A/B TEST COMPLETE"
echo "========================================="
echo "  Baseline: $BASELINE_JSON"
echo "  Optimized: $OPTIMIZED_JSON"
if [ "$SKIP_RED" != "1" ]; then
  echo "  RED runs:  $RED_DIR"
fi
echo "  GREEN runs: $GREEN_DIR"
echo ""
