# CLAUDE.md

Before responding to any Foundry development request, read [AGENTS.md](./AGENTS.md) for the complete CLI reference, skills ecosystem, and development guide.

Below are Claude Code-specific additions for this plugin.

## Plugin Hook Behavior

This plugin includes four hooks that run automatically:

- **SessionStart**: `foundry-session-start.sh` checks CLI version and initializes the Foundry environment
- **UserPromptSubmit**: `foundry-skill-router.sh` routes user intents to the appropriate skill
- **PreToolUse (Bash)**: `foundry-cli-guard.sh` checks Bash commands and adds advisory context when a Foundry CLI command is missing a required flag such as `--no-prompt`, or when app structure is being created by hand
- **PreToolUse (Skill)**: `superpowers-foundry-bridge.sh` intercepts `superpowers:brainstorming` and redirects to the Foundry development workflow skill

## Automated Safety Enforcement

The `foundry-cli-guard.sh` hook checks every Bash command and flags:

- Foundry CLI commands missing `--no-prompt` (prevents `Error: EOF` failures)
- Manual directory/file creation for app structure (prevents invalid manifest.yml)

The hook is advisory: it adds context to the tool call but doesn't block or rewrite the command, so the command still runs as written. Get the flags right before running.

## Skills Integration with Claude Code Workflows

**Planning Integration**: For structured planning with review checkpoints, install [superpowers](https://github.com/obra/superpowers) (`superpowers:writing-plans`, `superpowers:executing-plans`). Without superpowers, the orchestrator provides basic planning guidance that accounts for Foundry's capability and manifest dependencies.

**Execution Integration**: If superpowers is installed, `superpowers:executing-plans` provides batch execution with review checkpoints between capabilities. Otherwise, use the orchestrator's built-in execution checkpoints.

**Testing Integration**: If superpowers is installed, `superpowers:test-driven-development` enforces RED-GREEN-REFACTOR discipline. Each Foundry sub-skill also has its own capability-specific testing patterns.

**Handoff Integration**: Preserve Foundry-specific CLI state (profiles, authentication, `foundry ui run` status) when handing off between sessions.

## Essential Skills Commands

**Accessing Skills**: Skills are automatically invoked by Claude Code when working on Foundry development tasks. You can reference them explicitly using `@skills/skill-name` syntax.

**Skills Documentation**: Each skill includes comprehensive documentation in its `SKILL.md` file with specific patterns, testing approaches, and integration guidance.

**Skills Coordination**: The development-workflow skill ensures proper coordination between all sub-skills and maintains CLI state consistency throughout development.
