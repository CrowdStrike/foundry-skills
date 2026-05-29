# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [1.2.0] - TBD

### Added

- **Foundry-JS API integration pattern** — Added the `falcon.apiIntegration().execute()` pattern for calling external APIs from the UI to `ui-development/references/foundry-js.md`, with response structure and a cross-reference to Python/Go function examples.
- **Extension socket navigation** — The UI socket table now includes a console navigation column and the `identity.detections.details` socket, with verified paths to each socket's detail panel.

### Changed

- **collections-development** — Added pitfalls warning that schema field mismatches and invalid enum values return errors in the response body without throwing, so writes must check `result.errors`.
- **debugging-workflows** — Added troubleshooting rows for blank pages from an un-awaited `falcon.connect()` and data not appearing after writes due to schema mismatches.
- **development-workflow, ui-development** — Documented that `foundry apps validate`, `deploy`, and `ui run` must run from the app root; running from a subdirectory produces doubled paths and misleading file-not-found errors.

## [1.1.0] - 2026-05-13

### Added

- **e2e-testing skill** — End-to-end testing for Foundry apps using `@crowdstrike/foundry-playwright`. Covers the 4-project pipeline (authenticate → install → test → uninstall), page objects, configuration screens, custom page objects, CI with GitHub Actions, and debugging with Playwright MCP.
- **NGSIEM query export use case** — Export Falcon Next-Gen SIEM query results to CSV/JSON via Foundry functions with pagination and scheduled workflow patterns.
- **Foundry-JS reference** — `falcon.api.workflows`, `falcon.logscale`, `falcon.cloudFunction`, and collections CRUD patterns for `@crowdstrike/foundry-js` in `ui-development/references/foundry-js.md`.
- **Visual debugging section** in debugging-workflows — Screenshot-based troubleshooting with Playwright MCP and test failure artifacts.
- **agentskills.io metadata** — All skills now have top-level `tags`, `author`, `license`, and `compatibility` fields per the [agentskills.io](https://agentskills.io) open spec.

### Changed

- **development-workflow** — Expanded e2e testing guidance with credential configuration details, non-SSO user requirement, and app name alignment.
- **release.sh** — Added Step 8 documenting the Anthropic Plugin Marketplace update process (notify Anthropic of tag + SHA after each release).

### Removed

- **UI skill: stale E2E Testing section** — Removed placeholder in `ui-development/references/advanced-patterns.md` that used imaginary helpers predating `@crowdstrike/foundry-playwright`. Proper guidance now lives in the dedicated e2e-testing skill.

## [1.0.0] - 2026-04-29

Initial public release of Falcon Foundry Skills — AI coding assistant skills for building CrowdStrike Falcon Foundry apps.

### Skills

- **development-workflow** — Orchestrates the full app lifecycle from requirements through deployment. Coordinates all sub-skills and enforces CLI-first scaffolding.
- **api-integrations** — Create and configure API integrations with OpenAPI specs. Includes spec adaptation for Foundry compatibility and Falcon Fusion SOAR sharing.
- **collections-development** — Design and implement Foundry collections with JSON Schema modeling, CRUD operations via CustomStorage, and access control patterns.
- **functions-development** — Build serverless functions in Python or Go with FDK handler patterns, dependency management, and testing.
- **functions-falcon-api** — Call CrowdStrike Falcon APIs from within Foundry functions using zero-argument FalconPy authentication.
- **ui-development** — Build UI pages and extensions with React, Vue, or vanilla JS. Includes Foundry-JS patterns, Shoelace theming, and iframe communication.
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
