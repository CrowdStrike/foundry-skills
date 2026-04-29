# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-04-29

Initial public release of Falcon Foundry Skills — AI coding assistant skills for building CrowdStrike Falcon Foundry apps.

### Skills

- **development-workflow** — Orchestrates the full app lifecycle from requirements through deployment. Coordinates all sub-skills and enforces CLI-first scaffolding.
- **api-integrations** — Create and configure API integrations with OpenAPI specs. Includes spec adaptation for Foundry compatibility and Falcon Fusion SOAR sharing.
- **collections-development** — Design and implement Foundry collections with JSON Schema modeling, CRUD operations via CustomStorage, and access control patterns.
- **functions-development** — Build serverless functions in Python or Go with FDK handler patterns, dependency management, and testing.
- **functions-falcon-api** — Call CrowdStrike Falcon APIs from within Foundry functions using zero-argument FalconPy authentication.
- **ui-development** — Build UI pages and extensions with React, Vue, or vanilla JS. Includes FalconJS SDK patterns, Shoelace theming, and iframe communication.
- **workflows-development** — Design Falcon Fusion SOAR workflows with YAML specs, CEL expressions, loop/condition control flow, and platform action integration.
- **debugging-workflows** — Systematic troubleshooting for CLI errors, deployment failures, blank pages, and runtime issues.
- **security-patterns** — OAuth scoping, input validation, XSS prevention, CSP configuration, and secure coding patterns.

### Infrastructure

- **CLI guard hook** (`hooks/foundry-cli-guard.sh`) — Automatically validates Bash commands to enforce `--no-prompt`, block manual directory creation, and validate socket IDs.
- **Spec adaptation script** (`scripts/adapt-spec-for-foundry.py`) — Fixes common OpenAPI spec issues (server variables, auth schemes, parameter deduplication) before `foundry api-integrations create`.
- **Test harness** (`test-skill.sh`, `run-ab-test.sh`, `verify-apps.sh`) — Automated skill evaluation with token counting, anti-pattern detection, deploy verification, and A/B comparison.

### Use Cases

12 real-world implementation patterns extracted from [CrowdStrike Tech Hub](https://www.crowdstrike.com/tech-hub/ng-siem/) blog posts covering API pagination, detection enrichment, LogScale ingestion, custom SOAR actions, collections, and more.

### Multi-Tool Support

- **`AGENTS.md`** — Canonical AI agent instruction file with tool-agnostic Foundry development guidance (CLI commands, skills ecosystem, quality guidelines, contribution conventions).
- **`CLAUDE.md`** — Claude Code-specific plugin additions (hooks, superpowers integration, safety enforcement). References `AGENTS.md` for the full development guide.
- **`.github/copilot-instructions.md`** — Redirect for GitHub Copilot.
- **`GEMINI.md`** — Redirect for Gemini CLI.
- **`.cursorrules`** — Redirect for Cursor.
