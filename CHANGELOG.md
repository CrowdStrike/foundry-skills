# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [1.4.0] - TBD

### Added

- **GraphQL APIs use case** — Integrate GraphQL APIs (Falcon Identity Protection, GitHub, Snyk) into Foundry apps using FalconPy or HTTP POST. Covers zero-arg auth for Falcon GraphQL endpoints and the security tradeoff of env vars vs API integrations for third-party APIs.

## [1.3.0] - 2026-06-11

> Changes in this release were identified by running automated eval prompts against the skills with Sonnet and Opus, then investigating failures and judging feedback to find skill gaps.

### Added

**Functions & API Integrations:**
- Credential management section with decision table (API integration vs FalconPy vs env vars) and callout that raw HTTP works but credentials are unencrypted and visible in app exports.
- OAuth scope reference table mapping FalconPy classes and methods to required manifest scopes, derived from all production sample apps. Notes that built-in capabilities don't need explicit scopes. Eval runs confirmed this corrects invalid scope generation (e.g., `detects-read` → `detects:read`, `collection-management-read` → `custom-storage:read`).
- Context paragraph explaining API integrations ARE Foundry's credential management system.

**UI:**
- Vanilla JS as a first-class template option for pages and extensions. Includes CLI scaffolding examples, note that no npm install/build step is needed, and clarification that vite/build-related pitfalls are React-specific.
- Async `connect()` callout explaining `falcon.connect()` must be in `useEffect` and navigation must be accessed after connect resolves via `useMemo` with React state (`isInitialized`).

**Workflows:**
- HTTP Actions reference (`references/http-actions.md`) with verified `Inline.HTTPRequest` schema, both auth patterns (API key header and OAuth 2.0 client credentials), status-code conditional routing, and an HTTP-Actions-vs-API-integration decision guide. Added a callout so HTTP Actions are suggested for simple REST calls that don't need an app.
- Collection config lookup workflow example showing the pattern for reading user-configured settings from a collection before performing an action.
- Response Action Workflow (Contain Host) example showing platform action discovery and usage. Added Contain device action ID to platform actions table.
- Null-guard warning near trigger parameters explaining they're prompted in the UI but may be empty via API or sub-workflow calls.

### Fixed

**Functions & API Integrations:**
- Strengthened zero-arg constructor pitfall to explicitly call out the `os.environ` anti-pattern. Clarified this applies to FalconPy only (Go requires explicit credential wiring).
- Added Falcon severity values reference table for mapping to external ticketing systems.
- Clarified CustomStorage bulk read pattern: use FQL filters instead of sequential GetObject loops.
- Corrected `definition_id` vs name guidance: name works in production, UUID only needed for local testing. Fixed raw HTTP claim from "won't work" to "works but credentials are unencrypted."
- Added `APIIntegrations().execute_command_proxy()` code examples showing how to call registered third-party API integrations from function code. Includes request body/params patterns, explanation of why the platform proxy is required, and references to 3 sample repos.

**UI:**
- Improved CSP/Shoelace icons pitfall to mention Foundry's CSP allowlist and local asset alternative.

**Workflows:**
- Clarified `system_action` guidance: `false` exposes the workflow as a SOAR response action, `true` keeps it internal. Changed example default to `false` since most on-demand workflows should be SOAR-visible.
- Added callout that workflows must use registered API integrations, not raw HTTP via functions with hardcoded credentials.
- Fixed incorrect trigger parameter variable syntax. Was `${data['trigger.param_name']}`, corrected to `${data['param_name']}` (no prefix). Validated against foundry-sample-foundryjs-demo, security-skills (20+ workflows), and all other sample repos.
- Fixed CEL `has()` usage: `has(data['key'])` doesn't work in Fusion (throws `Q0910: invalid argument to has() macro`). Replaced with `data['key'] != null`. Documented that `has()` works on object fields after retrieval, not directly on data store keys.
- Added modern optional patterns: `data[?'key'].orValue(default)`, `.or()` fallback chains, safe list existence checks. Preferred over verbose `!= null` ternaries.
- Fixed version_constraint guidance: was oversimplified ("~0 for functions, ~1 for platform actions"). Corrected to explain it pins against the activity's `semantic_version` field. Some platform actions like "contain device" have no semantic_version and require `~0`.
- Forced workflows-development sub-skill loading from orchestrator to prevent hallucinated workflow formats.

## [1.2.0] - 2026-06-03

### Added

- **Deploy command validation** — The CLI guard hook now catches missing `--change-type` and `--change-log` flags on `foundry apps deploy`, preventing a 500 error from the Foundry API.
- **Foundry-JS API integration pattern** — Added the `falcon.apiIntegration().execute()` pattern for calling external APIs from the UI to `ui-development/references/foundry-js.md`, with response structure and a cross-reference to Python/Go function examples.
- **Extension socket navigation** — The UI socket table now includes a console navigation column and the `identity.detections.details` socket, with verified paths to each socket's detail panel.
- **Python function testing** — Added Falcon console testing documentation for Python functions, including discovering the Function logs button.

### Changed

- **ui-development** — Documented that `navigateTo` defaults `target` to `_self` when omitted (navigates in the same tab). Confirmed from foundry-js source.
- **collections-development** — Added pitfalls warning that schema field mismatches and invalid enum values return errors in the response body without throwing, so writes must check `result.errors`.
- **debugging-workflows** — Added troubleshooting rows for blank pages from an un-awaited `falcon.connect()` and data not appearing after writes due to schema mismatches.
- **development-workflow, ui-development** — Documented that `foundry apps validate`, `deploy`, and `ui run` must run from the app root; running from a subdirectory produces doubled paths and misleading file-not-found errors.

### Fixed

- **Inclusive terminology** — Changed "Whitelist approach" to "Allowlist approach" in security-examples.md.
- **verify-apps.sh extension verification** — Instructions now scroll to find the accordion, expand it, wait for the iframe to load, and check for content inside — matching the `expandExtensionInSocket()` pattern from `@crowdstrike/foundry-playwright`.
- **test-skill.sh warmup** — Use `--model haiku` for the API health check to avoid wasting Opus tokens on a connectivity test.
- **tail-test.sh** — Suppress `find` stderr when test directories don't exist yet.

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

13 real-world implementation patterns extracted from [CrowdStrike Tech Hub](https://www.crowdstrike.com/tech-hub/ng-siem/) blog posts covering API pagination, detection enrichment, LogScale ingestion, custom SOAR actions, collections, GraphQL APIs, and more.

### Multi-Tool Support

- **`AGENTS.md`** — Canonical AI agent instruction file with tool-agnostic Foundry development guidance (CLI commands, skills ecosystem, quality guidelines, contribution conventions).
- **`CLAUDE.md`** — Claude Code-specific plugin additions (hooks, superpowers integration, safety enforcement). References `AGENTS.md` for the full development guide.
- **`.github/copilot-instructions.md`** — Redirect for GitHub Copilot.
- **`GEMINI.md`** — Redirect for Gemini CLI.
- **`.cursorrules`** — Redirect for Cursor.
