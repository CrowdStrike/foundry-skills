#!/usr/bin/env bash
#
# test-assistants.sh — Smoke-test every assistant in the README against a live tenant.
#
# Each assistant gets the real app-creation prompt from the README, plus one
# instruction the README does not need: work for about a minute, then stop and say
# what happened. We are not waiting for a finished app (that takes ~3 minutes). We
# are looking for the failures that bite in the first minute — a denied token-cache
# write, a rejected flag, a TTY demand, a missing profile.
#
# The assistant reports back rather than being cut off mid-thought, which is the
# whole trick: the harness is talking to something that can describe its own state,
# so it asks. Every run ends in a fixed five-line report naming the skills that
# loaded, the `foundry` commands that ran and how each one went, and any blocker.
# Classification reads that report. Inferring the outcome by grepping a truncated
# transcript — and calling a clean timeout a pass — could not tell "still building"
# apart from "sat there doing nothing", which is exactly the case that matters.
#
# The timeout is now a safety net rather than the measurement. Assistants stop on
# their own at the report deadline, so a healthy run finishes well inside it.
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
# Everything is restored on exit, including on Ctrl-C, and a stash orphaned by a run
# that was killed before it could tidy up is recovered at startup.
#
# Usage:
#   ./test-assistants.sh                      # test every installed assistant
#   ./test-assistants.sh --only codex         # test one (repeatable)
#   ./test-assistants.sh --report-at 90       # ask for the report later (default 60s)
#   ./test-assistants.sh --timeout 300        # raise the hard cap (default 120s)
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
REPORT_AT=60
TIMEOUT=120
SAVE_FILE=""
ONLY=()
ISOLATE=1
EXPIRE_TOKEN=0
VERBOSE=0
LOG_DIR="/tmp/foundry-assistant-test"
SKILL_HOME="$HOME/.agents/skills"
STASH="$LOG_DIR/stashed-symlinks"
CODEX_CACHE_STASH="$LOG_DIR/stashed-codex-cache"
CODEX_CACHE_ORIGIN="$LOG_DIR/stashed-codex-cache.origin"

# The real app-creation prompt, matching the README example and test-skill.sh.
# It names no `foundry` commands, so an assistant with no skills loaded cannot fake
# its way through — which is exactly what makes it a skills test rather than a CLI
# test. CI asserts this line still starts with the README text, so keep additions
# out of it: the reporting instructions are appended at run time instead.
PROMPT="Create a Falcon Foundry app for me that has an Okta API integration with openapi. Share its listusers endpoint with Falcon Fusion SOAR. Then, create a workflow that can be run on-demand to email or print the list of users. Finally, create a UI extension that calls the listusers endpoint and displays the results. Pick a reasonable app name and proceed without asking me any questions."

# What turns a transcript into a result. Appended to the prompt above, never spliced
# into it.
#
# Three details in here are load-bearing. The labels are asked for as plain lines,
# because the classifier drops blockquoted lines and a report wrapped in `>` would
# vanish with them. The fields below are described in angle brackets and a real
# report contains none, so a log that merely echoes the prompt back — Codex prints
# the whole thing — cannot be mistaken for a report. And the deadline is stated as
# wall clock with `date` offered as the way to read it, because an assistant has no
# other clock and will otherwise keep going until something kills it.
report_instructions() {
  cat <<EOF

Two more things, because this is a timed test harness rather than a real build.

Do not try to finish the app. You have about ${REPORT_AT} seconds of wall clock; run \`date\`
if you need to know where you are. When that is up, stop wherever you have got to and
report. Report early — right away — if something blocks you, if you find yourself
about to ask me a question, or if you sense you are about to be interrupted. The
report is worth more to me than the extra progress.

To report, end your reply with these five lines, in this order, each starting a line
of plain text. No code fence, no blockquote, no bullets, no bold, and no angle
brackets in anything you write:

FOUNDRY-REPORT
STATUS: <one word — WORKING if the CLI is doing real work, BLOCKED if something stopped you, DONE if the app is built>
SKILLS: <comma-separated paths of the skill files you loaded, or NONE>
COMMANDS: <comma-separated, every foundry command you ran, each written as the command followed by => OK or => FAIL: reason. NONE if you ran none>
BLOCKER: <one line naming what stopped you, quoting the CLI error text verbatim if there was one. NONE if nothing did>
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --only)         ONLY+=("$2"); shift 2 ;;
    --report-at)    REPORT_AT="$2"; shift 2 ;;
    --timeout)      TIMEOUT="$2"; shift 2 ;;
    --save)         SAVE_FILE="$2"; shift 2 ;;
    --prompt)       PROMPT="$2"; shift 2 ;;
    --no-isolate)   ISOLATE=0; shift ;;
    -v|--verbose)   VERBOSE=1; shift ;;
    --expire-token) EXPIRE_TOKEN=1; shift ;;
    -h|--help)      sed -n '2,50p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

# The cap has to leave room for the report to be written after the deadline, or the
# harness kills the assistant mid-sentence and we are back to guessing.
if [ "$TIMEOUT" -le "$REPORT_AT" ]; then
  TIMEOUT=$(( REPORT_AT + 30 ))
fi

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
OURS=()                 # symlinks this script created, so we only ever remove our own
CODEX_CACHE=""          # moved-aside Codex plugin cache, restored on exit

# True if the path is a symlink into this repo — i.e. one of ours, safe to discard.
points_into_repo() {
  local target
  target=$(readlink "$1" 2>/dev/null) || return 1
  case "$target" in "$REPO"/*) return 0 ;; *) return 1 ;; esac
}

restore() {
  local had=0
  [ ${#DISABLED_CLAUDE[@]} -gt 0 ] && had=1
  [ ${#DISABLED_AGY[@]} -gt 0 ] && had=1
  [ "$STASHED" -gt 0 ] && had=1
  [ -n "$CODEX_CACHE" ] && had=1
  [ "$had" -eq 0 ] && return 0

  head2 "Restoring your setup"
  local p
  for p in ${DISABLED_CLAUDE[@]+"${DISABLED_CLAUDE[@]}"}; do
    claude plugin enable "$p" >/dev/null 2>&1 && vok "re-enabled claude plugin $p" || warn "could not re-enable claude plugin $p"
  done
  for p in ${DISABLED_AGY[@]+"${DISABLED_AGY[@]}"}; do
    agy plugin enable "$p" >/dev/null 2>&1 && vok "re-enabled agy plugin $p" || warn "could not re-enable agy plugin $p"
  done
  if [ -n "$CODEX_CACHE" ] && [ -d "$CODEX_CACHE_STASH" ]; then
    rm -rf "$CODEX_CACHE"
    mv "$CODEX_CACHE_STASH" "$CODEX_CACHE" && vok "restored Codex plugin cache"
    rm -f "$CODEX_CACHE_ORIGIN"
  fi
  if [ "$STASHED" -gt 0 ] && [ -d "$STASH" ]; then
    local n
    for n in "$STASH"/*; do
      [ -e "$n" ] || [ -L "$n" ] || continue
      rm -f "$SKILL_HOME/$(basename "$n")"
      mv "$n" "$SKILL_HOME/" && vok "restored symlink $(basename "$n")"
    done
    rmdir "$STASH" 2>/dev/null || true
  fi
  local plugins=$(( ${#DISABLED_CLAUDE[@]} + ${#DISABLED_AGY[@]} ))
  printf '  %s✓%s  re-enabled %s%s%s plugin(s), restored %s%s%s symlink(s)\n' \
    "$GREEN" "$RESET" "$BOLD" "$plugins" "$RESET" "$BOLD" "$STASHED" "$RESET"
}

# A run killed between stashing and restoring leaves your symlinks in $STASH and,
# worse, this run would overwrite them with its own copies. Nothing else on the
# machine will ever put them back, so recover them before touching anything.
recover_orphans() {
  local n base recovered=0 kept=0
  if [ -d "$STASH" ]; then
    for n in "$STASH"/*; do
      [ -e "$n" ] || [ -L "$n" ] || continue
      base=$(basename "$n")
      # A symlink into this repo at that name is a leftover of the interrupted run,
      # not something of yours. Anything else, leave alone and keep the orphan safe.
      points_into_repo "$SKILL_HOME/$base" && rm -f "$SKILL_HOME/$base"
      if [ -e "$SKILL_HOME/$base" ] || [ -L "$SKILL_HOME/$base" ]; then
        kept=$((kept+1)); continue
      fi
      mkdir -p "$SKILL_HOME"
      mv "$n" "$SKILL_HOME/" && recovered=$((recovered+1)) && vok "recovered symlink $base"
    done
    rmdir "$STASH" 2>/dev/null || true
  fi
  # Same hazard, bigger blast radius: an orphaned plugin cache means Codex is quietly
  # running with no plugins at all until someone reinstalls them.
  if [ -d "$CODEX_CACHE_STASH" ] && [ -f "$CODEX_CACHE_ORIGIN" ]; then
    local origin
    origin=$(cat "$CODEX_CACHE_ORIGIN")
    if [ -n "$origin" ] && [ ! -e "$origin" ]; then
      mkdir -p "$(dirname "$origin")"
      if mv "$CODEX_CACHE_STASH" "$origin"; then
        rm -f "$CODEX_CACHE_ORIGIN"
        recovered=$((recovered+1)); vok "recovered Codex plugin cache"
      fi
    fi
  fi
  [ "$recovered" -gt 0 ] && warn "recovered $recovered item(s) left behind by an interrupted run"
  [ "$kept" -gt 0 ] && warn "$kept stashed symlink(s) left in ${STASH/#$HOME/\~} — something else holds their names"
  return 0
}

# Ctrl-C must kill the assistant that is actually running, not just this script.
# The child runs in the background so it has its own PID we can signal; without
# that, the signal lands on the wrapper, the assistant keeps going, and the loop
# moves on to the next one.
CHILD_PID=""
INTERRUPTED=0
on_interrupt() {
  # Second Ctrl-C: give up on tidiness and leave now.
  if [ "$INTERRUPTED" -eq 1 ]; then
    printf '\n  %s▲%s  forcing exit\n' "$YELLOW" "$RESET"
    [ -n "$CHILD_PID" ] && kill -KILL -- -"$CHILD_PID" 2>/dev/null
    exit 130
  fi
  INTERRUPTED=1
  printf '\n  %s▲%s  stopping the assistant (Ctrl-C again to force)\n' "$YELLOW" "$RESET"
  if [ -n "$CHILD_PID" ]; then
    # Signal the whole process group, not just the job. Assistants spawn node, npm,
    # and the Foundry CLI; killing only the direct child leaves those running and
    # the script appears to hang.
    kill -TERM -- -"$CHILD_PID" 2>/dev/null || kill -TERM "$CHILD_PID" 2>/dev/null || true
    for _ in 1 2 3 4 5 6; do
      kill -0 -- -"$CHILD_PID" 2>/dev/null || break
      sleep 0.25
    done
    kill -KILL -- -"$CHILD_PID" 2>/dev/null || true
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

  # Codex has no `plugin disable`, and it loads the plugin cache *and*
  # ~/.agents/skills at once, so leaving the cache in place would defeat the whole
  # exercise. Move the directory aside rather than uninstalling; it is restored on
  # exit, so no reinstall is needed.
  local cc
  for cc in "$HOME"/.codex/plugins/cache/*/; do
    [ -d "$cc" ] || continue
    if find "$cc" -maxdepth 1 -name '*foundry*' -print -quit 2>/dev/null | grep -q .; then
      CODEX_CACHE="${cc%/}"
      rm -rf "$CODEX_CACHE_STASH"
      if mv "$CODEX_CACHE" "$CODEX_CACHE_STASH" 2>/dev/null; then
        # Record where it came from, so a run that dies before restoring can be
        # cleaned up by the next one instead of leaving Codex plugin-less.
        printf '%s\n' "$CODEX_CACHE" > "$CODEX_CACHE_ORIGIN"
        vok "moved Codex plugin cache aside"
      else
        warn "could not move the Codex plugin cache; its results will be ambiguous"
        CODEX_CACHE=""
      fi
      break
    fi
  done

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
    local link
    for link in "$SKILL_HOME"/*; do
      [ -L "$link" ] || continue
      points_into_repo "$link" || continue
      mv "$link" "$STASH/" && STASHED=$((STASHED+1)) && vok "stashed symlink $(basename "$link")"
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
  mkdir -p "$SKILL_HOME" "$STASH"
  local d n path
  for d in "$REPO"/skills/*/; do
    n=$(basename "${d%/}")
    path="$SKILL_HOME/$n"
    # Anything already at this name belongs to someone else — another clone, or a
    # real directory. Preserve it instead of letting `ln -sfn` destroy it.
    if [ -e "$path" ] || [ -L "$path" ]; then
      if mv "$path" "$STASH/$n" 2>/dev/null; then
        STASHED=$((STASHED+1)); vok "stashed colliding $n"
      else
        warn "could not move aside $n; leaving it alone"
        continue
      fi
    fi
    ln -sfn "${d%/}" "$path" && OURS+=("$n")
  done
}
unlink_repo_skills() {
  # Remove only the symlinks we created. Never touch anything we did not make.
  local n
  for n in ${OURS[@]+"${OURS[@]}"}; do
    [ -L "$SKILL_HOME/$n" ] && rm -f "$SKILL_HOME/$n"
  done
  OURS=()
}

recover_orphans

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

# ── Reading the report ─────────────────────────────────────────

# One line, no pipes or quotes. These strings land in a |-delimited array, a
# fixed-width table, and hand-rolled JSON, and a blocker quoted from the CLI can
# contain any of those characters.
clean() {
  local s max="${2:-72}"
  s=$(printf '%s' "$1" | tr '\r\n\t|"\\' '      ' \
      | sed -E $'s/\033\\[[0-9;]*[A-Za-z]//g; s/  +/ /g; s/^ +//; s/ +$//')
  [ "${#s}" -gt "$max" ] && s="${s:0:$max}…"
  printf '%s' "$s"
}

# The value of one report label, read from the body on stdin.
#
# Two guards. Lines holding an angle bracket are the prompt's own template rather
# than a report — a real report is asked for without any, and Codex echoes the whole
# prompt into its log — so they are dropped outright. And of what survives we take
# the LAST match, because the report is the end of the reply.
report_field() {
  local label="$1"
  grep -v '<' \
    | grep -E "^[^A-Za-z]*${label}\**:" \
    | tail -1 \
    | sed -E "s/^[^A-Za-z]*${label}\**:\**[[:space:]]*//"
}

# Treat an empty, absent, or explicitly-nothing field as nothing.
is_none() {
  local v="${1^^}"
  [ -z "$v" ] || [[ "$v" =~ ^(NONE|N/A|NA|NOTHING|-)[.]?$ ]]
}

# Which known failure mode a self-reported blocker describes. Bare phrases are safe
# to match here, unlike in the log scan below: this is one line the assistant wrote
# about itself, with the prompt's own template already filtered out.
blocker_category() {
  local t="$1"
  grep -qiE 'unknown (flag|command)|unsupported flag'          <<< "$t" && { echo flag;       return; }
  grep -qiE 'connection issue|token\.json|token cache|denied.*(write|permission)' <<< "$t" && { echo connection; return; }
  grep -qiE '\btty\b|terminal device|/dev/tty'                 <<< "$t" && { echo tty;        return; }
  grep -qiE 'trusted directory|not trusted'                    <<< "$t" && { echo trust;      return; }
  grep -qiE 'profile'                                          <<< "$t" && { echo profile;    return; }
  grep -qiE '\bEOF\b'                                          <<< "$t" && { echo eof;        return; }
  echo other
}

# Returns STATUS|CATEGORY|detail|skills|commands. The category is the trackable part:
# it says which known failure mode was hit, so counts can be compared across runs and
# branches.
#
# Two sources, in this order. First the log, for the handful of CLI errors that are
# decisive whatever the assistant believes happened — anchored on the CLI's real
# `Error:` prefix, because assistants echo skill text that discusses these same
# strings and matching bare phrases reports our own documentation as a failure. Then
# the assistant's own report, which is what decides everything else. Nothing is
# inferred from how far the transcript got: that could not tell "still building" from
# "sat there doing nothing", and it read a clean timeout as success.
classify() {
  local log="$1" rc="$2" body status skills raw_cmds raw_blocker cmds detail cat
  body=$(grep -v '^[[:space:]]*>' "$log" 2>/dev/null)

  grep -qiE "^[[:space:]]*(❌[[:space:]]*)?Error: unknown (flag|command)" <<< "$body" && { echo "FAIL|flag|rejected a CLI flag||"; return; }
  grep -qiE "^[[:space:]]*(❌[[:space:]]*)?Error:.*connection issue|^[[:space:]]*\* connection issue" <<< "$body" && { echo "FAIL|connection|connection issue (denied token-cache write?)||"; return; }
  grep -qiE "^[[:space:]]*(❌[[:space:]]*)?Error: no TTY available|^[[:space:]]*(❌[[:space:]]*)?could not open a new TTY|/dev/tty: device not configured" <<< "$body" && { echo "FAIL|tty|CLI demanded a TTY||"; return; }
  grep -qiE "Not inside a trusted directory"       <<< "$body" && { echo "FAIL|trust|refused to run in this directory||"; return; }
  grep -qiE "Error:.*no profiles found|no active profile" <<< "$body" && { echo "FAIL|profile|no usable Foundry profile||"; return; }
  grep -qiE "^[[:space:]]*(❌[[:space:]]*)?Error: EOF" <<< "$body" && { echo "FAIL|eof|interactive prompt hung the CLI||"; return; }

  status=$(report_field STATUS      <<< "$body")
  raw_cmds=$(report_field COMMANDS  <<< "$body")
  raw_blocker=$(report_field BLOCKER <<< "$body")
  skills=$(clean "$(report_field SKILLS <<< "$body")" 54)
  cmds=$(clean "$raw_cmds" 54)

  # Count outcomes on the raw value, before it is truncated for display.
  local oks fails
  oks=$(grep -oiE '=>[[:space:]]*OK' <<< "$raw_cmds" | grep -c .)
  fails=$(grep -oiE '=>[[:space:]]*FAIL' <<< "$raw_cmds" | grep -c .)

  if [ -z "$status" ]; then
    if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
      echo "FAIL|stalled|cut off at ${TIMEOUT}s with no report|$skills|$cmds"; return
    fi
    echo "FAIL|other|stopped without reporting (exit $rc)|$skills|$cmds"; return
  fi

  # A blocker is the result, whatever else the assistant managed to do.
  if grep -qi 'BLOCK' <<< "$status" || ! is_none "$raw_blocker"; then
    cat=$(blocker_category "$raw_blocker")
    detail=$(clean "blocked: ${raw_blocker:-no detail given}" 40)
    echo "FAIL|$cat|$detail|$skills|$cmds"; return
  fi

  # No blocker, so the pass needs evidence — and the report carries it: a `foundry`
  # command the assistant says came back OK.
  if [ "$oks" -gt 0 ]; then
    if grep -qiE 'DONE|COMPLETE|FINISH' <<< "$status"; then
      detail="built the app · ${oks} command(s) OK"
    else
      detail="${oks} foundry command(s) OK, no blocker"
    fi
    echo "PASS|ok|$detail|$skills|$cmds"; return
  fi
  [ "$fails" -gt 0 ] && {
    cat=$(blocker_category "$raw_cmds")
    echo "FAIL|$cat|$(clean "every command failed: $raw_cmds" 40)|$skills|$cmds"; return
  }
  echo "FAIL|stalled|reported $(clean "$status" 12) but ran no commands|$skills|$cmds"
}

head2 "Running"
info "real app-creation prompt · self-report at ${REPORT_AT}s · hard cap ${TIMEOUT}s · logs in ${LOG_DIR/#$HOME/\~}"
printf '\n'

RESULTS=(); CATEGORIES=(); FAILURES=0; TESTED=0

for entry in "${ASSISTANTS[@]}"; do
  IFS='|' read -r name bin source argv <<< "$entry"
  want "$name" || continue

  if ! command -v "$bin" >/dev/null 2>&1; then
    printf '  %s%-16s SKIP%s    %s not installed\n' "$DIM" "$name" "$RESET" "$bin"
    RESULTS+=("$name|SKIP|skip|not installed|0|none|")
    continue
  fi

  # Assistants without --plugin-dir need the symlinks in place for their run only.
  if [ "$source" = "~/.agents/skills" ]; then link_repo_skills; fi

  if [ "$EXPIRE_TOKEN" -eq 1 ]; then rm -f "$HOME/.config/foundry/token.json"; fi

  log="$LOG_DIR/${bin}.log"
  printf '  %s%-16s%s running… ' "$BLUE" "$name" "$RESET"

  read -r -a parts <<< "$argv"
  cmd=("$bin")
  # The canonical prompt, then the reporting instructions. Appended, never spliced:
  # CI asserts the PROMPT line still starts with the README text.
  full_prompt="${PROMPT}
$(report_instructions)"
  for p in "${parts[@]}"; do
    if [ "$p" = "%%PROMPT%%" ]; then cmd+=("$full_prompt"); else cmd+=("$p"); fi
  done

  start=$(date +%s)
  # `set -m` gives the job its own process group, so on_interrupt can signal the
  # entire tree with kill -- -PGID. Without it, Ctrl-C leaves grandchildren alive.
  set -m
  # < /dev/null is load-bearing: `claude -p` reads stdin and, backgrounded without
  # a redirect, blocks waiting for input that never arrives — 120s, zero bytes logged.
  ( cd "$LOG_DIR" && env -u CLAUDECODE "$TIMEOUT_BIN" "$TIMEOUT" "${cmd[@]}" ) < /dev/null > "$log" 2>&1 &
  CHILD_PID=$!
  set +m
  wait "$CHILD_PID"
  rc=$?
  CHILD_PID=""
  elapsed=$(( $(date +%s) - start ))

  if [ "$source" = "~/.agents/skills" ]; then unlink_repo_skills; fi

  IFS='|' read -r status category detail rskills rcmds <<< "$(classify "$log" "$rc")"
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
  # What it said it loaded and ran — the two things worth reading without opening the
  # log, and the pair that shows a pass came from the working tree.
  [ -n "$rskills" ] && info "skills: $rskills"
  [ -n "$rcmds" ]   && info "ran: $rcmds"

  [ "$status" != "PASS" ] && CATEGORIES+=("$category")
  RESULTS+=("$name|$status|$category|$detail|$elapsed|$source|$rskills")
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
      stalled)    label="no report, or no command run before the cap"    ; col=$MAGENTA ;;
      eof)        label="interactive prompt hung the CLI"             ; col=$RED ;;
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
    printf '{\n  "report_at": %s,\n  "timeout": %s,\n  "isolated": %s,\n  "expire_token": %s,\n  "results": [\n' \
      "$REPORT_AT" "$TIMEOUT" "$ISOLATE" "$EXPIRE_TOKEN"
    first=1
    for r in "${RESULTS[@]}"; do
      IFS='|' read -r n st cat d e src sk <<< "$r"
      [ $first -eq 0 ] && printf ',\n'; first=0
      printf '    {"assistant": "%s", "status": "%s", "category": "%s", "detail": "%s", "seconds": %s, "source": "%s", "skills": "%s"}' \
        "$n" "$st" "$cat" "$d" "$e" "$src" "$sk"
    done
    printf '\n  ]\n}\n'
  } > "$SAVE_FILE"
  info "saved $SAVE_FILE"
fi

printf '\n'
[ "$FAILURES" -eq 0 ]
