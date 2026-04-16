#!/usr/bin/env bash
#
# set-foundry-env.sh — SessionStart hook
#
# Sets FOUNDRY_UI_HEADLESS_MODE=true for the entire session so that
# deploy, release, and list-deployments commands work without a TTY.
# This eliminates the need to prefix each command manually.
#
set -euo pipefail

if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo 'export FOUNDRY_UI_HEADLESS_MODE=true' >> "$CLAUDE_ENV_FILE"
  # FOUNDRY_FF_ENHANCED_UI=false disables the TUI deploy flow that requires a TTY.
  # FOUNDRY_UI_HEADLESS_MODE only covers spinners, not deploy/release commands.
  # Remove once FOUNDRY_UI_HEADLESS_MODE covers the full TUI in a future CLI release.
  echo 'export FOUNDRY_FF_ENHANCED_UI=false' >> "$CLAUDE_ENV_FILE"
fi

exit 0
