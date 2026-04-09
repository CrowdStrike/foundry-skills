#!/usr/bin/env bash
#
# lint.sh — Run pylint on all Python scripts
#
# Usage: ./scripts/lint.sh
#
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
FAIL=0

for py in "$SCRIPTS_DIR"/*.py; do
  [ -f "$py" ] || continue
  name=$(basename "$py")
  printf "%-35s " "$name"
  score=$(pipx run pylint "$py" 2>&1 | sed -n 's/.*rated at \([0-9.]*\).*/\1/p')
  [ -z "$score" ] && score="ERR"
  if [ "$score" = "10.00" ] || [ "$score" = "10.0" ]; then
    printf "\033[0;32m%s/10\033[0m\n" "$score"
  elif echo "$score" | grep -qE '^[9]\.[0-9]+$'; then
    printf "\033[0;33m%s/10\033[0m\n" "$score"
  else
    printf "\033[0;31m%s/10\033[0m\n" "$score"
    FAIL=1
  fi
done

exit "$FAIL"
