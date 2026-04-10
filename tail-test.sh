#!/usr/bin/env bash
# Tail the active test run and show tool calls in real time
#
# Usage:
#   ./tail-test.sh              # Auto-detect latest log
#   ./tail-test.sh path/to.log  # Tail specific log

if [[ -n "${1:-}" ]]; then
  LOG="$1"
else
  # Find the most recently modified .log under both test dirs
  LOG=$(find /tmp/foundry-skill-test /tmp/foundry-skill-ab \
    -name 'run-*.log' -newer /tmp/.tail-test-marker \
    2>/dev/null | head -1)
  # Fallback: newest log overall
  if [[ -z "$LOG" ]]; then
    LOG=$(ls -t /tmp/foundry-skill-test/run-*.log /tmp/foundry-skill-ab/*/run-*.log 2>/dev/null | head -1)
  fi
  if [[ -z "$LOG" ]]; then
    echo "No test logs found. Start a test first, or pass a log path."
    exit 1
  fi
fi

echo "Tailing: $LOG"
echo "Waiting for output... (Ctrl-C to stop)"
tail -f "$LOG" | grep --line-buffered '"tool_use"' | jq -r '.message.content[]? | select(.type=="tool_use") | "\(.name): \(.input.command // .input.skill // .input.file_path // .input.pattern // .input.content[0:80] // "")"' 2>/dev/null
