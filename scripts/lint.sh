#!/usr/bin/env bash
#
# lint.sh — Run pylint on all skill-bundled Python scripts
#
# Usage: ./scripts/lint.sh
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RCFILE="$REPO_ROOT/.pylintrc"
FAIL=0

for py in "$REPO_ROOT"/skills/*/scripts/*.py; do
  [ -f "$py" ] || continue
  name="${py#"$REPO_ROOT"/}"
  printf "%-60s " "$name"
  score=$(pipx run pylint --rcfile="$RCFILE" "$py" 2>&1 | sed -n 's/.*rated at \([0-9.]*\).*/\1/p')
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
