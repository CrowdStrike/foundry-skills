#!/usr/bin/env bash
#
# release.sh — Automate plugin release workflow
#
# 1. Prompt for semantic version bump (major/minor/patch)
# 2. Update version in .claude-plugin/plugin.json
# 3. Update README version badge
# 4. Update SKILL.md version and updated date
# 5. Update CHANGELOG date (TBD → today)
# 6. Commit, tag, and push
# 7. Print instructions for the marketplace PR
#
set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
RESET='\033[0m'

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PLUGIN_JSON="$SCRIPT_DIR/.claude-plugin/plugin.json"
MARKETPLACE_URL="https://github.com/CrowdStrike/foundry-skills.git"

# Read current version from plugin.json
get_current_version() {
  jq -r '.version' "$PLUGIN_JSON" 2>/dev/null || echo "0.0.0"
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

main() {
  printf "${BLUE}=== Plugin Release Workflow ===${RESET}\n\n"

  # Preflight checks
  # Find the remote that points to the upstream AI repo (where marketplace looks for tags)
  local remote=""
  while IFS= read -r line; do
    name=$(echo "$line" | awk '{print $1}')
    url=$(echo "$line" | awk '{print $2}')
    if [[ "$url" == *"/CrowdStrike/foundry-skills"* ]]; then
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

  printf "\n${BLUE}Step 1: Update plugin.json${RESET}\n"
  jq --arg v "$NEXT_VERSION" '.version = $v' "$PLUGIN_JSON" > /tmp/plugin.json.tmp
  mv /tmp/plugin.json.tmp "$PLUGIN_JSON"
  printf "${GREEN}✓${RESET} Updated to v${NEXT_VERSION}\n"

  printf "\n${BLUE}Step 1b: Update marketplace.json${RESET}\n"
  MARKETPLACE_JSON="$SCRIPT_DIR/.claude-plugin/marketplace.json"
  jq --arg v "$NEXT_VERSION" '.plugins[0].version = $v' "$MARKETPLACE_JSON" > /tmp/marketplace.json.tmp
  mv /tmp/marketplace.json.tmp "$MARKETPLACE_JSON"
  printf "${GREEN}✓${RESET} Updated to v${NEXT_VERSION}\n"

  printf "\n${BLUE}Step 2: Update README badge${RESET}\n"
  # Use portable sed with temp file pattern (macOS and Linux compatible)
  sed 's/badge\/version-[0-9.]*-blue/badge\/version-'"$NEXT_VERSION"'-blue/' "$SCRIPT_DIR/README.md" > /tmp/README.md.tmp
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
  git add "$PLUGIN_JSON" "$MARKETPLACE_JSON" "$SCRIPT_DIR/README.md" "$SCRIPT_DIR/skills"/*/SKILL.md "$SCRIPT_DIR/CHANGELOG.md"
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
  printf "${GREEN}Done.${RESET}\n"
}

main "$@"
