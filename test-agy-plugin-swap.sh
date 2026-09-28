#!/usr/bin/env bash
#
# test-agy-plugin-swap.sh — unit tests for scripts/agy-plugin-swap.sh.
# Fast, no network, no real Antigravity. A stub `agy` flips the enabled flag in a
# throwaway config.json, and every test asserts that the installed plugin and its
# flag come back exactly as they were, whether the run finished or was killed.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/agy-swap-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

export AGY_SWAP_NAME="test-plugin"
export AGY_SWAP_REPO="$WORK/repo"
export AGY_SWAP_PLUGINS="$WORK/gemini/config/plugins"
export AGY_SWAP_CONFIG="$WORK/gemini/config/config.json"
export AGY_SWAP_STASH="$WORK/gemini/config/.stash/$AGY_SWAP_NAME"
export AGY_SWAP_BIN="$WORK/bin/agy"

mkdir -p "$WORK/bin"
cat > "$AGY_SWAP_BIN" <<'STUB'
#!/usr/bin/env bash
# agy plugin enable|disable <name>, writing plugins.<name>.enabled like the real CLI.
[ "$1" = plugin ] || exit 2
case "$2" in enable) v=True ;; disable) v=False ;; *) exit 2 ;; esac
python3 - "$AGY_SWAP_CONFIG" "$3" "$v" <<'PY'
import json, sys
path, name, v = sys.argv[1], sys.argv[2], sys.argv[3] == "True"
try:
    d = json.load(open(path))
except Exception:
    d = {}
d.setdefault("plugins", {}).setdefault(name, {})["enabled"] = v
json.dump(d, open(path, "w"))
PY
STUB
chmod +x "$AGY_SWAP_BIN"

# shellcheck source=scripts/agy-plugin-swap.sh
source "$SCRIPT_DIR/scripts/agy-plugin-swap.sh"

PASS=0
FAIL=0
pass() { echo "  ✅ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }
expect() { local d="$1"; shift; if "$@"; then pass "$d"; else fail "$d"; fi; }  # expect <desc> <cmd...>
refute() { local d="$1"; shift; if "$@"; then fail "$d"; else pass "$d"; fi; }  # refute <desc> <cmd...>
flag_is() { [ "$(agy_plugin_enabled test-plugin)" = "$1" ]; }
stash_marker_is() { [ "$(cat "$AGY_SWAP_STASH/plugin/marker" 2>/dev/null)" = "$1" ]; }

PATH_="$AGY_SWAP_PLUGINS/$AGY_SWAP_NAME"

# build_fixture <enabled: true|false|none> <installed: yes|no>
build_fixture() {
  rm -rf "$WORK/gemini" "$WORK/repo" "$WORK/other"
  mkdir -p "$AGY_SWAP_PLUGINS" "$AGY_SWAP_REPO"
  echo "working-tree" > "$AGY_SWAP_REPO/marker"
  if [ "$2" = yes ]; then
    mkdir -p "$PATH_"
    echo "installed-copy" > "$PATH_/marker"
  fi
  case "$1" in
    true)  echo '{"plugins": {"test-plugin": {"enabled": true}}}'  > "$AGY_SWAP_CONFIG" ;;
    false) echo '{"plugins": {"test-plugin": {"enabled": false}}}' > "$AGY_SWAP_CONFIG" ;;
    none)  echo '{}' > "$AGY_SWAP_CONFIG" ;;
  esac
}
installed_back() { [ -d "$PATH_" ] && [ ! -L "$PATH_" ] && [ "$(cat "$PATH_/marker")" = "installed-copy" ]; }
linked() { [ -L "$PATH_" ] && [ "$(readlink "$PATH_")" = "$AGY_SWAP_REPO" ]; }
no_stash() { [ ! -e "$AGY_SWAP_STASH" ]; }

echo "== swap in, then out, with the plugin enabled =="
build_fixture true yes
expect "swap_in succeeds" agy_swap_in
expect "plugin path is a symlink to the working tree" linked
expect "installed copy parked in the stash" stash_marker_is installed-copy
expect "AGY_SWAP_ACTIVE is 1 while swapped" [ "$AGY_SWAP_ACTIVE" -eq 1 ]
expect "swap_out succeeds" agy_swap_out
expect "installed copy is back in place" installed_back
expect "flag still true" flag_is true
expect "stash removed" no_stash

echo "== a plugin the user had disabled goes back to disabled =="
build_fixture false yes
agy_swap_in >/dev/null
expect "enabled for the run" flag_is true
agy_swap_out
expect "disabled again afterwards" flag_is false
expect "installed copy is back in place" installed_back

echo "== nothing installed: the symlink is created and then removed =="
build_fixture none no
expect "swap_in succeeds" agy_swap_in
expect "plugin path is a symlink to the working tree" linked
agy_swap_out
refute "no plugin left behind" [ -e "$PATH_" -o -L "$PATH_" ]
expect "stash removed" no_stash

echo "== swap_out is idempotent =="
expect "second swap_out is a no-op" agy_swap_out

echo "== an earlier run's stash blocks the swap and nothing is touched =="
build_fixture true yes
mkdir -p "$AGY_SWAP_STASH/plugin" && echo "older-copy" > "$AGY_SWAP_STASH/plugin/marker"
refute "swap_in refuses" agy_swap_in
expect "installed copy untouched" installed_back
expect "leftover stash untouched" stash_marker_is older-copy
expect "reason reported in AGY_SWAP_ERR" [ -n "$AGY_SWAP_ERR" ]

echo "== agy_recover undoes a run that was killed after the swap =="
build_fixture false yes
agy_swap_in >/dev/null
AGY_SWAP_ACTIVE=0          # a new process: nothing in memory, only the stash
expect "recover succeeds" agy_recover
expect "recover reports it put something back" [ "$AGY_SWAP_RECOVERED" -eq 1 ]
expect "installed copy is back in place" installed_back
expect "flag back to false" flag_is false
expect "stash removed" no_stash

echo "== agy_recover undoes a run killed between the move and the symlink =="
build_fixture true yes
mkdir -p "$AGY_SWAP_STASH"
printf '%s\n' "$AGY_SWAP_REPO" > "$AGY_SWAP_STASH/link-target"
echo true > "$AGY_SWAP_STASH/enabled"
mv "$PATH_" "$AGY_SWAP_STASH/plugin"
expect "recover succeeds" agy_recover
expect "installed copy is back in place" installed_back

echo "== agy_recover undoes a run started from a different clone =="
build_fixture true yes
mkdir -p "$WORK/other"
AGY_SWAP_REPO="$WORK/other" agy_swap_in >/dev/null
expect "recover succeeds from this clone" agy_recover
expect "the other clone's symlink is gone and the installed copy is back" installed_back

echo "== agy_recover keeps both copies if the plugin was reinstalled meanwhile =="
build_fixture true yes
agy_swap_in >/dev/null
rm -f "$PATH_"; mkdir -p "$PATH_"; echo "reinstalled" > "$PATH_/marker"
refute "recover reports failure" agy_recover
expect "reinstalled copy untouched" [ "$(cat "$PATH_/marker")" = "reinstalled" ]
expect "parked copy kept in the stash" stash_marker_is installed-copy

echo "== a reinstalled copy keeps its flag and the stash keeps its recovery record =="
build_fixture false yes
agy_swap_in >/dev/null
rm -f "$PATH_"; mkdir -p "$PATH_"; echo "reinstalled" > "$PATH_/marker"
refute "swap_out reports failure" agy_swap_out
expect "reinstalled copy's flag left enabled" flag_is true
expect "link target still recorded" [ -f "$AGY_SWAP_STASH/link-target" ]
expect "prior flag still recorded" [ "$(cat "$AGY_SWAP_STASH/enabled" 2>/dev/null)" = false ]
rm -rf "$PATH_"
expect "recover succeeds once the path is free" agy_recover
expect "installed copy is back in place" installed_back
expect "flag back to false" flag_is false
expect "stash removed" no_stash

echo "== a failed enable blocks the swap and puts everything back =="
build_fixture false yes
refute "swap_in refuses" env AGY_SWAP_BIN=false bash -c "source '$SCRIPT_DIR/scripts/agy-plugin-swap.sh' && agy_swap_in"
expect "installed copy is back in place" installed_back
expect "flag still false" flag_is false
expect "stash removed" no_stash

echo "== swap_out runs from an INT (Ctrl-C) trap =="
build_fixture false yes
cat > "$WORK/int-child.sh" <<CHILD
source "$SCRIPT_DIR/scripts/agy-plugin-swap.sh"
trap 'agy_swap_out' EXIT
trap 'agy_swap_out; exit 130' INT TERM
agy_swap_in
: > "$WORK/int-ready"
sleep 20 & wait
CHILD
rm -f "$WORK/int-ready"
bash "$WORK/int-child.sh" & icpid=$!
tries=0; while [ ! -f "$WORK/int-ready" ] && [ "$tries" -lt 100 ]; do sleep 0.1; tries=$((tries + 1)); done
kill -INT "$icpid" 2>/dev/null; wait "$icpid" 2>/dev/null || true
expect "INT trap put the installed copy back" installed_back
expect "INT trap put the flag back to false" flag_is false
expect "stash removed" no_stash

echo ""
echo "== $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
