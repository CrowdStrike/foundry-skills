#!/usr/bin/env bash
# AGY_SWAP_ACTIVE and AGY_SWAP_RECOVERED are read by the caller.
# shellcheck disable=SC2034
#
# agy-plugin-swap.sh — point Antigravity at the working tree for a test run, then
# put its installed plugin back exactly as it was.
#
# Antigravity has no --plugin-dir and ignores ~/.agents/skills. It loads plugins only
# from ~/.gemini/config/plugins/<name>, and whether each one is live is a per-name
# `enabled` flag in ~/.gemini/config/config.json. So agy_swap_in parks the installed
# copy (move, never delete), symlinks the working tree in its place and enables it;
# agy_swap_out removes the symlink, moves the installed copy back and returns the
# flag to its prior value.
#
# The stash is under ~/.gemini/config rather than /tmp. While a run is in flight it
# holds the only copy of the installed plugin, and /tmp is cleared at boot. Before
# anything moves, the stash also records the symlink target it is about to create
# and the flag's prior value, so agy_recover can undo a run that was killed at any
# point, including one started from a different clone.
#
# Source this file, bind the config, then call:
#   agy_recover       # once, at startup, to undo a killed run
#   agy_swap_in       # before the Antigravity run; non-zero means "do not test"
#   agy_swap_out      # afterwards, and from the EXIT/INT/TERM trap (idempotent)
#
# Config (defaults shown):
#   AGY_SWAP_NAME     (required)                     the plugin's name
#   AGY_SWAP_REPO     (required)                     the working tree to link in
#   AGY_SWAP_PLUGINS  ~/.gemini/config/plugins
#   AGY_SWAP_CONFIG   ~/.gemini/config/config.json
#   AGY_SWAP_STASH    ~/.gemini/config/.test-assistants-stash/$AGY_SWAP_NAME
#   AGY_SWAP_BIN      agy
#
# Each function returns non-zero and sets AGY_SWAP_ERR when it can't do its job.
# AGY_SWAP_ACTIVE is 1 from the moment agy_swap_in starts recording until
# agy_swap_out finishes.

AGY_SWAP_PLUGINS="${AGY_SWAP_PLUGINS:-$HOME/.gemini/config/plugins}"
AGY_SWAP_CONFIG="${AGY_SWAP_CONFIG:-$HOME/.gemini/config/config.json}"
AGY_SWAP_STASH="${AGY_SWAP_STASH:-$HOME/.gemini/config/.test-assistants-stash/${AGY_SWAP_NAME:-}}"
AGY_SWAP_BIN="${AGY_SWAP_BIN:-agy}"
AGY_SWAP_ACTIVE=0
AGY_SWAP_ERR=""

# agy_plugin_enabled <name> — prints true, false, or nothing if the flag isn't set.
agy_plugin_enabled() {
  [ -f "$AGY_SWAP_CONFIG" ] || return 0
  python3 - "$AGY_SWAP_CONFIG" "$1" <<'PY' 2>/dev/null
import json, sys
try:
    plugins = json.load(open(sys.argv[1])).get("plugins") or {}
except Exception:
    sys.exit(0)
v = (plugins.get(sys.argv[2]) or {}).get("enabled")
if isinstance(v, bool):
    print("true" if v else "false")
PY
}

agy_swap_in() {
  AGY_SWAP_ERR=""
  local path="$AGY_SWAP_PLUGINS/$AGY_SWAP_NAME" st="$AGY_SWAP_STASH"
  if [ -e "$st" ] || [ -L "$st" ]; then
    AGY_SWAP_ERR="an earlier run's stash is still at $st"
    return 1
  fi
  mkdir -p "$AGY_SWAP_PLUGINS" "$st" 2>/dev/null || { AGY_SWAP_ERR="could not create $st"; return 1; }
  # Record first, so a kill anywhere below leaves enough behind to undo it.
  printf '%s\n' "$AGY_SWAP_REPO" > "$st/link-target"
  agy_plugin_enabled "$AGY_SWAP_NAME" > "$st/enabled"
  AGY_SWAP_ACTIVE=1
  if [ -e "$path" ] || [ -L "$path" ]; then
    if ! mv "$path" "$st/plugin" 2>/dev/null; then
      AGY_SWAP_ERR="could not move $path aside"
      agy_swap_out
      return 1
    fi
  fi
  if ! ln -s "$AGY_SWAP_REPO" "$path" 2>/dev/null; then
    AGY_SWAP_ERR="could not link $AGY_SWAP_REPO into $AGY_SWAP_PLUGINS"
    agy_swap_out
    return 1
  fi
  "$AGY_SWAP_BIN" plugin enable "$AGY_SWAP_NAME" >/dev/null 2>&1 || true
  return 0
}

agy_swap_out() {
  local path="$AGY_SWAP_PLUGINS/$AGY_SWAP_NAME" st="$AGY_SWAP_STASH" target="" prior=""
  local err="$AGY_SWAP_ERR"
  [ -d "$st" ] || { AGY_SWAP_ACTIVE=0; return 0; }
  [ -f "$st/link-target" ] && read -r target < "$st/link-target"
  [ -f "$st/enabled" ] && read -r prior < "$st/enabled"
  # Remove the symlink only if it's the one that was recorded, whichever clone made it.
  if [ -n "$target" ] && [ -L "$path" ] && [ "$(readlink "$path")" = "$target" ]; then
    rm -f "$path"
  fi
  if [ "$prior" = "false" ]; then
    "$AGY_SWAP_BIN" plugin disable "$AGY_SWAP_NAME" >/dev/null 2>&1 \
      || err="could not disable $AGY_SWAP_NAME again"
  fi
  rm -f "$st/link-target" "$st/enabled"
  if [ -e "$st/plugin" ] || [ -L "$st/plugin" ]; then
    if [ -e "$path" ] || [ -L "$path" ]; then
      AGY_SWAP_ERR="$path is occupied, so the installed copy is still parked at $st/plugin"
      AGY_SWAP_ACTIVE=0
      return 1
    fi
    if ! mv "$st/plugin" "$path" 2>/dev/null; then
      AGY_SWAP_ERR="could not move $st/plugin back to $path"
      AGY_SWAP_ACTIVE=0
      return 1
    fi
  fi
  rmdir "$st" "${st%/*}" 2>/dev/null || true
  AGY_SWAP_ACTIVE=0
  AGY_SWAP_ERR="$err"
  return 0
}

# agy_recover — undo a run that was killed between agy_swap_in and agy_swap_out.
# Returns 0 with AGY_SWAP_RECOVERED=1 if it put something back, 0 if there was
# nothing to do, and 1 (with AGY_SWAP_ERR) if the stash couldn't be returned.
agy_recover() {
  AGY_SWAP_RECOVERED=0
  AGY_SWAP_ERR=""
  [ -d "$AGY_SWAP_STASH" ] || return 0
  agy_swap_out || return 1
  AGY_SWAP_RECOVERED=1
  return 0
}
