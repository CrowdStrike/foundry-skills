#!/usr/bin/env bash
#
# release.sh — Automate plugin release workflow
#
# Usage:
#   ./release.sh              # interactive bump (major/minor/patch)
#   ./release.sh --version X  # release exact version (e.g., first release)
#
# 1. Prompt for semantic version bump (or use --version)
# 2. Update Claude and Codex plugin metadata
# 3. Update README version badge
# 4. Update SKILL.md version and updated date
# 5. Update CHANGELOG date (TBD → today)
# 6. Commit and create a release PR
# 7. Print post-merge marketplace instructions
#
set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
RESET='\033[0m'

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CLAUDE_PLUGIN_JSON="$SCRIPT_DIR/.claude-plugin/plugin.json"
CODEX_PLUGIN_JSON="$SCRIPT_DIR/.codex-plugin/plugin.json"
ROOT_PLUGIN_JSON="$SCRIPT_DIR/plugin.json"
CLAUDE_MARKETPLACE_JSON="$SCRIPT_DIR/.claude-plugin/marketplace.json"
CODEX_MARKETPLACE_JSON="$SCRIPT_DIR/.agents/plugins/marketplace.json"
MARKETPLACE_URL="https://github.com/CrowdStrike/foundry-skills.git"
EXPLICIT_VERSION=""
BUNDLE_ONLY=0
BUNDLE_REF=""

# Everything the OpenAI skills-only bundle must contain. Single source of truth:
# a skill that starts referencing a new top-level path needs adding here, and
# build_bundle fails loudly if a referenced path is missing from the archive.
#
# assets/ holds the interface icons (composerIcon/logo) referenced by
# .codex-plugin/plugin.json; the portal rejects the upload if they are absent.
#
# Deliberately excluded: hooks/ (Codex discovers hooks/hooks.json and would run
# Claude-contract hooks unvalidated), .claude-plugin/ and the root plugin.json
# (one plugin root per archive, and only the Codex manifest is needed here).
BUNDLE_PATHS=(.codex-plugin assets skills use-cases requirements.txt LICENSE README.md)

# Argument parsing
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      EXPLICIT_VERSION="$2"
      shift 2
      ;;
    --bundle)
      BUNDLE_REF="${2:-}"
      shift
      [[ -n "${BUNDLE_REF:-}" && "$BUNDLE_REF" != --* ]] && shift || BUNDLE_REF=""
      BUNDLE_ONLY=1
      ;;
    *)
      printf "${RED}Usage: $0 [--version X.Y.Z] [--bundle [ref]]${RESET}\n" >&2
      exit 1
      ;;
  esac
done

# Read current version from plugin.json
get_current_version() {
  jq -r '.version' "$CLAUDE_PLUGIN_JSON" 2>/dev/null || echo "0.0.0"
}

# Parse semantic version into "major minor patch"
parse_version() {
  local version=$1
  if [[ $version =~ ^v?([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]}"
  else
    printf "${RED}ERROR: Invalid version format: %s${RESET}\n" "$version" >&2
    exit 1
  fi
}

# Calculate next version based on bump type
calculate_next_version() {
  local major=$1 minor=$2 patch=$3 bump_type=$4
  case "$bump_type" in
    major) echo "$((major + 1)).0.0" ;;
    minor) echo "$major.$((minor + 1)).0" ;;
    patch) echo "$major.$minor.$((patch + 1))" ;;
  esac
}

# Build the OpenAI skills-only submission bundle and verify it before upload.
# The portal validates structure after upload; this catches the same problems
# locally, where fixing them is cheap.
build_bundle() {
  local ref="${1:-}"
  if [[ -z "$ref" ]]; then
    ref=$(git -C "$SCRIPT_DIR" describe --tags --abbrev=0 2>/dev/null || echo "")
    [[ -z "$ref" ]] && { printf "${RED}✗${RESET} No tags found. Pass a ref: ./release.sh --bundle v1.5.0\n" >&2; return 1; }
    printf "${YELLOW}⚠${RESET} No ref given, using latest tag: %s\n" "$ref"
  fi
  git -C "$SCRIPT_DIR" rev-parse --verify --quiet "$ref" >/dev/null \
    || { printf "${RED}✗${RESET} Ref not found: %s\n" "$ref" >&2; return 1; }

  local version="${ref#v}"
  local zip="$SCRIPT_DIR/crowdstrike-falcon-foundry-${version}.zip"
  printf "\n${BLUE}Building skills-only bundle from %s${RESET}\n" "$ref"

  # Build to a temp file and only move it into place after every check passes.
  # git archive truncates its --output before it runs, so writing straight to
  # "$zip" would leave a 0-byte file if the archive (or a later check) fails, and
  # a 0-byte zip looks fine locally until the portal or Slack rejects it.
  local tmpzip="${zip}.partial"
  git -C "$SCRIPT_DIR" archive --format=zip --output="$tmpzip" "$ref" "${BUNDLE_PATHS[@]}" \
    || { printf "${RED}✗${RESET} git archive failed\n" >&2; rm -f "$tmpzip"; return 1; }

  local work; work=$(mktemp -d)
  # shellcheck disable=SC2064
  trap "rm -rf '$work' '$tmpzip'" RETURN
  unzip -q "$tmpzip" -d "$work" || { printf "${RED}✗${RESET} Archive is not readable\n" >&2; return 1; }

  local fail=0

  # Exactly one plugin root, at the archive root.
  if [[ -f "$work/.codex-plugin/plugin.json" ]]; then
    printf "${GREEN}✓${RESET} Codex manifest present at the archive root\n"
  else
    printf "${RED}✗${RESET} Missing .codex-plugin/plugin.json\n"; fail=1
  fi
  local roots
  roots=$(find "$work" -maxdepth 2 -type d \( -name .codex-plugin -o -name .claude-plugin -o -name .agent-plugin \) | wc -l | tr -d ' ')
  if [[ "$roots" == "1" ]]; then
    printf "${GREEN}✓${RESET} Exactly one plugin root\n"
  else
    printf "${RED}✗${RESET} Found %s plugin manifests; the portal requires exactly one\n" "$roots"; fail=1
  fi

  # Interface icons. The portal requires interface.composerIcon and interface.logo,
  # each pointing at a square image that ships inside the archive. A bundle missing
  # them imports through the CLI fine but is rejected at upload ("Missing plugin
  # composer icon" / "Missing plugin logo"), so catch it here where fixing is cheap.
  local manifest="$work/.codex-plugin/plugin.json"
  local icon_field icon_path resolved
  for icon_field in composerIcon logo; do
    icon_path=$(jq -r ".interface.${icon_field} // empty" "$manifest" 2>/dev/null)
    if [[ -z "$icon_path" ]]; then
      printf "${RED}✗${RESET} interface.%s missing from .codex-plugin/plugin.json; the portal rejects the upload\n" "$icon_field"; fail=1
      continue
    fi
    # Paths are relative to the plugin root (the archive root), e.g. ./assets/logo.png.
    resolved="$work/${icon_path#./}"
    if [[ ! -f "$resolved" ]]; then
      printf "${RED}✗${RESET} interface.%s -> %s is not in the archive; add its directory to BUNDLE_PATHS\n" "$icon_field" "$icon_path"; fail=1
      continue
    fi
    # The portal requires a square image. For PNGs, read width/height from the IHDR
    # chunk with the standard library so this works on CI without Pillow.
    if [[ "$icon_path" == *.png ]] && ! python3 - "$resolved" <<'PY'
import struct, sys
with open(sys.argv[1], "rb") as fh:
    head = fh.read(24)
# PNG signature (8 bytes) + IHDR: width/height are big-endian uint32 at bytes 16-24.
if head[:8] != b"\x89PNG\r\n\x1a\n" or head[12:16] != b"IHDR":
    sys.exit(2)
width, height = struct.unpack(">II", head[16:24])
sys.exit(0 if width == height else 1)
PY
    then
      printf "${RED}✗${RESET} interface.%s -> %s is not a square PNG; the portal requires a square image\n" "$icon_field" "$icon_path"; fail=1
      continue
    fi
    printf "${GREEN}✓${RESET} interface.%s resolves to %s inside the archive\n" "$icon_field" "$icon_path"
  done

  # At least one skill.
  local skills
  skills=$(find "$work/skills" -mindepth 2 -maxdepth 2 -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$skills" -ge 1 ]]; then
    printf "${GREEN}✓${RESET} %s skills with a SKILL.md\n" "$skills"
  else
    printf "${RED}✗${RESET} No skills/<name>/SKILL.md found\n"; fail=1
  fi

  # Disqualifiers for a skills-only submission.
  local bad=0
  [[ -e "$work/.mcp.json" || -e "$work/.app.json" ]] && bad=1
  grep -rqs "mcpServers" "$work/.codex-plugin/plugin.json" && bad=1
  grep -rqs "screenshots" "$work/.codex-plugin/plugin.json" && bad=1
  [[ -d "$work/hooks" ]] && { printf "${RED}✗${RESET} hooks/ is in the archive; Codex would run Claude-contract hooks unvalidated\n"; fail=1; }
  if [[ "$bad" == "0" ]]; then
    printf "${GREEN}✓${RESET} No mcpServers, .mcp.json, .app.json or interface.screenshots\n"
  else
    printf "${RED}✗${RESET} Archive contains something a skills-only plugin may not ship\n"; fail=1
  fi

  # Every relative path the skills reference must resolve inside the archive.
  # This is what catches a skill that starts using a new top-level directory.
  # `|| true` keeps the substitution from tripping `set -e`: under pipefail the
  # inner grep exits non-zero for any file with no links, which would otherwise
  # abort the whole script. The captured stdout (the MISSING lines) is unaffected.
  local missing
  missing=$(cd "$work" && find skills -name '*.md' | while read -r f; do
    d=$(dirname "$f")
    grep -ohE '\]\((\.\./)*[A-Za-z0-9_./-]+\.(md|py|sh|json|ya?ml)(#[^)]*)?\)' "$f" 2>/dev/null \
      | sed 's/^](//; s/)$//; s/#.*$//' | while read -r link; do
        target=$(python3 -c 'import os,sys; print(os.path.normpath(os.path.join(sys.argv[1], sys.argv[2])))' "$d" "$link")
        [[ -e "$target" ]] || printf '%s -> %s\n' "$f" "$link"
      done
  done) || true
  if [[ -z "$missing" ]]; then
    printf "${GREEN}✓${RESET} Every path referenced by a skill resolves inside the archive\n"
  else
    printf "${RED}✗${RESET} Referenced paths missing from the archive:\n%s\n" "$missing"
    printf "  Add the containing directory to BUNDLE_PATHS in release.sh.\n"; fail=1
  fi

  # Runtime dependencies that no markdown link points at, so the link check above
  # cannot see them. requirements.txt is named inside a shell snippet; use-cases is
  # globbed at runtime by development-workflow.
  local dep
  for dep in requirements.txt use-cases; do
    if [[ -e "$work/$dep" ]]; then
      printf "${GREEN}✓${RESET} %s present (referenced at runtime, not by a link)\n" "$dep"
    else
      printf "${RED}✗${RESET} %s missing; skills reference it outside a markdown link\n" "$dep"; fail=1
    fi
  done

  local count size
  count=$(find "$work" -type f | wc -l | tr -d ' ')
  local count size
  count=$(find "$work" -type f | wc -l | tr -d ' ')
  size=$(du -h "$tmpzip" | cut -f1 | tr -d ' ')
  printf "\n  %s files, %s\n" "$count" "$size"

  if [[ "$fail" != "0" ]]; then
    printf "\n${RED}Bundle failed validation. Do not upload it.${RESET}\n" >&2
    return 1
  fi
  # Every check passed — publish the archive under its final name. On any failure
  # above we return early and the RETURN trap deletes the partial file, so a
  # broken build never leaves a zip (0-byte or otherwise) to upload by mistake.
  mv -f "$tmpzip" "$zip"
  printf "\n  %s\n" "$zip"
  printf "\n${GREEN}Bundle is ready to upload at https://platform.openai.com/plugins${RESET}\n"
}

main() {
  if [[ "$BUNDLE_ONLY" == "1" ]]; then
    build_bundle "$BUNDLE_REF"
    return $?
  fi

  printf "${BLUE}=== Plugin Release Workflow ===${RESET}\n\n"

  # Preflight checks
  # Find the remote that points to the upstream AI repo (where marketplace looks for tags)
  local remote=""
  while IFS= read -r line; do
    name=$(echo "$line" | awk '{print $1}')
    url=$(echo "$line" | awk '{print $2}')
    if [[ "$url" == *"CrowdStrike/foundry-skills"* ]]; then
      remote="$name"
      break
    fi
  done < <(git remote -v | grep push)

  if [ -z "$remote" ]; then
    printf "${RED}ERROR: No remote found pointing to CrowdStrike/foundry-skills${RESET}\n" >&2
    printf "The marketplace references that repo. Add it with:\n" >&2
    printf "  git remote add upstream %s\n" "$MARKETPLACE_URL" >&2
    exit 1
  fi

  local branch
  branch=$(git rev-parse --abbrev-ref HEAD)
  if [ "$branch" != "main" ]; then
    printf "${RED}ERROR: Must be on main branch (currently on %s)${RESET}\n" "$branch" >&2
    exit 1
  fi

  if ! git diff --quiet || ! git diff --cached --quiet; then
    printf "${RED}ERROR: Working tree is dirty. Commit or stash changes first.${RESET}\n" >&2
    exit 1
  fi

  CURRENT_VERSION=$(get_current_version)
  printf "Current version: ${GREEN}${CURRENT_VERSION}${RESET}\n\n"

  if [ -n "$EXPLICIT_VERSION" ]; then
    # Validate the explicit version format
    if ! [[ "$EXPLICIT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      printf "${RED}ERROR: Invalid version format: %s (expected X.Y.Z)${RESET}\n" "$EXPLICIT_VERSION" >&2
      exit 1
    fi
    NEXT_VERSION="$EXPLICIT_VERSION"
    printf "Explicit version: ${YELLOW}${NEXT_VERSION}${RESET}\n"
  else
    # Prompt for bump type
    printf "Release type:\n"
    printf "  1) Major (breaking changes)\n"
    printf "  2) Minor (new features, backwards compatible)\n"
    printf "  3) Patch (bugfixes)\n\n"
    read -rp "Select [1-3]: " bump_choice

    case "$bump_choice" in
      1) BUMP_TYPE="major" ;;
      2) BUMP_TYPE="minor" ;;
      3) BUMP_TYPE="patch" ;;
      *)
        printf "${RED}Invalid choice${RESET}\n" >&2
        exit 1
        ;;
    esac

    read -r major minor patch <<< "$(parse_version "$CURRENT_VERSION")"
    NEXT_VERSION=$(calculate_next_version "$major" "$minor" "$patch" "$BUMP_TYPE")
    printf "\nVersion: ${CURRENT_VERSION} → ${YELLOW}${NEXT_VERSION}${RESET}\n"
  fi

  # Check tag doesn't already exist
  if git rev-parse "v${NEXT_VERSION}" >/dev/null 2>&1; then
    printf "${RED}ERROR: Tag v${NEXT_VERSION} already exists${RESET}\n" >&2
    exit 1
  fi

  read -rp "Proceed? (Y/n): " confirm
  if [[ "$confirm" =~ ^[Nn]$ ]]; then
    printf "Cancelled.\n"
    exit 0
  fi

  printf "\n${BLUE}Step 1: Update plugin manifests${RESET}\n"
  jq --arg v "$NEXT_VERSION" '.version = $v' "$CLAUDE_PLUGIN_JSON" > /tmp/claude-plugin.json.tmp
  mv /tmp/claude-plugin.json.tmp "$CLAUDE_PLUGIN_JSON"
  jq --arg v "$NEXT_VERSION" '.version = $v' "$CODEX_PLUGIN_JSON" > /tmp/codex-plugin.json.tmp
  mv /tmp/codex-plugin.json.tmp "$CODEX_PLUGIN_JSON"
  jq --arg v "$NEXT_VERSION" '.version = $v' "$ROOT_PLUGIN_JSON" > /tmp/root-plugin.json.tmp
  mv /tmp/root-plugin.json.tmp "$ROOT_PLUGIN_JSON"
  printf "${GREEN}✓${RESET} Claude, Codex, and Agent Plugins manifests → v${NEXT_VERSION}\n"

  printf "\n${BLUE}Step 1b: Update marketplace metadata${RESET}\n"
  jq --arg v "$NEXT_VERSION" '.plugins[0].version = $v' "$CLAUDE_MARKETPLACE_JSON" > /tmp/claude-marketplace.json.tmp
  mv /tmp/claude-marketplace.json.tmp "$CLAUDE_MARKETPLACE_JSON"
  jq --arg ref "v${NEXT_VERSION}" \
    '(.plugins[] | select(.name == "crowdstrike-falcon-foundry").source.ref) = $ref' \
    "$CODEX_MARKETPLACE_JSON" > /tmp/codex-marketplace.json.tmp
  mv /tmp/codex-marketplace.json.tmp "$CODEX_MARKETPLACE_JSON"
  printf "${GREEN}✓${RESET} Marketplace metadata → v${NEXT_VERSION}\n"

  printf "\n${BLUE}Step 2: Update README badge${RESET}\n"
  # Use portable sed with temp file pattern (macOS and Linux compatible)
  sed 's/badge\/version-[0-9.]*-blue/badge\/version-'"$NEXT_VERSION"'-blue/' "$SCRIPT_DIR/README.md" > /tmp/README.md.tmp
  mv /tmp/README.md.tmp "$SCRIPT_DIR/README.md"
  # Update the badge release link target
  sed 's|releases/tag/v[0-9.]*|releases/tag/v'"$NEXT_VERSION"'|' "$SCRIPT_DIR/README.md" > /tmp/README.md.tmp
  mv /tmp/README.md.tmp "$SCRIPT_DIR/README.md"
  printf "${GREEN}✓${RESET} README badge → v${NEXT_VERSION}\n"

  printf "\n${BLUE}Step 3: Update SKILL.md versions${RESET}\n"
  local today
  today=$(date +%Y-%m-%d)
  find "$SCRIPT_DIR/skills" -name SKILL.md | while read skill; do
    sed "s/^version: .*/version: $NEXT_VERSION/; s/^updated: .*/updated: $today/" "$skill" > /tmp/SKILL.md.tmp
    mv /tmp/SKILL.md.tmp "$skill"
  done
  printf "${GREEN}✓${RESET} All SKILL.md → v${NEXT_VERSION} (${today})\n"

  printf "\n${BLUE}Step 4: Update CHANGELOG date${RESET}\n"
  if grep -q "## \[${NEXT_VERSION}\] - TBD" "$SCRIPT_DIR/CHANGELOG.md"; then
    sed "s/## \[${NEXT_VERSION}\] - TBD/## [${NEXT_VERSION}] - ${today}/" "$SCRIPT_DIR/CHANGELOG.md" > /tmp/CHANGELOG.md.tmp
    mv /tmp/CHANGELOG.md.tmp "$SCRIPT_DIR/CHANGELOG.md"
    printf "${GREEN}✓${RESET} CHANGELOG [${NEXT_VERSION}] date → ${today}\n"
  else
    printf "${YELLOW}⚠${RESET} No [${NEXT_VERSION}] - TBD entry found in CHANGELOG.md (already dated?)\n"
  fi

  printf "\n${BLUE}Step 5: Commit and create PR${RESET}\n"
  local release_branch="release/v${NEXT_VERSION}"
  git checkout -b "$release_branch"
  git add "$CLAUDE_PLUGIN_JSON" "$CODEX_PLUGIN_JSON" "$ROOT_PLUGIN_JSON" \
    "$CLAUDE_MARKETPLACE_JSON" "$CODEX_MARKETPLACE_JSON" \
    "$SCRIPT_DIR/README.md" "$SCRIPT_DIR/skills"/*/SKILL.md \
    "$SCRIPT_DIR/CHANGELOG.md" "$SCRIPT_DIR/release.sh"
  git commit -m "Release v${NEXT_VERSION}"
  printf "${GREEN}✓${RESET} Committed v${NEXT_VERSION}\n"

  printf "\n${BLUE}Step 6: Push branch and create PR${RESET}\n"
  git push -u "$remote" "$release_branch"
  gh pr create --title "Release v${NEXT_VERSION}" --body "Version bump to v${NEXT_VERSION}."
  printf "${GREEN}✓${RESET} PR created\n"
  git checkout main

  printf "\n${BLUE}Step 7: After PR merges${RESET}\n"
  printf "\nOnce the PR is approved and merged, create a draft GitHub release:\n"
  printf "  gh release create v${NEXT_VERSION} --target main --title \"v${NEXT_VERSION}\" --generate-notes --draft\n\n"
  printf "This creates a draft release with auto-generated notes from merged PRs.\n"
  printf "Review and edit the notes at https://github.com/CrowdStrike/foundry-skills/releases,\n"
  printf "then click Publish when ready.\n\n"

  printf "${BLUE}Step 8: Update Anthropic Plugin Marketplace${RESET}\n"
  printf "\nAfter publishing the GitHub release, notify Anthropic of the new tag and SHA:\n"
  printf "  Tag: v${NEXT_VERSION}\n"
  printf "  SHA: \$(git rev-parse v${NEXT_VERSION})\n\n"
  printf "Anthropic handles the marketplace pin bump internally. Do not open PRs to\n"
  printf "anthropics/claude-plugins-official or re-submit through the plugin submission form.\n\n"

  printf "${BLUE}Step 9: Update OpenAI Plugins Directory${RESET}\n"
  printf "\nAfter publishing the GitHub release, build and verify the skills-only bundle:\n"
  printf "  ./release.sh --bundle v${NEXT_VERSION}\n\n"
  printf "That archives only what the skills need, checks it against the portal's\n"
  printf "structural rules, and refuses to produce an uploadable file if a skill\n"
  printf "references a path the archive is missing. Then upload it at:\n"
  printf "  https://platform.openai.com/plugins\n\n"
  printf "Submit the new version for review, then publish it after approval. The public\n"
  printf "Plugins Directory uses reviewed snapshots rather than the repository marketplace ref.\n\n"
  printf "${GREEN}Done.${RESET}\n"
}

main "$@"
