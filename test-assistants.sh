#!/usr/bin/env bash
#
# test-assistants.sh — Smoke-test every assistant in the README against a live tenant.
#
# Each assistant is asked to perform the prerequisite check *as the skill defines it*,
# without being told which commands those are, and to cite the SKILL.md it used.
# A pass therefore needs both: the skill was read, and the tenant was reached. That command is the earliest reliable failure signal: it is
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
#   ./test-assistants.sh --verbose            # list every plugin and symlink touched
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
VERBOSE=0
LOG_DIR="/tmp/foundry-assistant-test"
SKILL_HOME="$HOME/.agents/skills"
STASH="$LOG_DIR/stashed-symlinks"

# The prompt deliberately does NOT name the commands. Naming them would let an
# assistant with no skills loaded pass, which tells us nothing. "CLI prerequisite
# check" is development-workflow's own vocabulary, so knowing which commands it
# means requires having read the skill. Asking it to name the skill file gives a
# second, independent signal.
PROMPT="Using the Falcon Foundry skills, perform the CLI prerequisite check from the development-workflow skill. Run exactly the commands that skill specifies and print each one's raw output verbatim. Do NOT create, deploy, or release anything. Finish by stating the path of the SKILL.md file you used."

while [[ $# -gt 0 ]]; do
  case "$1" in
    --only)         ONLY+=("$2"); shift 2 ;;
    --timeout)      TIMEOUT="$2"; shift 2 ;;
    --save)         SAVE_FILE="$2"; shift 2 ;;
    --prompt)       PROMPT="$2"; shift 2 ;;
    --no-isolate)   ISOLATE=0; shift ;;
    -v|--verbose)   VERBOSE=1; shift ;;
    --expire-token) EXPIRE_TOKEN=1; shift ;;
    -h|--help)      sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'
BLUE=$'\033[0;34m'; MAGENTA=$'\033[0;35m'; CYAN=$'\033[0;36m'
DIM=$'\033[2m'; BOLD=$'\033[1m'; RESET=$'\033[0m'

ok()   { printf '  %s✓%s  %s\n' "$GREEN" "$RESET" "$1"; }
# Per-item bookkeeping: shown only with --verbose, so 20 lines of checkmarks don't
# bury 5 lines of actual results.
vok()  { [ "$VERBOSE" -eq 1 ] && printf '  %s✓%s  %s%s%s\n' "$GREEN" "$RESET" "$DIM" "$1" "$RESET"; return 0; }
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
  [ "$STASHED" -gt 0 ] && had=1
  [ "$had" -eq 0 ] && return 0

  head2 "Restoring your setup"
  local p
  for p in ${DISABLED_CLAUDE[@]+"${DISABLED_CLAUDE[@]}"}; do
    claude plugin enable "$p" >/dev/null 2>&1 && vok "re-enabled claude plugin $p" || warn "could not re-enable claude plugin $p"
  done
  for p in ${DISABLED_AGY[@]+"${DISABLED_AGY[@]}"}; do
    agy plugin enable "$p" >/dev/null 2>&1 && vok "re-enabled agy plugin $p" || warn "could not re-enable agy plugin $p"
  done
  if [ "$STASHED" -gt 0 ] && [ -d "$STASH" ]; then
    local n
    for n in "$STASH"/*; do
      [ -e "$n" ] || continue
      rm -f "$SKILL_HOME/$(basename "$n")"
      mv "$n" "$SKILL_HOME/" && vok "restored symlink $(basename "$n")"
    done
    rmdir "$STASH" 2>/dev/null || true
  fi
  local plugins=$(( ${#DISABLED_CLAUDE[@]} + ${#DISABLED_AGY[@]} ))
  printf '  %s✓%s  re-enabled %s%s%s plugin(s), restored %s%s%s symlink(s)\n' \
    "$GREEN" "$RESET" "$BOLD" "$plugins" "$RESET" "$BOLD" "$STASHED" "$RESET"
}

# Ctrl-C must kill the assistant that is actually running, not just this script.
# The child runs in the background so it has its own PID we can signal; without
# that, the signal lands on the wrapper, the assistant keeps going, and the loop
# moves on to the next one.
CHILD_PID=""
on_interrupt() {
  printf '\n  %s▲%s  interrupted — stopping the current assistant\n' "$YELLOW" "$RESET"
  if [ -n "$CHILD_PID" ]; then
    pkill -TERM -P "$CHILD_PID" 2>/dev/null || true
    kill -TERM "$CHILD_PID" 2>/dev/null || true
    sleep 0.5
    pkill -KILL -P "$CHILD_PID" 2>/dev/null || true
    kill -KILL "$CHILD_PID" 2>/dev/null || true
  fi
  # restore still runs, via the EXIT trap.
  exit 130
}
trap on_interrupt INT TERM
trap restore EXIT

isolate() {
  head2 "Isolating skill sources (so results mean something)"

  # Installed plugins that could shadow the working tree.
  if command -v claude >/dev/null 2>&1; then
    local out
    out=$(claude plugin list 2>/dev/null || true)
    while read -r p; do
      [ -z "$p" ] && continue
      if claude plugin disable "$p" >/dev/null 2>&1; then
        DISABLED_CLAUDE+=("$p"); vok "disabled claude plugin $p"
      fi
    done < <(echo "$out" | grep -oE '[a-z0-9-]*foundry[a-z0-9-]*' | sort -u)
  fi
  if command -v agy >/dev/null 2>&1; then
    while read -r p; do
      [ -z "$p" ] && continue
      if agy plugin disable "$p" >/dev/null 2>&1; then
        DISABLED_AGY+=("$p"); vok "disabled agy plugin $p"
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
        "$REPO"/*) mv "$link" "$STASH/" && STASHED=$((STASHED+1)) && vok "stashed symlink $(basename "$link")" ;;
      esac
    done
    [ "$STASHED" -eq 0 ] && rmdir "$STASH" 2>/dev/null || true
  fi

  local plugins=$(( ${#DISABLED_CLAUDE[@]} + ${#DISABLED_AGY[@]} ))
  if [ "$plugins" -eq 0 ] && [ "$STASHED" -eq 0 ]; then
    ok "nothing to isolate — no competing sources found"
  else
    printf '  %s✓%s  disabled %s%s%s plugin(s), stashed %s%s%s symlink(s)\n' \
      "$GREEN" "$RESET" "$BOLD" "$plugins" "$RESET" "$BOLD" "$STASHED" "$RESET"
    [ "$VERBOSE" -eq 0 ] && info "run with --verbose to list each one"
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
  "Codex|codex|~/.agents/skills|exec %%PROMPT%% --skip-git-repo-check"
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

# Returns STATUS|CATEGORY|detail. The category is the trackable part: it says which
# known failure mode was hit, so counts can be compared across runs and branches.
#
# Assistants echo skill text into their output, and that text discusses these very
# errors ("...fail with `unknown flag`"). Matching bare phrases therefore reports
# our own documentation as a failure. So: strip markdown-quoted lines, anchor on the
# CLI's actual `Error:` prefix, and treat a real app table as decisive proof the
# tenant was reached.
classify() {
  local log="$1" rc="$2" body
  body=$(grep -v '^\s*>' "$log" 2>/dev/null)

  # Two independent signals. The app table proves the tenant was reached; a cited
  # SKILL.md path proves the skill was actually read rather than the commands
  # guessed. Tenant-only is reported separately so it is not mistaken for a pass.
  local reached=0 cited=0
  grep -qE "^\s*\|\s*APP ID|^Apps:" <<< "$body" && reached=1
  grep -qiE "development-workflow/SKILL\.md|skills/development-workflow" <<< "$body" && cited=1
  if [ "$reached" -eq 1 ] && [ "$cited" -eq 1 ]; then
    echo "PASS|ok|used the skill, listed apps"; return
  fi
  if [ "$reached" -eq 1 ]; then
    echo "FAIL|no-skill|reached tenant but never cited the skill"; return
  fi

  grep -qiE "Error: unknown (flag|command)"        <<< "$body" && { echo "FAIL|flag|rejected a CLI flag"; return; }
  grep -qiE "Error:.*connection issue|^\s*\* connection issue" <<< "$body" && { echo "FAIL|connection|connection issue (denied token-cache write?)"; return; }
  grep -qiE "Error: no TTY available|could not open a new TTY|/dev/tty: device not configured" <<< "$body" && { echo "FAIL|tty|CLI demanded a TTY"; return; }
  grep -qiE "Not inside a trusted directory"       <<< "$body" && { echo "FAIL|trust|refused to run in this directory"; return; }
  grep -qiE "Error:.*no profiles found|no active profile" <<< "$body" && { echo "FAIL|profile|no usable Foundry profile"; return; }

  { [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; } && { echo "TIMEOUT|timeout|exceeded ${TIMEOUT}s"; return; }
  [ "$rc" -ne 0 ] && { echo "FAIL|other|exited $rc without reaching the tenant"; return; }
  echo "UNKNOWN|other|finished but printed no app list"
}

head2 "Running"
info "tenant check: foundry apps list · timeout ${TIMEOUT}s · logs in ${LOG_DIR/#$HOME/\~}"
printf '\n'

RESULTS=(); CATEGORIES=(); FAILURES=0; TESTED=0

for entry in "${ASSISTANTS[@]}"; do
  IFS='|' read -r name bin source argv <<< "$entry"
  want "$name" || continue

  if ! command -v "$bin" >/dev/null 2>&1; then
    printf '  %s%-16s SKIP%s    %s not installed\n' "$DIM" "$name" "$RESET" "$bin"
    RESULTS+=("$name|SKIP|skip|not installed|0|none")
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
  # Background + wait, so Ctrl-C has a PID to kill (see on_interrupt).
  ( cd "$LOG_DIR" && env -u CLAUDECODE "$TIMEOUT_BIN" "$TIMEOUT" "${cmd[@]}" ) > "$log" 2>&1 &
  CHILD_PID=$!
  wait "$CHILD_PID"
  rc=$?
  CHILD_PID=""
  elapsed=$(( $(date +%s) - start ))

  if [ "$source" = "~/.agents/skills" ]; then unlink_repo_skills; fi

  IFS='|' read -r status category detail <<< "$(classify "$log" "$rc")"
  case "$status" in
    PASS)    printf '\r  %s%-16s%s %s%sPASS%s    %-42s %s%ss%s\n' \
               "$BOLD" "$name" "$RESET" "$GREEN$BOLD" "$RESET" "$detail" "$DIM" "$elapsed" "$RESET" ;;
    TIMEOUT) printf '\r  %s%-16s%s %s%sTIMEOUT%s %-42s %s%ss%s\n' \
               "$BOLD" "$name" "$RESET" "$YELLOW$BOLD" "$RESET" "$detail" "$DIM" "$elapsed" "$RESET"
             FAILURES=$((FAILURES+1)) ;;
    *)       printf '\r  %s%-16s%s %s%sFAIL%s    %s%-42s%s %s%ss%s\n' \
               "$BOLD" "$name" "$RESET" "$RED$BOLD" "$RESET" "$RED" "$detail" "$RESET" "$DIM" "$elapsed" "$RESET"
             FAILURES=$((FAILURES+1)) ;;
  esac
  info "source: $source · log: ${log/#$HOME/\~}"

  [ "$status" != "PASS" ] && CATEGORIES+=("$category")
  RESULTS+=("$name|$status|$category|$detail|$elapsed|$source")
  TESTED=$((TESTED+1))
done

head2 "Summary"
if [ "$TESTED" -eq 0 ]; then
  printf '  no assistants tested\n'
elif [ "$FAILURES" -eq 0 ]; then
  printf '  %s%s%s%s of %s reached the tenant%s\n' \
    "$GREEN" "$BOLD" "$TESTED" "$RESET$GREEN" "$TESTED" "$RESET"
else
  printf '  %s%s%s%s of %s reached the tenant%s  %s·%s  %s%s%s%s failed%s\n' \
    "$GREEN" "$BOLD" "$((TESTED-FAILURES))" "$RESET$GREEN" "$TESTED" "$RESET" \
    "$DIM" "$RESET" "$RED" "$BOLD" "$FAILURES" "$RESET$RED" "$RESET"
  printf '\n  %sfailures by cause%s\n' "$BOLD" "$RESET"
  # Counts per known failure mode, worth tracking run to run.
  printf '%s\n' ${CATEGORIES[@]+"${CATEGORIES[@]}"} | sort | uniq -c | sort -rn | while read -r n cat; do
    case "$cat" in
      no-skill)   label="tenant reached, but the skill was not used"   ; col=$MAGENTA ;;
      connection) label="connection issue — denied token-cache write" ; col=$RED ;;
      tty)        label="TTY demanded by the CLI"                     ; col=$MAGENTA ;;
      flag)       label="unsupported CLI flag"                        ; col=$YELLOW ;;
      trust)      label="refused to run in the test directory"        ; col=$YELLOW ;;
      profile)    label="no usable Foundry profile"                   ; col=$YELLOW ;;
      timeout)    label="timed out"                                   ; col=$YELLOW ;;
      *)          label="other"                                       ; col=$DIM ;;
    esac
    printf '    %s%s×%s %s%s%s\n' "$BOLD" "$n" "$RESET" "$col" "$label" "$RESET"
  done
  printf '\n'
  if printf '%s\n' ${CATEGORIES[@]+"${CATEGORIES[@]}"} | grep -qx connection; then
    info 'A connection issue means the sandbox denied the CLI its token-cache'
    info 'write to ~/.config/foundry/ — see debugging-workflows.'
    [ "$EXPIRE_TOKEN" -eq 0 ] && info 'Re-run with --expire-token to force that path on every trial.'
  else
    info 'No connection or TTY failures. Read the logs above.'
  fi
fi

if [ -n "$SAVE_FILE" ]; then
  {
    printf '{\n  "timeout": %s,\n  "isolated": %s,\n  "expire_token": %s,\n  "results": [\n' \
      "$TIMEOUT" "$ISOLATE" "$EXPIRE_TOKEN"
    first=1
    for r in "${RESULTS[@]}"; do
      IFS='|' read -r n st cat d e src <<< "$r"
      [ $first -eq 0 ] && printf ',\n'; first=0
      printf '    {"assistant": "%s", "status": "%s", "category": "%s", "detail": "%s", "seconds": %s, "source": "%s"}' \
        "$n" "$st" "$cat" "$d" "$e" "$src"
    done
    printf '\n  ]\n}\n'
  } > "$SAVE_FILE"
  info "saved $SAVE_FILE"
fi

printf '\n'
[ "$FAILURES" -eq 0 ]
