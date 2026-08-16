#!/usr/bin/env bash
#
# sync-to-codex.sh — push the working tree's skills into Codex's plugin cache.
#
# Codex has no --plugin-dir, so it reads skills from an installed plugin cache.
# Reinstalling to pick up an edit means commit, push, `marketplace upgrade`, and
# `plugin add` — too slow to iterate on skill wording. This copies straight into
# the cache instead, so uncommitted edits take effect on the next Codex session.
#
# Only content Codex reads is synced (skills/ and AGENTS.md). Manifests, .git,
# and the rest of the cache are left alone so the install stays valid.
#
# Usage:
#   ./sync-to-codex.sh            # sync, then show what changed
#   ./sync-to-codex.sh --check    # report drift without writing anything
#
# Caveat: `codex plugin add` and `codex plugin marketplace upgrade` overwrite the
# cache from the marketplace ref, discarding anything synced here. Re-run after
# either command.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="crowdstrike-falcon-foundry"
CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

bold() { printf '\n\033[1m%s\033[0m\n' "$1"; }
ok()   { printf '  \033[0;32mOK\033[0m %s\n' "$1"; }
bad()  { printf '  \033[0;31mXX\033[0m %s\n' "$1"; }
info() { printf '     %s\n' "$1"; }

bold "Locating the Codex plugin cache"
# Version-scoped path (…/<plugin>/<version>/), so glob rather than hardcode.
CACHE=$(find "$HOME/.codex/plugins/cache" -type d -path "*${PLUGIN}/*" -depth 3 2>/dev/null | head -1)
if [ -z "$CACHE" ] || [ ! -d "$CACHE/skills" ]; then
  bad "no installed plugin found under ~/.codex/plugins/cache"
  info "install it first:"
  info "  codex plugin marketplace add CrowdStrike/foundry-skills"
  info "  codex plugin add ${PLUGIN}@foundry-marketplace"
  exit 1
fi
info "${CACHE/#$HOME/\~}"

if [ ! -d "$REPO/skills" ]; then
  bad "no skills/ directory in $REPO — run this from the repo root"
  exit 1
fi

RSYNC_OPTS=(-a --delete
  --exclude '.git' --exclude '__pycache__' --exclude '.pytest_cache'
  --exclude '.venv' --exclude '*.pyc')

bold "$([ "$CHECK_ONLY" -eq 1 ] && echo "Checking for drift (no changes)" || echo "Syncing")"
# Dry run first so we can report what moved, in both modes.
CHANGES=$(rsync "${RSYNC_OPTS[@]}" --dry-run --itemize-changes \
  "$REPO/skills/" "$CACHE/skills/" 2>/dev/null | grep -vE '^\.d' || true)

if [ -z "$CHANGES" ]; then
  ok "skills/ already identical"
else
  echo "$CHANGES" | sed 's/^/     /'
  if [ "$CHECK_ONLY" -eq 0 ]; then
    rsync "${RSYNC_OPTS[@]}" "$REPO/skills/" "$CACHE/skills/" >/dev/null 2>&1 \
      && ok "skills/ synced" || { bad "rsync failed"; exit 1; }
  fi
fi

# Codex reads AGENTS.md for repo-level instructions.
if ! cmp -s "$REPO/AGENTS.md" "$CACHE/AGENTS.md" 2>/dev/null; then
  if [ "$CHECK_ONLY" -eq 0 ]; then
    cp "$REPO/AGENTS.md" "$CACHE/AGENTS.md" && ok "AGENTS.md synced"
  else
    info "AGENTS.md differs"
  fi
else
  ok "AGENTS.md already identical"
fi

bold "Verifying"
if diff -rq "$REPO/skills" "$CACHE/skills" \
     -x '__pycache__' -x '*.pyc' -x '.pytest_cache' >/dev/null 2>&1; then
  ok "cache matches working tree"
else
  if [ "$CHECK_ONLY" -eq 1 ]; then
    info "drift present (expected — this was a check)"
  else
    bad "still differs after sync:"
    diff -rq "$REPO/skills" "$CACHE/skills" \
      -x '__pycache__' -x '*.pyc' -x '.pytest_cache' 2>&1 | sed 's/^/     /' | head
    exit 1
  fi
fi

# Size budget is what CI enforces, so surface a breach before the push does.
bold "Skill size budgets"
over=0
for f in "$REPO"/skills/*/SKILL.md; do
  t=$(( $(wc -c < "$f") / 4 ))
  n=$(basename "$(dirname "$f")")
  if [ "$t" -gt 5500 ]; then
    bad "$n ~${t} tokens — OVER 5500, CI will fail"
    over=1
  fi
done
[ "$over" -eq 0 ] && ok "all within 5500 tokens"

bold "Done"
info "Start a new Codex session to pick up the changes."
info "Re-run after any 'codex plugin add' or 'marketplace upgrade' — those overwrite the cache."
