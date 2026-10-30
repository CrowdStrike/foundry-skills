#!/usr/bin/env bash
#
# test-cursor-plugin-stash.sh — unit tests for scripts/cursor-plugin-stash.sh.
# Fast, no network, no real Cursor. Every test asserts that the installed plugins come
# back exactly as they were, whether the run finished or was killed.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/cursor-stash-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

export CURSOR_STASH_CACHE="$WORK/cursor/plugins/cache"
export CURSOR_STASH_DIR="$WORK/cursor/plugins/.stash"

# shellcheck source=scripts/cursor-plugin-stash.sh
source "$SCRIPT_DIR/scripts/cursor-plugin-stash.sh"

PASS=0
FAIL=0
check() {  # description, then a command that must succeed
  local d="$1"; shift
  if "$@"; then PASS=$((PASS + 1)); echo "  ✓ $d"; else FAIL=$((FAIL + 1)); echo "  ✗ $d"; fi
}
install_plugins() {
  rm -rf "$WORK/cursor"
  mkdir -p "$CURSOR_STASH_CACHE/cursor-public/fusion/abc123" "$CURSOR_STASH_CACHE/cursor-public/foundry/def456" "$CURSOR_STASH_CACHE/cursor-public/other/1"
  echo v1 > "$CURSOR_STASH_CACHE/cursor-public/fusion/abc123/SKILL.md"
  echo f1 > "$CURSOR_STASH_CACHE/cursor-public/foundry/def456/SKILL.md"
}
installed() { [ -f "$CURSOR_STASH_CACHE/cursor-public/fusion/abc123/SKILL.md" ] && [ -f "$CURSOR_STASH_CACHE/cursor-public/foundry/def456/SKILL.md" ]; }

echo "Stash and restore"
install_plugins
cursor_stash fusion foundry
check "both named plugins are moved out of the cache" test ! -e "$CURSOR_STASH_CACHE/cursor-public/fusion" -a ! -e "$CURSOR_STASH_CACHE/cursor-public/foundry"
check "an unnamed plugin is left alone" test -d "$CURSOR_STASH_CACHE/cursor-public/other/1"
check "two entries are counted" test "$CURSOR_STASH_MOVED" -eq 2
cursor_unstash
check "both plugins are back with their contents" installed
check "the stash directory is gone" test ! -e "$CURSOR_STASH_DIR"
check "unstash again is a no-op" cursor_unstash

echo "Nothing installed"
rm -rf "$WORK/cursor"
cursor_stash fusion foundry
check "nothing moved" test "$CURSOR_STASH_MOVED" -eq 0
check "no stash created" test ! -e "$CURSOR_STASH_DIR"

echo "Cursor re-downloaded a copy during the run"
install_plugins
cursor_stash fusion
mkdir -p "$CURSOR_STASH_CACHE/cursor-public/fusion/zzz999"
cursor_unstash
check "the original copy replaces the re-download" test -f "$CURSOR_STASH_CACHE/cursor-public/fusion/abc123/SKILL.md" -a ! -e "$CURSOR_STASH_CACHE/cursor-public/fusion/zzz999"

echo "A killed run is recovered"
install_plugins
cursor_stash fusion foundry
CURSOR_STASH_MOVED=0   # a new process knows nothing about the old run
cursor_recover
check "recover reports that it restored something" test "$CURSOR_STASH_RECOVERED" -eq 1
check "both plugins are back" installed
cursor_recover
check "recover with nothing stashed does nothing" test "$CURSOR_STASH_RECOVERED" -eq 0

echo "A damaged record can't point outside the cache"
install_plugins
mkdir -p "$WORK/outside/keep" "$CURSOR_STASH_DIR/0"
echo "$WORK/outside/keep" > "$CURSOR_STASH_DIR/0.origin"
cursor_unstash
check "unstash refuses and reports it" test -n "$CURSOR_STASH_ERR"
check "the outside directory is untouched" test -d "$WORK/outside/keep"
check "the stashed entry is still in the stash" test -d "$CURSOR_STASH_DIR/0"
printf '%s\n' "$CURSOR_STASH_CACHE/cursor-public/../../../outside/keep" > "$CURSOR_STASH_DIR/0.origin"
cursor_unstash
check "a .. path is refused too" test -d "$WORK/outside/keep" -a -d "$CURSOR_STASH_DIR/0"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
