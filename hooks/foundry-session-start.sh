#!/usr/bin/env bash
#
# foundry-session-start.sh — SessionStart hook
#
# 1. Check Foundry CLI version and warn if below minimum required
# 2. Set FOUNDRY_UI_HEADLESS_MODE=true for CLIs below 2.0.1 (older versions
#    need this env var to suppress the TUI; 2.0.1+ auto-detects headless)
#
set -euo pipefail

# --- Version check ---
MINIMUM_VERSION="2.0.1"
NEEDS_UPGRADE=0

if CLI_OUTPUT=$(foundry version 2>/dev/null); then
  CLI_VERSION=$(echo "$CLI_OUTPUT" | awk '{print $2}')

  # Compare semver: split into major.minor.patch
  IFS='.' read -r CUR_MAJ CUR_MIN CUR_PAT <<< "$CLI_VERSION"
  IFS='.' read -r MIN_MAJ MIN_MIN MIN_PAT <<< "$MINIMUM_VERSION"

  if [ "${CUR_MAJ:-0}" -lt "${MIN_MAJ:-0}" ]; then
    NEEDS_UPGRADE=1
  elif [ "${CUR_MAJ:-0}" -eq "${MIN_MAJ:-0}" ]; then
    if [ "${CUR_MIN:-0}" -lt "${MIN_MIN:-0}" ]; then
      NEEDS_UPGRADE=1
    elif [ "${CUR_MIN:-0}" -eq "${MIN_MIN:-0}" ] && [ "${CUR_PAT:-0}" -lt "${MIN_PAT:-0}" ]; then
      NEEDS_UPGRADE=1
    fi
  fi

  if [ "$NEEDS_UPGRADE" -eq 1 ]; then
    cat >&2 << UPGRADE_EOF
IMPORTANT: Foundry CLI $CLI_VERSION is below the minimum required $MINIMUM_VERSION. Before proceeding with any Foundry work, you MUST inform the user and offer to upgrade:

  - macOS/Linux: brew upgrade crowdstrike/foundry-cli/foundry
  - Windows: Download https://assets.foundry.crowdstrike.com/cli/latest/foundry_Windows_x86_64.zip

Feature unavailable below $MINIMUM_VERSION: automatic headless mode detection (2.0.1+). foundry apps validate works on 2.0.0+.

Use AskUserQuestion to ask whether to upgrade now. If the user declines, Foundry commands may fail or behave unexpectedly.
UPGRADE_EOF
  fi
fi

# --- Env vars for older CLIs ---
# CLIs below 2.0.1 need FOUNDRY_UI_HEADLESS_MODE=true to suppress the TUI.
# 2.0.1+ auto-detects headless environments, so this is only needed as a fallback.
if [ "$NEEDS_UPGRADE" -eq 1 ]; then
  if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
    echo 'export FOUNDRY_UI_HEADLESS_MODE=true' >> "$CLAUDE_ENV_FILE"
  else
    cat >&2 << ENV_EOF
IMPORTANT: Foundry CLI $CLI_VERSION requires FOUNDRY_UI_HEADLESS_MODE=true to suppress the TUI in non-interactive environments. You MUST run this export before ANY foundry CLI command (deploy, release, validate, etc.), or those commands will fail with "could not open a new TTY":

  export FOUNDRY_UI_HEADLESS_MODE=true

Run this silently at the start of any Bash tool call that uses the foundry CLI. Do not ask the user — just prepend it.
ENV_EOF
  fi
fi

exit 0
