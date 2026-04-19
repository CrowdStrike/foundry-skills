# AI Agent Instructions for foundry-skills

This repository is an AI coding assistant plugin for [CrowdStrike Falcon Foundry](https://www.crowdstrike.com/en-us/platform/next-gen-siem/falcon-foundry/) development. It provides specialized skills that guide AI assistants through building complete Foundry apps, covering UI pages, serverless functions, data collections, automation workflows, and API integrations.

The skills are markdown-based and usable by any AI coding assistant. Claude Code users should also see [CLAUDE.md](./CLAUDE.md) for plugin-specific hook and integration details.

## Prerequisites

- **Foundry CLI**: Install cross-platform:
  - macOS/Linux: `brew tap crowdstrike/foundry-cli && brew install crowdstrike/foundry-cli/foundry`
  - Windows: Download https://assets.foundry.crowdstrike.com/cli/latest/foundry_Windows_x86_64.zip, expand it, add the installation directory to PATH
- **Authentication**: Run `foundry login` to authenticate with CrowdStrike, or use `foundry profile create --no-prompt` for headless environments
- **Development Environment**: Node.js, Python, or Go depending on your app requirements
- **CLI Reference**: https://docs.crowdstrike.com/r/v5114866

## Repository Structure

- `skills/` - 9 specialized development skills, each with a `SKILL.md` file
- `hooks/` - Hook scripts for Claude Code plugin integration
- `use-cases/` - Real-world implementation patterns extracted from [CrowdStrike Tech Hub](https://www.crowdstrike.com/tech-hub/ng-siem/?cspage=0&lang=English&type=Article) blog posts
- `scripts/` - Helper scripts (OpenAPI spec adaptation, linting)
- `.claude-plugin/` - Claude Code plugin manifest and marketplace configuration

## Skills Ecosystem

The `skills/` directory contains specialized skills that provide systematic approaches for Foundry development. These skills enforce best practices, prevent technical debt, and ensure platform-specific patterns are followed correctly.

### Core Principles

**Mandatory Sub-Skill Delegation**: The foundry-development-workflow skill enforces that all capability development must use the appropriate specialized sub-skill. This prevents platform-specific mistakes and ensures consistent quality.

**Capability-Based Architecture**: Each skill maps to specific Foundry platform capabilities:

- **UI capabilities** → foundry-ui-development
- **Data capabilities** → foundry-collections-development
- **Logic capabilities** → foundry-functions-development
- **Automation capabilities** → foundry-workflows-development

**Security-First Design**: Security patterns are integrated throughout all skills, with dedicated foundry-security-patterns for specialized security guidance.

### Primary Workflow Skills

#### Foundry Development Workflow (Primary Orchestrator)

**Always starts here** - coordinates complete app lifecycle and enforces sub-skill delegation.

**Critical Functions**:

- CLI state management (`foundry profile`, authentication, `foundry ui run`)
- Manifest.yml coordination across all capabilities
- Sub-skill delegation enforcement (NO direct implementation allowed)

#### Capability-Specific Skills

**Specialized skills for each Foundry capability type:**

- **foundry-ui-development**: Vue/React + Shoelace UI components and extensions
- **foundry-collections-development**: JSON Schema data modeling and CRUD operations
- **foundry-functions-development**: Go/Python serverless functions with CrowdStrike SDK
- **foundry-workflows-development**: YAML automation workflows and Fusion orchestration
- **foundry-functions-falcon-api**: Calling Falcon APIs from within Functions (OAuth, SDKs)
- **foundry-api-integrations**: Exposing external APIs via OpenAPI specs

#### Support Skills

**Cross-cutting concerns and troubleshooting:**

- **foundry-security-patterns**: OAuth scoping, input validation, UI security
- **foundry-debugging-workflows**: Systematic troubleshooting for CLI, manifest, and API issues

### Use Cases

The `use-cases/` directory contains real-world implementation patterns extracted from [CrowdStrike Tech Hub](https://www.crowdstrike.com/tech-hub/ng-siem/?cspage=0&lang=English&type=Article) blog posts. Each file captures an actionable pattern (not a summary) that AI assistants can apply when users describe similar scenarios. The orchestrator searches use-case frontmatter to match user requests, and sub-skills reference specific use cases for context.

### Skills Usage Patterns

#### Starting New Foundry Development

```
1. foundry-development-workflow coordinates the lifecycle
2. Specialized sub-skills for each capability (UI, Collections, Functions, Workflows)
3. foundry-security-patterns for security review
```

#### Working with Existing Foundry Apps

```
1. foundry-development-workflow assesses current state
2. Appropriate sub-skill for the capability being modified
3. foundry-debugging-workflows if issues arise
4. foundry-security-patterns for security validation
```

#### Common Development Scenarios

- **"Add UI extension"** → foundry-ui-development skill
- **"Create data schema"** → foundry-collections-development skill
- **"Build API endpoint"** → foundry-functions-development skill
- **"Automate workflow"** → foundry-workflows-development skill
- **"Call Falcon API from Function"** → foundry-functions-falcon-api skill
- **"Expose external API to Foundry"** → foundry-api-integrations skill
- **"Troubleshoot deployment"** → foundry-debugging-workflows skill

## Essential Foundry CLI Commands

> **⚠️ CRITICAL: Always use `--no-prompt` with creation commands**
>
> AI coding assistants operate in non-interactive environments. Commands that prompt for user input will fail with `Error: EOF`. **ALWAYS** include `--no-prompt` on any command that supports it.

> **🚫 NEVER CREATE APP DIRECTORIES OR FILES MANUALLY**
>
> **ABSOLUTELY FORBIDDEN:** Using `mkdir`, `touch`, or manually creating app-related directories (api-integrations/, workflows/, functions/, collections/, ui/) or files (manifest.yml, etc.). The Foundry CLI generates these with correct structure, IDs, and manifest entries.
>
> **If a CLI command fails:**
>
> 1. ✅ Fix the command (add `--no-prompt`, check flags, verify auth)
> 2. ✅ Retry the corrected CLI command
> 3. ❌ **NEVER** fall back to `mkdir` or manual creation
>
> **Manual creation causes:** Invalid manifest.yml, missing generated IDs, broken app structure, hours of debugging

```bash
# Authentication & Environment Management
foundry login                              # OAuth-based authentication
foundry profile list                       # View available profiles (US-1, US-2, EU-1, US-GOV)
foundry profile active                     # Show current active profile
foundry profile activate --name <name>     # Switch between environments

# App Development Lifecycle
foundry apps create --name "X" --no-prompt --no-git  # Create new app
foundry apps run                           # Start full app locally in dev mode
foundry apps deploy --change-type Patch --change-log "msg" --no-prompt  # Deploy to cloud
foundry apps release --change-type Patch --deployment-id <id> --notes "notes"  # Release to app catalog
foundry ui run                             # Local UI development server

# Scaffolding Commands (ALWAYS use --no-prompt)
foundry api-integrations create --name "X" --spec path.json --no-prompt   # Create API integration
foundry ui pages create --name "X" --from-template React --no-prompt       # Create UI page
foundry ui extensions create --name "X" --from-template React --sockets "socket.name" --no-prompt  # Create UI extension
foundry ui navigation add --name "X" --path / --ref pages.xxx  # Add navigation
foundry functions create --name "X" --language python --no-prompt           # Create function
foundry collections create --name "X" --schema path.json --no-prompt        # Create collection
foundry workflows create --name "X" --spec path.yaml --no-prompt            # Create workflow
```

## Quality and Thoroughness

When building Falcon Foundry apps, take your time and do each step thoroughly. Quality is more important than speed. Specifically:

- Do not skip validation steps (deploy early after API integrations and collections to catch spec issues)
- Do not skip the Vite `noAttr()` fix for UI pages - a blank page wastes more time than the 30 seconds to add it
- Read each sub-skill's Common Pitfalls section before implementing that capability
- Verify CLI commands succeed before moving to the next step - do not chain multiple scaffolding commands blindly

## Security Considerations

- **Never commit credentials** - CLI handles authentication
- **Scoped permissions** - Request minimal required permissions in manifest
- **Iframe security** - UI runs in sandboxed environment
- **API rate limiting** - Respect CrowdStrike API limits

## Contribution Conventions

- All `SKILL.md` versions must match the version in `.claude-plugin/plugin.json`
- Hook scripts in `hooks/` must be executable (`chmod +x`)
- Run `./test-hooks.sh` before submitting a pull request
- Run `npx markdownlint-cli2 "**/*.md"` to validate markdown formatting
- Snapshots and use-case files follow standardized frontmatter formats
