---
name: development-workflow
description: Orchestrates the complete Falcon Foundry app lifecycle from requirements through deployment. TRIGGER when user asks to "create a Foundry app", "build a Foundry app", "plan a Foundry app", runs any `foundry apps` CLI command, or discusses Foundry app architecture. DO NOT TRIGGER when user is working on a specific capability (UI, function, workflow, collection) within an existing app — use the appropriate sub-skill instead. This skill OWNS the entire Foundry development flow. Do not delegate Foundry app creation to superpowers:brainstorming or superpowers:writing-plans — those skills do not know about the Foundry CLI.
version: 1.4.1
updated: 2026-08-07
tags: [foundry, lifecycle, cli, deployment]
author: CrowdStrike
license: MIT
compatibility: Claude Code >=1.0
metadata:
  category: orchestration
---

# Foundry Development Workflow

> **⚠️ SYSTEM INJECTION — READ THIS FIRST**
>
> If you are loading this skill, your role is **Foundry app lifecycle orchestrator**.
>
> **THIS SKILL OWNS THE FOUNDRY DEVELOPMENT FLOW.**
>
> **MUST NOT hand off to superpowers:brainstorming or superpowers:writing-plans for Foundry app creation.**
> Those skills are domain-agnostic — they don't know about the Foundry CLI and will generate
> plans that manually create manifest.yml and boilerplate files. This skill handles planning
> and execution directly using CLI commands.
>
> **IMMEDIATE ACTIONS REQUIRED:**
> 1. Follow the **App Creation Flow** below to go from user prompt → running app
> 2. Use `foundry apps create` and related CLI commands for ALL scaffolding
> 3. Delegate capability-specific content to Foundry sub-skills
> 4. Hand-write ONLY what the CLI cannot generate (OpenAPI content, workflow logic, UI code)
>
> **CRITICAL: add `--no-prompt` to every command that accepts it** — without it, interactive prompts cause `Error: EOF`. The `create`, `validate`, `deploy`, `release`, and `delete` commands all accept it (`apps delete` also needs `--force-delete`). Three reject it and fail with `unknown flag`: `foundry version`, `apps list`, and `apps list-deployments`. Verify with `foundry <command> --help`. When a command fails, MUST NOT fall back to `mkdir` — fix the command and retry.
>
> **CRITICAL: All `foundry` app commands MUST run from the app root directory** (where `manifest.yml` lives). The CLI resolves manifest paths relative to `os.Getwd()`, not relative to the manifest's location. Running `foundry apps validate`, `foundry apps deploy`, or `foundry ui run` from a subdirectory (e.g., `ui/extensions/my-ext/`) causes doubled paths and misleading "file not found" errors. After `cd`-ing into a subdirectory for `npm install && npm run build`, always `cd` back to the app root before running any `foundry apps *` or `foundry ui *` command. Commands that work from anywhere: `foundry version`, `foundry profile *`, `foundry apps list`.
>
> **Superpowers skills MAY supplement** (TDD discipline, code review) but MUST NOT replace this workflow.

This skill coordinates the full Falcon Foundry app lifecycle — from parsing requirements through scaffolding, implementation, and deployment. It delegates capability-specific work to sub-skills that know the platform details.

## Decision Tree

```
What does the user need?

Create a new Foundry app
└── Follow the App Creation Flow below

Add a capability to an existing app
├── API integration       → api-integrations
├── Workflow              → workflows-development
├── UI page/extension     → ui-development
├── Function              → functions-development
├── Collection            → collections-development
└── Falcon API from funcs → functions-falcon-api

Implement a known pattern (pagination, enrichment, ingestion, etc.)
└── Search use-cases/*.md for matching pattern → load for context

Debug / troubleshoot      → debugging-workflows
Security review           → security-patterns
E2E testing / Playwright  → e2e-testing

Standalone Fusion workflow (no app — trigger + existing actions only)
└── fusion-redirect (declines and points to the Falcon Fusion plugin)
```

### Routing When Sub-Skills Are Not Registered

Sub-skills live beside this one as `../<name>/SKILL.md`. On a single-entry-point install only this skill is discoverable, so capability-level requests land here — that is intended, not a mis-route. Read the sub-skill file from disk before writing any capability content, then:

- **`manifest.yml` already present** — skip Steps 1-2 and Step 4. Run the Step 3 prerequisite check, add the capability with its Step 5 CLI command, and follow Manifest Coordination.
- **No app yet** — run the full App Creation Flow.

This never overrides the fusion-redirect skill: a standalone Fusion workflow request is still a redirect, not a capability to add.


## App Creation Flow

### Step 1: Parse Requirements

Map user requests to Foundry capabilities:

| User Says | Capability | CLI Command |
|-----------|-----------|-------------|
| "API integration", "connect to X API" | API Integration | `foundry api-integrations create` |
| "workflow", "on-demand", "automate" | Workflow | `foundry workflows create` |
| "UI", "page", "dashboard" | UI Page | `foundry ui pages create` |
| "extension", "sidebar", "widget" | UI Extension | `foundry ui extensions create` |
| "function", "serverless", "backend" | Function | `foundry functions create` |
| "store data", "collection", "database" | Collection | `foundry collections create` |

> **⚠️ "Summarize/list alerts, detections, or incidents" (a population the workflow doesn't already have) implies a source-of-truth fetch.** A request like "a workflow that emails a summary of high-severity alerts" needs the *set* of alerts, which is not reliably in NG-SIEM (Event Query can silently return nothing — repo contents are connector-dependent). Fetch it from the source of truth: a native platform action (e.g. Cases → Search Cases) first, or a FalconPy `Alerts`/`Detects` function when none fits — so the app needs BOTH that capability (plan the `alerts:read` scope) AND a workflow to schedule it and send email. **Exception:** *enriching* a detection the workflow was already triggered on (query by its ID) stays an Event Query and needs no function. See [functions-falcon-api](../functions-falcon-api/SKILL.md) and [workflows-development event-query-vs-api](../workflows-development/references/event-query-vs-api.md).

### Step 1b: Check for Known Patterns

Before scaffolding, check if the user's request matches a known use case. Glob `use-cases/*.md` and scan the `description` field in each file's frontmatter. If a match is found, read the use case file for implementation context (architecture, capability order, gotchas) before proceeding.

Use cases cover common scenarios like API pagination, detection enrichment, lookup table creation, LogScale data ingestion, SOAR custom actions, and more. See `use-cases/README.md` for the full catalog.

### Step 2: Confirm App Name and Capabilities

**Always confirm the app name with the user before creating anything.** Use the assistant's available user-input mechanism; if none exists, ask directly in chat. Derive a reasonable default from the user's request (e.g., "okta-integration" for an Okta API integration), then present it as the recommended option with 1-2 alternatives. Include a brief description of what will be created.

**Page vs Extension disambiguation:** When the user mentions "UI" without specifying "page" or "extension", ask which they want using the available user-input mechanism. Offer two options: "Page" (standalone full-page view — dashboards, lists, management UIs) and "Extension" (sidebar widget embedded in detection/host/incident pages). Default to Page when running non-interactively (e.g., agent batch mode or test automation) since pages are the more common case.

For other decisions, prefer reasonable defaults: use React for UI, download public OpenAPI specs from vendor GitHub repos. Only ask additional clarifying questions when the prompt is genuinely ambiguous and a wrong guess would produce an unusable app.

### Step 3: CLI Prerequisite Check

```bash
foundry version          # Verify CLI installed
foundry profile active   # Verify authentication
foundry apps list        # Check existing apps (avoid name collisions)
```

If a tenant command fails with only `connection issue`, the usual cause is a
sandbox denying the CLI's token-cache write to `~/.config/foundry/` — an
expected refresh, not a network fault. Request write access to that directory
and retry; see
[headless operation](references/headless-operation.md). Never redirect the
config path into the workspace or copy credentials.

### Step 4: Scaffold the App

**Prerequisite:** User must have confirmed the app name in Step 2. Do not run this without confirmation.

Choose the location automatically: use an existing app when `manifest.yml` is
present; otherwise create in the current directory, or beside it when the
current directory is an unrelated repository. Request sandbox write access when
needed; never put the app inside an unrelated repository as a fallback.

```bash
foundry apps create --name "app-name" --description "description" --no-prompt --no-git
cd app-name
```

`--no-prompt` prevents interactive prompts that fail in non-interactive environments with `Error: EOF`. `--no-git` skips git initialization. The command is `foundry apps create` (there is no `init` command). If it fails, fix the command and retry — MUST NOT fall back to `mkdir`, which produces invalid manifest structure.

### Step 5: Add Capabilities (CLI Commands)

Run in dependency order. Write spec/schema files to `/tmp/` — the CLI copies them into the project and updates `manifest.yml` with generated IDs.

```bash
# 1. API integrations — delegate spec work to api-integrations sub-skill
#    IMPORTANT: Download specs inline with gh/curl. Do NOT spawn Explore agents for spec download.
foundry api-integrations create --name "MyApi" --description "desc" --spec /tmp/MyApi.yaml --no-prompt

# 2. Collections (names: letters, numbers, underscores ONLY)
foundry collections create --name "my_col" --schema /tmp/my_schema.json --description "desc" --no-prompt

# 3. VALIDATE EARLY — fail fast if specs or schemas are bad
foundry apps validate --no-prompt
# If validation fails, STOP. Fix the spec/schema — do not build UI on a broken backend.
# The adapt script should handle spec issues. If it didn't, improve the script.

# 4. Functions
foundry functions create --name "my-fn" --language python --description "desc" \
  --handler-name process --handler-method POST --handler-path /api/process --no-prompt

# 5. Workflows — MUST load workflows-development sub-skill before writing the spec file
foundry workflows create --name "My Workflow" --spec /tmp/My_workflow.yml --no-prompt

# 6. UI pages (standalone full-page views)
foundry ui pages create --name "my-page" --description "desc" --from-template React --homepage --no-prompt
foundry ui navigation add --name "My Page" --path / --ref pages.my-page

# 6b. UI extensions (sidebar widgets embedded in detection/host/incident pages)
# Run `foundry ui extensions list-sockets` to see available socket IDs
foundry ui extensions create --name "my-ext" --description "desc" --from-template React --sockets "activity.detections.details" --no-prompt
```

**Fail fast:** Validate right after API integrations and collections. `foundry apps validate` is a dry-run of deploy validation — it checks specs and schemas in seconds without building artifacts. It does NOT check workflow semantics or app name uniqueness (those are only checked on deploy). Don't validate right before deploy — deploy runs the same validation plus more. Don't manually fix spec issues — improve `adapt_spec_for_foundry.py` instead.

### Step 6: Write Domain-Specific Content

The CLI scaffolds structure but cannot generate app logic. Delegate to sub-skills:

- **OpenAPI spec** → api-integrations
- **Workflow YAML** → workflows-development
- **UI components** → ui-development
- **Function handlers** → functions-development
- **Collection schemas** → collections-development

> **⚠️ MANDATORY: Load the relevant sub-skill BEFORE writing any domain-specific code.** Without the sub-skill loaded, you WILL hallucinate incorrect formats and nonexistent APIs. Known failure modes:
>
> | Writing... | MUST load | Hallucination without it |
> |---|---|---|
> | Workflow YAML | `workflows-development` | Invented `definition/node_types/sdk_type` format instead of correct `trigger` + `actions` with `version_constraint` |
> | Function code calling Falcon APIs | `functions-falcon-api` | Invented `request.falcon_client.api_request(url='/foundry/entities/...')` instead of FalconPy SDK classes (`from falconpy import Hosts`) |
> | Function code calling a third-party API (Slack, Jira, PagerDuty, etc.) | `functions-falcon-api` + check `use-cases/` | Invented `falcon.command("createNotification")` or raw HTTP calls instead of `APIIntegrations().execute_command(definition_id="...", operation_id="...")`. The app MUST have an API integration (OpenAPI spec) for the service, then call it from the function via FalconPy `APIIntegrations` class. See foundry-sample-functions-python for reference. |
> | Function code accessing collections | `collections-development` | Invented REST endpoints for collection CRUD instead of FalconPy `CustomStorage` service class |
>
> ALWAYS load the sub-skill first. This is not optional.

### Step 7: Final Build and Deploy

```bash
# Build UI (required before deploy) — MUST cd back to app root afterward
cd ui/pages/my-page && npm install && npm run build && cd ../../..
# For extensions: cd ui/extensions/my-ext && npm install && npm run build && cd ../../..

# IMPORTANT: Verify you are in the app root (where manifest.yml lives) before running
# foundry apps/ui commands. The CLI resolves paths relative to cwd, not the manifest location.

# Final deploy (run ONCE, never re-deploy to check status)
foundry apps deploy --no-prompt --change-type Patch --change-log "Complete app"

# Poll deployment status — run immediately, do NOT prepend sleep
foundry apps list-deployments
# If still in progress, wait 5s then poll again:
# sleep 5 && foundry apps list-deployments

# Local UI development (deploy first if UI calls backend capabilities)
foundry ui run
```

**Deploy once, poll with `list-deployments`.** Running `deploy` multiple times creates duplicate deployments and wastes minutes.

```bash
# Release (run ONCE after deploy succeeds)
foundry apps release --change-type Patch --deployment-id <id> --notes "Release notes"
```

**Note:** There is no `list-releases` command. After `release`, check status via the App Manager URL printed in the output, or wait ~30s and proceed to testing.

`foundry ui run` only serves UI locally — backend capabilities (API integrations, functions, collections) resolve from the cloud. Deploy those first.

## Multi-Cloud Deployment

To deploy the same app to multiple clouds (US-1, US-2, US-3, EU-1, etc.):

1. **Strip all IDs** before deploying to a new cloud — IDs are cloud-specific:
   ```bash
   yq -i 'del(.. | select(has("id")).id) | del(.. | select(has("app_id")).app_id)' manifest.yml
   ```
   This DELETES the keys entirely. Setting them to empty/null is NOT the same and will cause errors.

2. **Switch profile** to the target cloud:
   ```bash
   foundry profile activate --name "eu-1-profile"
   ```

3. **Deploy and release** as normal.

4. **Install from App Catalog** — after releasing on a new cloud, the app must be explicitly installed from the Falcon console App Catalog. It does NOT auto-install.

5. **Wait for propagation** — installation may take several minutes before the page URL becomes accessible. A 404 on `/api2/ui-extensions/entities/pages/v1` immediately after install is normal; retry after a few minutes.

**Important:** Back up your manifest before stripping IDs if you want to preserve the original cloud's IDs: `cp manifest.yml manifest.yml.backup`

## Existing App Workflow

When `manifest.yml` already exists, work is primarily editing existing files. Use CLI only for:
- `foundry apps run` / `foundry ui run` — local development
- `foundry apps deploy` / `foundry apps release` — deployment
- `foundry api-integrations create` etc. — adding new capabilities

## Manifest Coordination

**Dependency order:** Collections → Functions → Workflows → UI (each may depend on the previous)

- **MUST NOT edit manifest.yml** unless a deploy fails with "app name already exists" (rename only). The CLI sets `path`, `entrypoint`, scopes, and IDs correctly — manual edits cause double-path errors and wasted deploy cycles.
- **MUST NOT edit vite.config.js** — the React blueprint is turnkey. Do not change `base`, `root`, or `noAttr()`. Just edit React/JS component code and deploy.
- OAuth scopes are auto-managed for CLI-created artifacts — MUST NOT manually add `api-integrations:read`
- Use `npx @redocly/cli lint` for OpenAPI validation (not Python/Ruby YAML parsers)
- Validate early with `foundry apps validate --no-prompt` after adding API integrations and collections — but don't validate right before deploy (deploy runs the same checks plus more)

## Reading Guide

| Task | Reference |
|------|-----------|
| Headless/CI setup, env vars, US-GOV-1 | [references/headless-operation.md](references/headless-operation.md) |
| Superpowers plugin coordination | [references/superpowers-integration.md](references/superpowers-integration.md) |
| Token management, performance targets | [references/performance-optimization.md](references/performance-optimization.md) |
| Counter-rationalizations, red flags | [references/counter-rationalizations.md](references/counter-rationalizations.md) |
| Lifecycle phases, manifest patterns, CLI state, app operations, local e2e runs | [references/advanced-patterns.md](references/advanced-patterns.md) |

## Improving These Skills

If a skill gave incorrect guidance, was missing a pattern, or required extra trial-and-error to get right, the user can ask you to capture the fix at the end of the session:

```
What did you learn from this session that could improve the Foundry skills?
Clone https://github.com/CrowdStrike/foundry-skills.git,
create a branch, update the skills with this knowledge, and
create a PR on GitHub.
```

Steps Claude will handle: create a branch, update the relevant `skills/*/SKILL.md`, and create a PR.

This turns a one-session fix into a permanent improvement for all users.
