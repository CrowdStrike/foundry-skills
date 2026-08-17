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
# so it asks. Every run ends in a fixed plain-text report naming the skills that
# loaded, the `foundry` commands that ran and how each one went, and any blocker;
# --e2e adds the app name and deployment id to the same shape.
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
#   ./test-assistants.sh --include codex      # test only these (comma-separated)
#   ./test-assistants.sh --exclude antigravity # test all but these (comma-separated)
#   ./test-assistants.sh --report-at 90       # ask for the report later (default 60s)
#   ./test-assistants.sh --timeout 300        # raise the hard cap (default 120s)
#   ./test-assistants.sh --e2e                # build and DEPLOY for real (see below)
#   ./test-assistants.sh --judge              # judge the last --e2e run, launching nothing
#   ./test-assistants.sh --expire-token       # delete the cached token first (see below)
#   ./test-assistants.sh --save results.json  # machine-readable results
#   ./test-assistants.sh --sequential         # one at a time (default: two groups in parallel)
#   ./test-assistants.sh --no-isolate         # skip bias control (not recommended)
#   ./test-assistants.sh --verbose            # list every plugin and symlink touched
#
# --e2e is the other half of the story. Smoke mode deliberately says "do not try to
# finish the app", so it can prove an assistant reaches the tenant but never that it
# can ship one — and a self-reported "3 foundry commands OK" is compatible with
# nothing at all being deployed. In --e2e mode the deadline moves out to ~15 minutes
# and the appended instructions demand a deployment id, so a PASS requires an artifact
# that either exists on the tenant or does not.
#
# Two things --e2e sets up that smoke mode does not need. Each assistant gets its own
# working directory, since they would otherwise scaffold on top of each other. And
# each is told to end its app name with its own slug, because app names are unique per
# tenant: without that the first deploy wins and the rest fail with "app name already
# exists", which looks like a skills failure and is not.
#
# What --e2e still does NOT do is check the tenant. It records what each assistant
# claims; verifying the claim is verify-apps.sh's job.
#
# --expire-token removes ~/.config/foundry/token.json so each run must refresh it.
# Without this, a still-valid token means no write is attempted and a sandbox
# permission failure cannot reproduce. The file is a regenerable cache, not a
# credential; the CLI recreates it from configuration.yml.
#
# Needs bash 4.3+ for case conversion and namerefs. macOS ships 3.2, so this runs
# under the Homebrew bash the shebang finds on PATH, not /bin/bash.
#
# Exit status is non-zero if any tested assistant failed.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT_AT=""  # default set below: near the end of the run, which differs by mode
TIMEOUT=""    # default set below: higher in parallel, where agents contend
E2E=0         # --e2e: build and deploy for real instead of smoke-testing
JUDGE=0       # --judge: check a previous --e2e run against ground truth, launching nothing
SAVE_FILE=""
ONLY=()
SKIP=()
ISOLATE=1
EXPIRE_TOKEN=0
VERBOSE=0
PARALLEL=1   # two groups in parallel; --sequential to disable
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
about to ask me a question, or if you sense you are about to be interrupted.
Running out of the time budget is expected and is not a failure — report what you
have done so far with BLOCKER: NONE. The
report is worth more to me than the extra progress.

To report, end your reply with these five lines, in this order, each starting a line
of plain text. No code fence, no blockquote, no bullets, no bold, and no angle
brackets in anything you write:

FOUNDRY-REPORT
STATUS: <one word — WORKING if the CLI is doing real work, BLOCKED only if a real problem stopped you, DONE if the app is built. Running out of the time budget is NOT blocked; that is WORKING>
SKILLS: <comma-separated paths of the skill files you loaded, or NONE>
COMMANDS: <comma-separated, every foundry command you ran, each written as the command followed by => OK or => FAIL: reason. NONE if you ran none>
BLOCKER: <one line naming a real problem, quoting the CLI error verbatim if there was one. NONE if nothing did. The time budget is not a blocker — if you simply ran out of time and nothing failed, write NONE>
EOF
}

# The --e2e counterpart. Same seven-line plain-text shape as above, for the same
# reason: this is parsed out of a transcript that may have echoed the prompt back,
# and JSON from five different assistants arrives fenced, prefixed, or truncated.
# Two extra fields carry the evidence smoke mode cannot produce.
#
# Note what is NOT said here: no `foundry` command is named, and the app is never
# described as something to "deploy and release" step by step. Deploy is Step 7 of the
# development-workflow skill, so an assistant that loaded the skills knows to do it.
# Spelling out the steps would measure instruction-following instead, and the canonical
# prompt's whole value is that it names no commands.
e2e_instructions() {   # slug
  cat <<EOF

Two more things, because this runs against a live shared tenant.

Name the app so it ends with \`-$1\`. App names must be unique per tenant and other
builds are running alongside yours; without the suffix your deploy may be rejected as
a duplicate of someone else's app. Otherwise pick whatever name you like.

You have about ${REPORT_AT} seconds of wall clock; run \`date\` if you need to know where you
are. Report before that runs out, and report immediately if something blocks you or if
you find yourself about to ask me a question. A partial result reported is worth more
than a finished app I never hear about.

To report, end your reply with these seven lines, in this order, each starting a line
of plain text. No code fence, no blockquote, no bullets, no bold, and no angle
brackets in anything you write:

FOUNDRY-REPORT
STATUS: <one word — DONE if the app deployed, WORKING if you ran out of time mid-build, BLOCKED only if a real problem stopped you>
APP: <the app name you chose, or NONE if you never created one>
DEPLOYMENT: <the deployment id returned by the deploy, or NONE if you did not get one>
SKILLS: <comma-separated paths of the skill files you loaded, or NONE>
COMMANDS: <comma-separated, every foundry command you ran, each written as the command followed by => OK or => FAIL: reason. NONE if you ran none>
BLOCKER: <one line naming a real problem, quoting the CLI error verbatim if there was one. NONE if nothing did>
EOF
}

# Both selectors take a comma-separated list and are repeatable, so
# `--include codex,cursor` and `--include codex --include cursor` are the same thing.
# The comma form matches how the eval harness spells its filter.
add_selectors() {   # array_name csv
  local -n arr="$1"
  local IFS=','
  read -r -a _parts <<< "$2"
  local v
  for v in ${_parts[@]+"${_parts[@]}"}; do
    v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"
    [ -n "$v" ] && arr+=("$v")
  done
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --include|--only) add_selectors ONLY "$2"; shift 2 ;;
    --exclude|--skip) add_selectors SKIP "$2"; shift 2 ;;
    --report-at)    REPORT_AT="$2"; shift 2 ;;
    --timeout)      TIMEOUT="$2"; shift 2 ;;
    --save)         SAVE_FILE="$2"; shift 2 ;;
    --prompt)       PROMPT="$2"; shift 2 ;;
    --no-isolate)   ISOLATE=0; shift ;;
    --e2e)          E2E=1; shift ;;
    --judge)        JUDGE=1; shift ;;
    -v|--verbose)   VERBOSE=1; shift ;;
    --sequential)   PARALLEL=0; shift ;;
    --expire-token) EXPIRE_TOKEN=1; shift ;;
    -h|--help)      sed -n '2,50p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

# Concurrency slows each agent: three at once all pegged a 120s cap they beat easily
# alone. But 240s only moved the peg — they used nearly all of it and wall clock got
# worse (278s vs 200s). 150s is the middle: room to report under contention, not so
# much that they spend it all.
#
# --e2e is a different measurement and needs a different budget. test-skill.sh runs
# take 5-10 minutes to build and deploy this same app, so the cap is 15 with the
# report asked for at 13 — late enough that stopping to report is the last thing an
# assistant does, not something it does instead of deploying.
if [ -z "$TIMEOUT" ]; then
  if   [ "$E2E" -eq 1 ];    then TIMEOUT=900
  elif [ "$PARALLEL" -eq 1 ]; then TIMEOUT=150
  else                           TIMEOUT=120
  fi
fi

# Judging reads files and the tenant. It launches nothing, so there is nothing to
# isolate and no reason to touch the user's plugins or symlinks.
[ "$JUDGE" -eq 1 ] && ISOLATE=0

if [ -z "$REPORT_AT" ]; then
  if [ "$E2E" -eq 1 ]; then REPORT_AT=780; else REPORT_AT=60; fi
fi

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
CHILD_PIDS=()
INTERRUPTED=0
on_interrupt() {
  if [ "$INTERRUPTED" -eq 1 ]; then
    printf '\n  %s▲%s  forcing exit\n' "$YELLOW" "$RESET"
    for _p in ${CHILD_PIDS[@]+"${CHILD_PIDS[@]}"}; do kill -KILL -- -"$_p" 2>/dev/null; done
    exit 130
  fi
  INTERRUPTED=1
  printf '\n  %s▲%s  stopping %s assistant(s) (Ctrl-C again to force)\n' \
    "$YELLOW" "$RESET" "${#CHILD_PIDS[@]}"
  # Signal each whole process group: assistants spawn node, npm and the Foundry CLI,
  # and killing only the direct child leaves those running.
  for _p in ${CHILD_PIDS[@]+"${CHILD_PIDS[@]}"}; do
    kill -TERM -- -"$_p" 2>/dev/null || kill -TERM "$_p" 2>/dev/null || true
  done
  for _ in 1 2 3 4 5 6; do
    local alive=0
    for _p in ${CHILD_PIDS[@]+"${CHILD_PIDS[@]}"}; do kill -0 -- -"$_p" 2>/dev/null && alive=1; done
    [ "$alive" -eq 0 ] && break
    sleep 0.25
  done
  for _p in ${CHILD_PIDS[@]+"${CHILD_PIDS[@]}"}; do kill -KILL -- -"$_p" 2>/dev/null; done
  exit 130   # restore runs via the EXIT trap
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
      # Every skill symlink, not only this repo's. A sibling repo competes just as much:
      # Cursor loaded fusion-skills' `setup` and ran 2 foundry commands where Claude,
      # seeing only ours, ran 8.
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
  [ "$JUDGE" -eq 0 ] && warn "bias control skipped (--no-isolate): results may reflect an installed copy"
fi

# ── Assistants ─────────────────────────────────────────────────
# name|binary|source|argv   (%%PROMPT%% substituted at run time)
#
# Codex gets no sandbox-bypass flag on purpose. Its sandbox is what breaks the
# CLI's token-cache write, so bypassing it would make this pass while users fail.
ASSISTANTS=(
  "Claude Code|claude|--plugin-dir|-p %%PROMPT%% --plugin-dir $REPO --dangerously-skip-permissions --verbose --output-format stream-json"
  "Codex|codex|~/.agents/skills|exec %%PROMPT%% --skip-git-repo-check"
  "Copilot CLI|copilot|--plugin-dir|-p %%PROMPT%% --plugin-dir $REPO --allow-all"
  "Cursor|agent|--plugin-dir|-p %%PROMPT%% --plugin-dir $REPO --force --trust"
  "Antigravity CLI|agy|~/.agents/skills|-p %%PROMPT%% --dangerously-skip-permissions"
)

want() {
  local n="$1" b="$2" o
  # Match either the display name or the binary. Names are what the table shows;
  # binaries are what the log files are named after, so `--only agent` has to select
  # Cursor or someone reading agent.log gets a silent empty run.
  for o in ${SKIP[@]+"${SKIP[@]}"}; do
    [[ "${n,,}" == *"${o,,}"* || "${b,,}" == *"${o,,}"* ]] && return 1
  done
  [ ${#ONLY[@]} -eq 0 ] && return 0
  for o in "${ONLY[@]}"; do
    [[ "${n,,}" == *"${o,,}"* || "${b,,}" == *"${o,,}"* ]] && return 0
  done
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
  # A --e2e-only failure, and a harness fault rather than a skills one: app names are
  # unique per tenant, so two assistants that ignored the slug suffix collide and the
  # loser looks broken. Categorised separately so it cannot be read as an assistant
  # problem.
  grep -qiE 'name already exists|already in use|duplicate app'  <<< "$t" && { echo dupname;    return; }
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
  # Claude streams stream-json, so its report arrives inside an escaped JSON string.
  # Expanding \n puts the labels and the blockquoted skill text back at line start,
  # where the patterns below expect them. The second sed drops the JSON tail that
  # follows the closing quote, which would otherwise be read as part of BLOCKER; it
  # anchors on a quote plus `}` or `]` rather than the first quote, because BLOCKER is
  # asked to quote the CLI error verbatim. No-ops on plain-text logs.
  body=$(sed -e 's/\\n/\
/g' -e 's/"[]}].*$//' "$log" 2>/dev/null | grep -v '^[[:space:]]*>')

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

  # Our own time budget is not a failure, however the assistant phrases it. Codex
  # reported "Timed test harness limit stopped me" as a blocker while every command
  # it ran had succeeded. Discard that class of blocker before judging.
  if grep -qiE 'time (budget|limit)|timed? (out|harness)|harness limit|ran out of time|60[- ]second' <<< "$raw_blocker"; then
    raw_blocker=NONE
    grep -qi 'BLOCK' <<< "$status" && status=WORKING
  fi

  # A real blocker is the result, whatever else the assistant managed to do.
  if grep -qi 'BLOCK' <<< "$status" || ! is_none "$raw_blocker"; then
    cat=$(blocker_category "$raw_blocker")
    detail=$(clean "blocked: ${raw_blocker:-no detail given}" 40)
    echo "FAIL|$cat|$detail|$skills|$cmds"; return
  fi

  # In --e2e the bar is an artifact rather than activity. "N commands OK" was exactly
  # the verdict that let a run pass with nothing on the tenant, so a deployment id is
  # the only thing that counts here. Whether the id is real is verify-apps.sh's call.
  if [ "$E2E" -eq 1 ]; then
    local app dep
    app=$(report_field APP        <<< "$body")
    dep=$(report_field DEPLOYMENT <<< "$body")
    is_none "$app" && app="?"
    if is_none "$dep"; then
      echo "FAIL|nodeploy|$(clean "no deployment id (app: $app)" 40)|$skills|$cmds"; return
    fi
    echo "PASS|deployed|$(clean "deployed $app · $dep" 40)|$skills|$cmds"; return
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

# All assistants share ONE token cache at ~/.config/foundry/token.json. Run in
# parallel with an expired token and they race to refresh it: concurrent logins plus
# a write race on the same file. Warming it once first means nobody needs to refresh.

# Seconds of life left in the cached token, or 0 if there is no readable one. Reads
# the `expiry` timestamp only — the token value is never read, printed, or logged.
token_ttl() {
  local f="$HOME/.config/foundry/token.json" exp now
  [ -r "$f" ] || { echo 0; return; }
  exp=$(sed -n 's/.*"expiry"[[:space:]]*:[[:space:]]*\([0-9]\{1,\}\).*/\1/p' "$f" | head -1)
  [ -n "$exp" ] || { echo 0; return; }
  now=$(date +%s)
  echo $(( exp > now ? exp - now : 0 ))
}

warm_token() {
  command -v foundry >/dev/null 2>&1 || return 0
  head2 "Warming the shared token cache"
  # `apps list` proves the token works NOW, which is not the same as it lasting the
  # whole run: a token with four minutes left passes the warm-up and then expires
  # with every assistant mid-build, which is the exact race this function exists to
  # prevent. So compare its remaining life against the cap rather than assuming.
  #
  # The token lasts ~30 minutes, so smoke mode cannot straddle expiry and this stays
  # quiet there; a 15-minute --e2e run can. Only discard when the arithmetic says it
  # will actually run out — throwing away a valid token costs an auth round trip that
  # can itself fail. --expire-token means the caller WANTS the assistants on the
  # refresh path, so leave that mode alone.
  local ttl; ttl=$(token_ttl)
  if [ "$EXPIRE_TOKEN" -eq 0 ] && [ "$ttl" -gt 0 ] && [ "$ttl" -lt "$TIMEOUT" ]; then
    info "cached token has ${ttl}s left, less than this run's ${TIMEOUT}s cap — refreshing now"
    rm -f "$HOME/.config/foundry/token.json"
  fi
  if foundry apps list >/dev/null 2>&1; then
    ok "token valid — no assistant will need to refresh it mid-run"
  else
    warn "could not reach the tenant; assistants may each try to refresh the token"
    info "that is a write race on ~/.config/foundry/token.json — expect noisy failures"
  fi
}

# --expire-token exists to force the refresh path, which is exactly what must not
# happen concurrently. Serialise in that mode.
if [ "$EXPIRE_TOKEN" -eq 1 ] && [ "$PARALLEL" -eq 1 ]; then
  PARALLEL=0
  warn "--expire-token forces sequential mode (concurrent token refresh would race)"
fi
[ "$PARALLEL" -eq 1 ] && warm_token

RUN_START=$(date +%s)
[ "$JUDGE" -eq 0 ] && head2 "Running"
if [ "$JUDGE" -eq 1 ]; then
  :
elif [ "$E2E" -eq 1 ]; then
  info "END-TO-END: real deploy required · report at ${REPORT_AT}s · hard cap ${TIMEOUT}s · logs in ${LOG_DIR/#$HOME/\~}"
  info "a PASS means the assistant reported a deployment id; verify it with ./verify-apps.sh"
else
  info "real app-creation prompt · self-report at ${REPORT_AT}s · hard cap ${TIMEOUT}s · logs in ${LOG_DIR/#$HOME/\~}"
fi
printf '\n'

RESULTS=(); CATEGORIES=(); FAILURES=0; TESTED=0

# Two groups, because they need OPPOSITE filesystem state and cannot overlap:
# --plugin-dir assistants run with this repo's symlinks stashed away, while Codex and
# Antigravity need those same symlinks present. Set the state once per group, run the
# group in parallel, then move on. Wall clock becomes the slowest member of each group
# instead of the sum of all five.
# Sets LAUNCHED_PID / LAUNCHED_START. Deliberately NOT echoing them: calling this via
# $(...) would run it in a subshell that owns the background job, and the parent shell
# then cannot wait on the pid ("is not a child of this shell").
LAUNCHED_PID=""
LAUNCHED_START=""
launch() {   # name bin source argv
  local name="$1" bin="$2" argv="$4" log="$LOG_DIR/${2}.log"
  local -a parts=() cmd=()
  read -r -a parts <<< "$argv"
  cmd=("$bin")
  # The canonical prompt, then the mode's instructions. Appended, never spliced:
  # CI asserts the PROMPT line still starts with the README text.
  local tail_instructions work_dir="$LOG_DIR"
  if [ "$E2E" -eq 1 ]; then
    # Its own directory, or four assistants scaffold on top of each other. The binary
    # name doubles as the app-name suffix — short, and already unique per assistant.
    work_dir="$LOG_DIR/e2e/$bin"
    mkdir -p "$work_dir"
    tail_instructions=$(e2e_instructions "$bin")
  else
    tail_instructions=$(report_instructions)
  fi
  local full_prompt="${PROMPT}
${tail_instructions}"
  local pp
  for pp in "${parts[@]}"; do
    if [ "$pp" = "%%PROMPT%%" ]; then cmd+=("$full_prompt"); else cmd+=("$pp"); fi
  done
  local start; start=$(date +%s)
  # `set -m` gives each job its own process group so on_interrupt can signal the whole
  # tree. < /dev/null is load-bearing: `claude -p` reads stdin and, backgrounded
  # without a redirect, blocks on input that never arrives — full timeout, empty log.
  set -m
  ( cd "$work_dir" && env -u CLAUDECODE "$TIMEOUT_BIN" "$TIMEOUT" "${cmd[@]}" ) < /dev/null > "$log" 2>&1 &
  LAUNCHED_PID=$!
  set +m
  LAUNCHED_START=$start
}

report_one() {   # name bin source rc elapsed
  local name="$1" bin="$2" source="$3" rc="$4" elapsed="$5"
  local log="$LOG_DIR/${bin}.log" status category detail rskills rcmds
  IFS='|' read -r status category detail rskills rcmds <<< "$(classify "$log" "$rc")"
  case "$status" in
    PASS)    printf '  %s%-16s%s %s✔ PASS%s  %-43s %s%4ss%s\n' \
               "$BOLD" "$name" "$RESET" "$GREEN$BOLD" "$RESET" "$detail" "$DIM" "$elapsed" "$RESET" ;;
    TIMEOUT) printf '  %s%-16s%s %s◷ SLOW%s   %-43s %s%4ss%s\n' \
               "$BOLD" "$name" "$RESET" "$YELLOW$BOLD" "$RESET" "$detail" "$DIM" "$elapsed" "$RESET"
             FAILURES=$((FAILURES+1)) ;;
    *)       printf '  %s%-16s%s %s✘ FAIL%s  %s%-43s%s %s%4ss%s\n' \
               "$BOLD" "$name" "$RESET" "$RED$BOLD" "$RESET" "$RED" "$detail" "$RESET" "$DIM" "$elapsed" "$RESET"
             FAILURES=$((FAILURES+1)) ;;
  esac
  info "source: $source · log: ${log/#$HOME/\~}"
  # What it said it loaded and ran — the two things worth reading without opening the
  # log, and the pair that shows a pass came from the working tree.
  [ -n "$rskills" ] && info "skills: $rskills"
  [ -n "$rcmds" ]   && info "ran: $rcmds"
  [ "$status" != "PASS" ] && CATEGORIES+=("$category")
  # --e2e records the two claims a judging pass needs as their own fields, not buried
  # in the display string: verify-apps.sh has to look them up on the tenant.
  local rapp="" rdep=""
  if [ "$E2E" -eq 1 ]; then
    local ebody; ebody=$(grep -v '^[[:space:]]*>' "$log" 2>/dev/null)
    rapp=$(clean "$(report_field APP        <<< "$ebody")" 60)
    rdep=$(clean "$(report_field DEPLOYMENT <<< "$ebody")" 60)
  fi
  RESULTS+=("$name|$status|$category|$detail|$elapsed|$source|$rskills|$rapp|$rdep")
  TESTED=$((TESTED+1))
  return 0
}

run_group() {
  local want_src="$1"
  # `local -a x` leaves the array UNSET under set -u; `=()` makes it set-but-empty.
  local -a g_names=() g_bins=() g_pids=() g_starts=()
  local entry name bin source argv

  for entry in "${ASSISTANTS[@]}"; do
    IFS='|' read -r name bin source argv <<< "$entry"
    want "$name" "$bin" || continue
    [ "$source" = "$want_src" ] || continue
    if ! command -v "$bin" >/dev/null 2>&1; then
      printf '  %s%-16s SKIP%s    %s not installed\n' "$DIM" "$name" "$RESET" "$bin"
      RESULTS+=("$name|SKIP|skip|not installed|0|none|")
      continue
    fi
    g_names+=("$name"); g_bins+=("$bin")
  done
  [ ${#g_names[@]} -eq 0 ] && return 0

  # Set the filesystem state ONCE for the whole group.
  [ "$want_src" = "~/.agents/skills" ] && link_repo_skills
  [ "$EXPIRE_TOKEN" -eq 1 ] && rm -f "$HOME/.config/foundry/token.json"

  local i
  for i in "${!g_names[@]}"; do
    for entry in "${ASSISTANTS[@]}"; do
      IFS='|' read -r name bin source argv <<< "$entry"
      [ "$name" = "${g_names[$i]}" ] || continue
      launch "$name" "$bin" "$source" "$argv"
      g_pids+=("$LAUNCHED_PID"); g_starts+=("$LAUNCHED_START")
      CHILD_PIDS+=("$LAUNCHED_PID")
      if [ "$PARALLEL" -eq 1 ]; then
        printf '  %s%-16s%s %s▸ running%s\n' "$BLUE" "$name" "$RESET" "$DIM" "$RESET"
      else
        printf '  %s%-16s%s running… ' "$BLUE" "$name" "$RESET"
        wait "${g_pids[$i]}"; g_rcs[$i]=$?
        printf '\r'
      fi
      break
    done
  done

  if [ "$PARALLEL" -eq 1 ]; then
    printf '\n'
    for i in "${!g_pids[@]}"; do wait "${g_pids[$i]}"; g_rcs[$i]=$?; done
  fi

  for i in "${!g_names[@]}"; do
    for entry in "${ASSISTANTS[@]}"; do
      IFS='|' read -r name bin source argv <<< "$entry"
      [ "$name" = "${g_names[$i]}" ] || continue
      report_one "$name" "$bin" "$source" "${g_rcs[$i]:-1}" \
        "$(( $(date +%s) - ${g_starts[$i]} ))"
      break
    done
  done

  [ "$want_src" = "~/.agents/skills" ] && unlink_repo_skills
  CHILD_PIDS=()
  return 0
}

# ── Judging ───────────────────────────────────────────────────────
# A PASS above means the assistant SAID it deployed. This checks whether it did, and
# whether the app contains what was asked for. Every check reads a file or the tenant;
# none of it trusts the transcript.
#
# Apps are located by identity rather than by path, because the per-assistant working
# directory is advisory: Copilot ran `cd /Users/mraible/dev` and scaffolded there, so a
# judge that only looked where it was told would have failed a genuinely working app.
# An app found elsewhere is reported as "escaped", not as a failure.

# Newline-separated "name<TAB>state" for everything on the tenant. One call, reused.
tenant_apps() {
  foundry apps list 2>/dev/null | awk -F'|' 'NF>3 && $2 !~ /APP ID/ {
    gsub(/^[ \t]+|[ \t]+$/, "", $3); gsub(/^[ \t]+|[ \t]+$/, "", $4)
    if ($3 != "") printf "%s\t%s\n", $3, $4
  }'
}

# Sets MANIFEST_PATH and FOUND_OUTSIDE. Deliberately not echoing the path: called
# through $(...) the assignments would happen in a subshell and never reach the caller,
# which is the same trap that broke launch() returning a pid.
MANIFEST_PATH=""
FOUND_OUTSIDE=""
find_manifest() {   # bin
  local bin="$1"
  MANIFEST_PATH=""; FOUND_OUTSIDE=""
  MANIFEST_PATH=$(find "$LOG_DIR/e2e/$bin" -name manifest.yml -maxdepth 3 2>/dev/null | head -1)
  [ -n "$MANIFEST_PATH" ] && return
  # Not where we put it. Look where an assistant has actually been known to wander,
  # then fall back to whatever path the transcript mentions.
  MANIFEST_PATH=$(grep -oE '/[^ "]*/manifest\.yml' "$LOG_DIR/${bin}.log" 2>/dev/null | head -1)
  if [ -z "$MANIFEST_PATH" ]; then
    MANIFEST_PATH=$(find "$HOME/dev" -maxdepth 2 -name manifest.yml \
      -exec grep -l -- "-${bin}\$" {} + 2>/dev/null | head -1)
  fi
  [ -n "$MANIFEST_PATH" ] && [ -f "$MANIFEST_PATH" ] && FOUND_OUTSIDE=1
  [ -f "${MANIFEST_PATH:-/nonexistent}" ] || MANIFEST_PATH=""
}

# Present-or-not for the things the skills are supposed to produce. Each maps to one
# sub-skill, so a missing mark says which skill did not really run.
judge_one() {   # name bin claimed_app claimed_deployment
  local name="$1" bin="$2" c_app="$3" c_dep="$4"
  local manifest app_dir app_name state marks="" notes=""

  find_manifest "$bin"; manifest="$MANIFEST_PATH"
  if [ -z "$manifest" ]; then
    printf '  %s%-16s%s %s✘ NO APP%s  nothing on disk for this assistant\n' \
      "$BOLD" "$name" "$RESET" "$RED$BOLD" "$RESET"
    JUDGED+=("$name|NOAPP|||"); return
  fi
  app_dir=$(dirname "$manifest")
  app_name=$(sed -n 's/^name:[[:space:]]*//p' "$manifest" | head -1)
  [ -n "$FOUND_OUTSIDE" ] && notes="built outside its working directory: ${app_dir/#$HOME/\~}"

  state=$(tenant_apps | awk -F'\t' -v n="$app_name" '$1==n {print $2; exit}')
  [ -z "$state" ] && state="ABSENT"

  # api-integrations, with the two markers that only appear if the skill was applied:
  # Okta's SSWS auth prefix, and x-cs-operation-config for sharing with Fusion SOAR.
  local spec
  spec=$(find "$app_dir/api-integrations" -type f \( -name '*.yaml' -o -name '*.yml' -o -name '*.json' \) 2>/dev/null | head -1)
  [ -n "$spec" ] && marks+="api " || marks+="--- "
  [ -n "$spec" ] && grep -qi 'SSWS' "$spec" && marks+="ssws " || marks+="---- "
  [ -n "$spec" ] && grep -q 'x-cs-operation-config' "$spec" && marks+="soar " || marks+="---- "

  grep -qE '^workflows:' "$manifest" && grep -qE '^\s+- id:|^\s+[a-z].*:' <<< "$(sed -n '/^workflows:/,/^[a-z]/p' "$manifest")" \
    && marks+="wf " || marks+="-- "
  grep -qE '^[[:space:]]+extensions:' "$manifest" && ! sed -n '/extensions:/,+3p' "$manifest" | grep -q '\[\]' \
    && marks+="ext " || marks+="--- "

  # The UI is only real if it talks to the integration and uses the design system.
  # Scoped to source files: an unscoped grep matches @shoelace-style in a lock file or
  # a bundled copy in node_modules, which says nothing about what the code renders.
  local ui_src=(--exclude-dir=node_modules --include='*.js' --include='*.jsx' --include='*.html')
  grep -rqs "${ui_src[@]}" -e 'apiIntegration(' "$app_dir/ui" && marks+="api-js " || marks+="------ "
  grep -rqsE "${ui_src[@]}" -e '<sl-' "$app_dir/ui" && marks+="shoelace" || marks+="--------"

  local verdict colour
  case "$state" in
    Released|Deployed) verdict=OK;      colour=$GREEN ;;
    ABSENT)            verdict=NOTENANT; colour=$RED ;;
    *)                 verdict=STATE;   colour=$YELLOW ;;
  esac
  # The disagreement that matters: it claimed a deployment the tenant cannot show.
  [ "$verdict" = NOTENANT ] && [ -n "$c_dep" ] && notes="claimed $c_dep but the tenant has no such app"
  [ -n "$c_app" ] && [ "$c_app" != "$app_name" ] && [ "$c_app" != "?" ] \
    && notes="${notes:+$notes; }reported \"$c_app\" but the manifest says \"$app_name\""

  printf '  %s%-16s%s %s%-9s%s %-22s %s%s%s\n' \
    "$BOLD" "$name" "$RESET" "$colour$BOLD" "$state" "$RESET" "$app_name" "$DIM" "$marks" "$RESET"
  [ -n "$notes" ] && info "$notes"
  JUDGED+=("$name|$verdict|$app_name|$state|$marks")
}

run_judge() {
  head2 "Judging against the tenant and the files on disk"
  info "state · app · api ssws soar wf ext api-js shoelace   (dashes mean absent)"
  JUDGED=()
  local entry name bin source argv r rn rapp rdep
  for entry in "${ASSISTANTS[@]}"; do
    IFS='|' read -r name bin source argv <<< "$entry"
    want "$name" "$bin" || continue
    rapp=""; rdep=""
    for r in ${RESULTS[@]+"${RESULTS[@]}"}; do
      IFS='|' read -r rn _ _ _ _ _ _ rapp rdep <<< "$r"
      [ "$rn" = "$name" ] && break
      rapp=""; rdep=""
    done
    judge_one "$name" "$bin" "$rapp" "$rdep"
  done
}

declare -a g_rcs=()
if [ "$JUDGE" -eq 0 ]; then
  run_group "--plugin-dir"
  run_group "~/.agents/skills"
fi

WALL=$(( $(date +%s) - RUN_START ))
SEQ=0
for r in ${RESULTS[@]+"${RESULTS[@]}"}; do
  IFS='|' read -r _n _s _c _d _e _src _sk <<< "$r"
  SEQ=$(( SEQ + ${_e:-0} ))
done

if [ "$JUDGE" -eq 1 ]; then
  run_judge
  printf '\n'
  exit 0
fi

head2 "Summary"
if [ "$TESTED" -eq 0 ]; then
  printf '  no assistants tested\n'
elif [ "$FAILURES" -eq 0 ]; then
  printf '  %s%s✔ %s of %s%s reached the tenant%s\n' \
    "$GREEN" "$BOLD" "$TESTED" "$TESTED" "$RESET$GREEN" "$RESET"
  printf '    %s%ss wall clock · %ss if run one at a time%s\n' "$DIM" "$WALL" "$SEQ" "$RESET"
else
  printf '  %s%s%s of %s%s reached the tenant%s   %s│%s   %s%s✘ %s failed%s\n' \
    "$GREEN" "$BOLD" "$((TESTED-FAILURES))" "$TESTED" "$RESET$GREEN" "$RESET" \
    "$DIM" "$RESET" "$RED" "$BOLD" "$FAILURES" "$RESET"
  printf '    %s%ss wall clock · %ss if run one at a time%s\n' "$DIM" "$WALL" "$SEQ" "$RESET"
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
      nodeploy)   label="never produced a deployment id"              ; col=$RED ;;
      dupname)    label="app name collided on the tenant (harness fault)" ; col=$YELLOW ;;
      *)          label="other"                                       ; col=$DIM ;;
    esac
    printf '    %s%s×%s %s%s%s\n' "$BOLD" "$n" "$RESET" "$col" "$label" "$RESET"
  done
  printf '\n'
  if printf '%s\n' ${CATEGORIES[@]+"${CATEGORIES[@]}"} | grep -qx connection; then
    info 'A connection issue means the sandbox denied the CLI its token-cache'
    info 'write to ~/.config/foundry/ — see debugging-workflows.'
    [ "$EXPIRE_TOKEN" -eq 0 ] && info 'Re-run with --expire-token to force that path on every trial.'
  elif printf '%s\n' ${CATEGORIES[@]+"${CATEGORIES[@]}"} | grep -qx dupname; then
    info 'An app-name collision is this harness misbehaving, not the assistant: the'
    info 'slug suffix in the prompt is what keeps names unique per tenant.'
  elif printf '%s\n' ${CATEGORIES[@]+"${CATEGORIES[@]}"} | grep -qx nodeploy; then
    info 'Reaching the tenant is not shipping to it. Read the log to see how far it'
    info 'got, and raise --timeout if it simply ran out of wall clock.'
  else
    info 'No connection or TTY failures. Read the logs above.'
  fi
fi

if [ -n "$SAVE_FILE" ]; then
  {
    printf '{\n  "mode": "%s",\n  "report_at": %s,\n  "timeout": %s,\n  "isolated": %s,\n  "expire_token": %s,\n  "results": [\n' \
      "$([ "$E2E" -eq 1 ] && echo e2e || echo smoke)" \
      "$REPORT_AT" "$TIMEOUT" "$ISOLATE" "$EXPIRE_TOKEN"
    first=1
    for r in "${RESULTS[@]}"; do
      IFS='|' read -r n st cat d e src sk app dep <<< "$r"
      [ $first -eq 0 ] && printf ',\n'; first=0
      printf '    {"assistant": "%s", "status": "%s", "category": "%s", "detail": "%s", "seconds": %s, "source": "%s", "skills": "%s", "app": "%s", "deployment_id": "%s"}' \
        "$n" "$st" "$cat" "$d" "$e" "$src" "$sk" "$app" "$dep"
    done
    printf '\n  ]\n}\n'
  } > "$SAVE_FILE"
  info "saved $SAVE_FILE"
fi

printf '\n'
[ "$FAILURES" -eq 0 ]
