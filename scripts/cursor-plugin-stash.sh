#!/usr/bin/env bash
# CURSOR_STASH_MOVED and CURSOR_STASH_RECOVERED are read by the caller.
# shellcheck disable=SC2034
#
# cursor-plugin-stash.sh — move Cursor's installed marketplace plugins out of the way
# for a test run, then put them back exactly as they were.
#
# Cursor loads a --plugin-dir and its installed plugin cache at the same time, and
# its CLI has no `plugin disable`. With an installed copy present, a run can use
# either one, so a pass tells you nothing about which version was tested. So
# cursor_stash moves each named plugin's cache directory into a stash (move, never
# delete) and cursor_unstash moves it back.
#
# The stash sits next to the cache under ~/.cursor/plugins rather than /tmp: while a
# run is in flight it holds the only copy, and /tmp is cleared at boot. Each entry
# records where it came from, so cursor_recover can undo a run that was killed.
#
# Source this file, then call:
#   cursor_recover          # once, at startup, to undo a killed run
#   cursor_stash NAME...    # before the run; moves each installed NAME aside
#   cursor_unstash          # afterwards, and from the EXIT/INT trap (idempotent)
#
# Config (defaults shown):
#   CURSOR_STASH_CACHE  ~/.cursor/plugins/cache
#   CURSOR_STASH_DIR    ~/.cursor/plugins/.test-assistants-stash
#
# CURSOR_STASH_MOVED is how many entries cursor_stash moved. CURSOR_STASH_ERR is set
# when something couldn't be moved.

CURSOR_STASH_CACHE="${CURSOR_STASH_CACHE:-$HOME/.cursor/plugins/cache}"
CURSOR_STASH_DIR="${CURSOR_STASH_DIR:-$HOME/.cursor/plugins/.test-assistants-stash}"
CURSOR_STASH_MOVED=0
CURSOR_STASH_ERR=""

# cursor_stash NAME... — move every installed copy of each plugin NAME (under any
# marketplace in the cache) into the stash.
cursor_stash() {
  CURSOR_STASH_ERR=""
  local name dir n=0
  for name in "$@"; do
    for dir in "$CURSOR_STASH_CACHE"/*/"$name"; do
      [ -d "$dir" ] || continue
      mkdir -p "$CURSOR_STASH_DIR" 2>/dev/null || { CURSOR_STASH_ERR="could not create $CURSOR_STASH_DIR"; return 1; }
      local slot="$CURSOR_STASH_DIR/$n"
      while [ -e "$slot" ]; do n=$((n + 1)); slot="$CURSOR_STASH_DIR/$n"; done
      # Record the origin first, so a kill right after the move can still be undone.
      printf '%s\n' "$dir" > "$slot.origin"
      if mv "$dir" "$slot" 2>/dev/null; then
        CURSOR_STASH_MOVED=$((CURSOR_STASH_MOVED + 1))
      else
        rm -f "$slot.origin"
        CURSOR_STASH_ERR="could not move $dir aside"
      fi
      n=$((n + 1))
    done
  done
  [ -z "$CURSOR_STASH_ERR" ]
}

# cursor_unstash — put every stashed entry back where it came from. If Cursor
# re-downloaded a copy into the original path during the run, that copy is replaced.
cursor_unstash() {
  CURSOR_STASH_ERR=""
  [ -d "$CURSOR_STASH_DIR" ] || return 0
  local rec slot origin
  for rec in "$CURSOR_STASH_DIR"/*.origin; do
    [ -f "$rec" ] || continue
    slot="${rec%.origin}"
    read -r origin < "$rec"
    if [ ! -d "$slot" ]; then
      rm -f "$rec"
      continue
    fi
    # Only ever restore into (and replace inside) the plugin cache, so a damaged
    # record can't point the rm below at anything else.
    case "$origin" in
      *"/.."*) CURSOR_STASH_ERR="refusing to restore $slot to $origin (path has ..)"; continue ;;
      "$CURSOR_STASH_CACHE"/*/*) ;;
      *) CURSOR_STASH_ERR="refusing to restore $slot to $origin (outside $CURSOR_STASH_CACHE)"; continue ;;
    esac
    mkdir -p "$(dirname "$origin")" 2>/dev/null
    [ -e "$origin" ] && rm -rf "$origin"
    if mv "$slot" "$origin" 2>/dev/null; then
      rm -f "$rec"
    else
      CURSOR_STASH_ERR="could not move $slot back to $origin"
    fi
  done
  rmdir "$CURSOR_STASH_DIR" 2>/dev/null || true
  CURSOR_STASH_MOVED=0
  [ -z "$CURSOR_STASH_ERR" ]
}

# cursor_recover — undo a run that was killed between cursor_stash and
# cursor_unstash. Sets CURSOR_STASH_RECOVERED=1 if it put something back.
cursor_recover() {
  CURSOR_STASH_RECOVERED=0
  compgen -G "$CURSOR_STASH_DIR/*.origin" >/dev/null || return 0
  cursor_unstash || return 1
  CURSOR_STASH_RECOVERED=1
}
