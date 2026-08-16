#!/usr/bin/env bash
#
# test-assistants.sh — Smoke-test every assistant in the README against a live tenant.
#
# Each assistant is asked to run the CLI prerequisite check and report
# `foundry apps list`. That command is the earliest reliable failure signal: it is
# the first step that reaches the tenant, so a sandbox blocking the CLI's
# token-cache write, a missing profile, or a bad flag all surface here rather than
# fifteen minutes into a build.
#
# Nothing is created, deployed, or released. The prompt is read-only by design.
#
# BIAS CONTROL — this is the point of the script, not a detail. Skills can reach an
# assistant from several places at once (an installed marketplace plugin, symlinks
# in ~/.agents/skills/, a --plugin-dir flag). If more than one is live, a passing
# run tells you nothing about which copy was exercised, and a stale installed copy
# can silently mask your working tree. So before testing, this script:
#
#   1. Disables installed Foundry plugins where the assistant supports it
#   2. Moves this repo's symlinks out of ~/.agents/skills/
#   3. Gives each assistant exactly ONE source pointing at the working tree
#
# Everything is restored on exit, including on Ctrl-C.
#
# Usage:
#   ./test-assistants.sh                      # test every installed assistant
#   ./test-assistants.sh --only codex         # test one (repeatable)
#   ./test-assistants.sh --timeout 180        # per-assistant limit (default 120s)
#   ./test-assistants.sh --expire-token       # delete the cached token first (see below)
#   ./test-assistants.sh --save results.json  # machine-readable results
#   ./test-assistants.sh --no-isolate         # skip bias control (not recommended)
#
# --expire-token removes ~/.config/foundry/token.json so each run must refresh it.
# Without this, a still-valid token means no write is attempted and a sandbox
# permission failure cannot reproduce. The file is a regenerable cache, not a
# credential; the CLI recreates it from configuration.yml.
#
# Exit status is non-zero if any tested assistant failed.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMEOUT=120
SAVE_FILE=""
ONLY=()
ISOLATE=1
EXPIRE_TOKEN=0
LOG_DIR="/tmp/foundry-assistant-test"
SKILL_HOME="$HOME/.agents/skills"
STASH="$LOG_DIR/stashed-symlinks"

PROMPT="Use the Falcon Foundry skills to run the CLI prerequisite check: report the output of 'foundry version', 'foundry profile active', and 'foundry apps list'. Do NOT create, deploy, or release anything. Print the raw command output verbatim, then stop."

while [[ $# -gt 0 ]]; do
  case "$1" in
    --only)         ONLY+=("$2"); shift 2 ;;
    --timeout)      TIMEOUT="$2"; shift 2 ;;
    --save)         SAVE_FILE="$2"; shift 2 ;;
    --prompt)       PROMPT="$2"; shift 2 ;;
    --no-isolate)   ISOLATE=0; shift ;;
    --expire-token) EXPIRE_TOKEN=1; shift ;;
    -h|--help)      sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'
BLUE=$'\033[0;34m'; MAGENTA=$'\033[0;35m'; CYAN=$'\033[0;36m'
DIM=$'\033[2m'; BOLD=$'\033[1m'; RESET=$'\033[0m'

ok()   { printf '  %s✓%s  %s\n' "$GREEN" "$RESET" "$1"; }
warn() { printf '  %s▲%s  %s\n' "$YELLOW" "$RESET" "$1"; }
info() { printf '      %s%s%s\n' "$DIM" "$1" "$RESET"; }
head2(){ printf '\n%s%s%s%s\n' "$BOLD" "$CYAN" "$1" "$RESET"; }

TIMEOUT_BIN=$(command -v timeout || command -v gtimeout || true)
[ -z "$TIMEOUT_BIN" ] && { echo "ERROR: needs 'timeout' or 'gtimeout' (brew install coreutils)" >&2; exit 1; }

mkdir -p "$LOG_DIR"

# ── Bias control ───────────────────────────────────────────────
DISABLED_CLAUDE=()
DISABLED_AGY=()
STASHED=0

restore() {
  local had=0
  [ ${#DISABLED_CLAUDE[@]} -gt 0 ] && had=1
  [ ${#DISABLED_AGY[@]} -gt 0 ] && had=1
  [ "$STASHED" -eq 1 ] && had=1
  [ "$had" -eq 0 ] && return 0

  head2 "Restoring your setup"
  local p
  for p in ${DISABLED_CLAUDE[@]+"${DISABLED_CLAUDE[@]}"}; do
    claude plugin enable "$p" >/dev/null 2>&1 && ok "re-enabled claude plugin $p" || warn "could not re-enable claude plugin $p"
  done
  for p in ${DISABLED_AGY[@]+"${DISABLED_AGY[@]}"}; do
    agy plugin enable "$p" >/dev/null 2>&1 && ok "re-enabled agy plugin $p" || warn "could not re-enable agy plugin $p"
  done
  if [ "$STASHED" -eq 1 ] && [ -d "$STASH" ]; then
    local n
    for n in "$STASH"/*; do
      [ -e "$n" ] || continue
      rm -f "$SKILL_HOME/$(basename "$n")"
      mv "$n" "$SKILL_HOME/" && ok "restored symlink $(basename "$n")"
    done
    rmdir "$STASH" 2>/dev/null || true
  fi
}
trap restore EXIT INT TERM

isolate() {
  head2 "Isolating skill sources (so results mean something)"

  # Installed plugins that could shadow the working tree.
  if command -v claude >/dev/null 2>&1; then
    local out
    out=$(claude plugin list 2>/dev/null || true)
    while read -r p; do
      [ -z "$p" ] && continue
      if claude plugin disable "$p" >/dev/null 2>&1; then
        DISABLED_CLAUDE+=("$p"); ok "disabled claude plugin $p"
      fi
    done < <(echo "$out" | grep -oE '[a-z0-9-]*foundry[a-z0-9-]*' | sort -u)
  fi
  if command -v agy >/dev/null 2>&1; then
    while read -r p; do
      [ -z "$p" ] && continue
      if agy plugin disable "$p" >/dev/null 2>&1; then
        DISABLED_AGY+=("$p"); ok "disabled agy plugin $p"
      fi
    done < <(agy plugin list 2>/dev/null | grep -oE '"name": *"[^"]*foundry[^"]*"' | sed 's/.*: *"//;s/"//' | sort -u)
  fi

  # Copilot and Cursor cannot disable, only uninstall — too destructive to do
  # automatically. Warn instead, since --plugin-dir should win anyway.
  if command -v copilot >/dev/null 2>&1 && copilot plugin list 2>/dev/null | grep -qi foundry; then
    warn "copilot has a Foundry plugin installed and cannot disable it"
    info "--plugin-dir should take precedence; uninstall manually for a fully clean run"
  fi

  # Symlinks in ~/.agents/skills pointing into THIS repo. These are live, so they
  # would double-load alongside --plugin-dir.
  if [ -d "$SKILL_HOME" ]; then
    mkdir -p "$STASH"
    local link target
    for link in "$SKILL_HOME"/*; do
      [ -L "$link" ] || continue
      target=$(readlink "$link")
      case "$target" in
        "$REPO"/*) mv "$link" "$STASH/" && STASHED=1 && ok "stashed symlink $(basename "$link")" ;;
      esac
    done
    [ "$STASHED" -eq 0 ] && rmdir "$STASH" 2>/dev/null || true
  fi

  if [ ${#DISABLED_CLAUDE[@]} -eq 0 ] && [ ${#DISABLED_AGY[@]} -eq 0 ] && [ "$STASHED" -eq 0 ]; then
    ok "nothing to isolate — no competing sources found"
  fi
  return 0
}

# Codex and Antigravity have no --plugin-dir, so give them the one source they do
# read: symlinks into the working tree, created fresh for this run.
link_repo_skills() {
  mkdir -p "$SKILL_HOME"
  local d
  for d in "$REPO"/skills/*/; do
    ln -sfn "${d%/}" "$SKILL_HOME/$(basename "${d%/}")"
  done
}
unlink_repo_skills() {
  local d
  for d in "$REPO"/skills/*/; do
    rm -f "$SKILL_HOME/$(basename "${d%/}")"
  done
}

if [ "$ISOLATE" -eq 1 ]; then
  isolate
else
  warn "bias control skipped (--no-isolate): results may reflect an installed copy"
fi

# ── Assistants ─────────────────────────────────────────────────
# name|binary|source|argv   (%%PROMPT%% substituted at run time)
#
# Codex gets no sandbox-bypass flag on purpose. Its sandbox is what breaks the
# CLI's token-cache write, so bypassing it would make this pass while users fail.
ASSISTANTS=(
  "Claude Code|claude|--plugin-dir|-p %%PROMPT%% --plugin-dir $REPO --dangerously-skip-permissions"
  "Codex|codex|~/.agents/skills|exec %%PROMPT%%"
  "Copilot CLI|copilot|--plugin-dir|-p %%PROMPT%% --plugin-dir $REPO --allow-all"
  "Cursor|agent|--plugin-dir|-p %%PROMPT%% --plugin-dir $REPO --force"
  "Antigravity CLI|agy|~/.agents/skills|-p %%PROMPT%% --dangerously-skip-permissions"
)

want() {
  [ ${#ONLY[@]} -eq 0 ] && return 0
  local n="$1" o
  for o in "${ONLY[@]}"; do [[ "${n,,}" == *"${o,,}"* ]] && return 0; done
  return 1
}

# A hard failure anywhere outweighs a success line: assistants often retry and
# print both, and we care whether the run hit a wall at all.
classify() {
  local log="$1" rc="$2"
  grep -qiE "unknown flag|unknown command" "$log" 2>/dev/null && { echo "FAIL|bad flag or unsupported command"; return; }
  grep -qi  "connection issue"            "$log" 2>/dev/null && { echo "FAIL|connection issue (denied token-cache write?)"; return; }
  grep -qiE "no profiles found|no active profile" "$log" 2>/dev/null && { echo "FAIL|no usable Foundry profile"; return; }
  grep -qE  "APP ID|App ID"               "$log" 2>/dev/null && { echo "PASS|listed apps"; return; }
  { [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; } && { echo "TIMEOUT|exceeded ${TIMEOUT}s"; return; }
  [ "$rc" -ne 0 ] && { echo "FAIL|exited $rc without reaching the tenant"; return; }
  echo "UNKNOWN|finished but printed no app list"
}

head2 "Running"
info "tenant check: foundry apps list · timeout ${TIMEOUT}s · logs in ${LOG_DIR/#$HOME/\~}"
printf '\n'

RESULTS=(); FAILURES=0; TESTED=0

for entry in "${ASSISTANTS[@]}"; do
  IFS='|' read -r name bin source argv <<< "$entry"
  want "$name" || continue

  if ! command -v "$bin" >/dev/null 2>&1; then
    printf '  %s%-16s SKIP%s    %s not installed\n' "$DIM" "$name" "$RESET" "$bin"
    RESULTS+=("$name|SKIP|not installed|0|none")
    continue
  fi

  # Assistants without --plugin-dir need the symlinks in place for their run only.
  if [ "$source" = "~/.agents/skills" ]; then link_repo_skills; fi

  if [ "$EXPIRE_TOKEN" -eq 1 ]; then rm -f "$HOME/.config/foundry/token.json"; fi

  log="$LOG_DIR/${bin}.log"
  printf '  %s%-16s%s running… ' "$BLUE" "$name" "$RESET"

  read -r -a parts <<< "$argv"
  cmd=("$bin")
  for p in "${parts[@]}"; do
    if [ "$p" = "%%PROMPT%%" ]; then cmd+=("$PROMPT"); else cmd+=("$p"); fi
  done

  start=$(date +%s)
  ( cd "$LOG_DIR" && env -u CLAUDECODE "$TIMEOUT_BIN" "$TIMEOUT" "${cmd[@]}" ) > "$log" 2>&1
  rc=$?
  elapsed=$(( $(date +%s) - start ))

  if [ "$source" = "~/.agents/skills" ]; then unlink_repo_skills; fi

  IFS='|' read -r status detail <<< "$(classify "$log" "$rc")"
  case "$status" in
    PASS)    printf '\r  %s%-16s%s %s%sPASS%s    %-42s %s%ss%s\n' \
               "$BOLD" "$name" "$RESET" "$BOLD" "$GREEN" "$RESET" "$detail" "$DIM" "$elapsed" "$RESET" ;;
    TIMEOUT) printf '\r  %s%-16s%s %s%sTIMEOUT%s %-42s %s%ss%s\n' \
               "$BOLD" "$name" "$RESET" "$BOLD" "$YELLOW" "$RESET" "$detail" "$DIM" "$elapsed" "$RESET"
             FAILURES=$((FAILURES+1)) ;;
    *)       printf '\r  %s%-16s%s %s%sFAIL%s    %s%-42s%s %s%ss%s\n' \
               "$BOLD" "$name" "$RESET" "$BOLD" "$RED" "$RESET" "$RED" "$detail" "$RESET" "$DIM" "$elapsed" "$RESET"
             FAILURES=$((FAILURES+1)) ;;
  esac
  info "source: $source · log: ${log/#$HOME/\~}"

  RESULTS+=("$name|$status|$detail|$elapsed|$source")
  TESTED=$((TESTED+1))
done

head2 "Summary"
if [ "$TESTED" -eq 0 ]; then
  printf '  no assistants tested\n'
elif [ "$FAILURES" -eq 0 ]; then
  printf '  %sall %s tested assistant(s) reached the tenant%s\n' "$GREEN" "$TESTED" "$RESET"
else
  printf '  %s%s of %s failed%s\n' "$RED" "$FAILURES" "$TESTED" "$RESET"
  info 'A "connection issue" failure usually means the sandbox denied the CLI its'
  info 'token-cache write to ~/.config/foundry/ — see debugging-workflows.'
  [ "$EXPIRE_TOKEN" -eq 0 ] && info 'Re-run with --expire-token to force that path on every trial.'
fi

if [ -n "$SAVE_FILE" ]; then
  {
    printf '{\n  "timeout": %s,\n  "isolated": %s,\n  "expire_token": %s,\n  "results": [\n' \
      "$TIMEOUT" "$ISOLATE" "$EXPIRE_TOKEN"
    first=1
    for r in "${RESULTS[@]}"; do
      IFS='|' read -r n s d e src <<< "$r"
      [ $first -eq 0 ] && printf ',\n'; first=0
      printf '    {"assistant": "%s", "status": "%s", "detail": "%s", "seconds": %s, "source": "%s"}' \
        "$n" "$s" "$d" "$e" "$src"
    done
    printf '\n  ]\n}\n'
  } > "$SAVE_FILE"
  info "saved $SAVE_FILE"
fi

printf '\n'
[ "$FAILURES" -eq 0 ]
