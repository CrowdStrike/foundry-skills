# CLAUDE.md

Before responding to any Foundry development request, read [AGENTS.md](./AGENTS.md) for the complete CLI reference, skills ecosystem, and development guide.

Below are Claude Code-specific additions for this plugin.

## Plugin Hook Behavior

This plugin includes four hooks that run automatically:

- **SessionStart**: `foundry-session-start.sh` checks CLI version and initializes the Foundry environment
- **UserPromptSubmit**: `foundry-skill-router.sh` routes user intents to the appropriate skill
- **PreToolUse (Bash)**: `foundry-cli-guard.sh` validates all Bash commands to ensure Foundry CLI commands include `--no-prompt` and blocks manual directory/file creation for app structure
- **PreToolUse (Skill)**: `superpowers-foundry-bridge.sh` intercepts `superpowers:brainstorming` and redirects to the Foundry development workflow skill

## Automated Safety Enforcement

The `foundry-cli-guard.sh` hook automatically validates all Bash commands to ensure:

- Foundry CLI commands always include `--no-prompt` flag (prevents `Error: EOF` failures)
- Manual directory/file creation for app structure is blocked (prevents invalid manifest.yml)
- Commands are corrected before execution with clear error messages

This enforcement runs automatically. You don't need to remember the rules; the hook will catch mistakes before they cause failures.

## Skills Integration with Claude Code Workflows

**Planning Integration**: For structured planning with review checkpoints, install [superpowers](https://github.com/obra/superpowers) (`superpowers:writing-plans`, `superpowers:executing-plans`). Without superpowers, the orchestrator provides basic planning guidance that accounts for Foundry's 47 capability types and manifest dependencies.

**Execution Integration**: If superpowers is installed, `superpowers:executing-plans` provides batch execution with review checkpoints between capabilities. Otherwise, use the orchestrator's built-in execution checkpoints.

**Testing Integration**: If superpowers is installed, `superpowers:test-driven-development` enforces RED-GREEN-REFACTOR discipline. Each Foundry sub-skill also has its own capability-specific testing patterns.

**Handoff Integration**: Preserve Foundry-specific CLI state (profiles, authentication, `foundry ui run` status) when handing off between sessions.

## Counter-Rationalizations

The skills enforce discipline to prevent common failures:

| Your Excuse | Reality |
|-------------|---------|
| "I have API experience" | Foundry APIs have platform-specific auth, discovery, and error handling |
| "Time pressure means skip sub-skills" | Sub-skills PREVENT rework that costs 10x more time |
| "I can learn patterns during implementation" | Learning while implementing = building on wrong assumptions |
| "Sub-skills are overkill for simple cases" | No Foundry capability is simple - platform complexity is hidden |

## Essential Skills Commands

**Accessing Skills**: Skills are automatically invoked by Claude Code when working on Foundry development tasks. You can reference them explicitly using `@skills/skill-name` syntax.

**Skills Documentation**: Each skill includes comprehensive documentation in its `SKILL.md` file with specific patterns, testing approaches, and integration guidance.

**Skills Coordination**: The development-workflow skill ensures proper coordination between all sub-skills and maintains CLI state consistency throughout development.
