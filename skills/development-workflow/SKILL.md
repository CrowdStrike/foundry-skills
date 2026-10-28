---
name: development-workflow
description: Orchestrates the complete Falcon Foundry app lifecycle from requirements through deployment. TRIGGER when user asks to "create a Foundry app", "build a Foundry app", "plan a Foundry app", runs any `foundry apps` CLI command, or discusses Foundry app architecture. DO NOT TRIGGER when user is working on a specific capability (UI, function, workflow, collection) within an existing app — use the appropriate sub-skill instead. This skill OWNS the entire Foundry development flow. Do not delegate Foundry app creation to superpowers:brainstorming or superpowers:writing-plans — those skills do not know about the Foundry CLI.
version: 1.6.0
updated: 2026-10-01
tags: [foundry, lifecycle, cli, deployment]
author: CrowdStrike
license: MIT
compatibility: Claude Code >=1.0
metadata:
  category: orchestration
---

# Foundry Development Workflow

> This skill owns the Foundry development flow. Follow the **App Creation Flow** below from user prompt to running app, scaffold with `foundry apps create` and related CLI commands, delegate capability-specific content to the Foundry sub-skills, and hand-write only what the CLI can't generate (OpenAPI content, workflow logic, UI code).
>
> Don't hand Foundry app creation to superpowers:brainstorming or superpowers:writing-plans. They don't know the Foundry CLI and produce plans that hand-write manifest.yml and boilerplate files. They can supplement this flow (TDD discipline, code review), not replace it.
>
> **CRITICAL: add `--no-prompt` to every command that accepts it** — without it, interactive prompts cause `Error: EOF`. The `create`, `validate`, `deploy`, `release`, and `delete` commands all accept it (`apps delete` also needs `--force-delete`). Three reject it and fail with `unknown flag`: `foundry version`, `apps list`, and `apps list-deployments`. Verify with `foundry <command> --help`. When a command fails, MUST NOT fall back to `mkdir` — fix the command and retry.
>
> **CRITICAL: All `foundry` app commands MUST run from the app root directory** (where `manifest.yml` lives). The CLI resolves manifest paths relative to `os.Getwd()`, not relative to the manifest's location. Running `foundry apps validate`, `foundry apps deploy`, or `foundry ui run` from a subdirectory (e.g., `ui/extensions/my-ext/`) causes doubled paths and misleading "file not found" errors. Commands that work from anywhere: `foundry version`, `foundry profile *`, `foundry apps list`.

This skill coordinates the full Falcon Foundry app lifecycle — from parsing requirements through scaffolding, implementation, and deployment. It delegates capability-specific work to sub-skills that know the platform details.

## Decision Tree

```
What does the user need?

Create a new Foundry app
└── Follow the App Creation Flow below

Upgrade a template-installed app
└── app-upgrades

Add a capability to an existing app
├── API integration       → api-integrations
├── Workflow              → workflows-development
├── UI page/extension     → ui-development
├── Function              → functions-development
├── Collection            → collections-development
├── AI agent / knowledge base → ai-agents-development
└── Falcon API from funcs → functions-falcon-api

Execute / test a deployed function
├── "run my function", "execute function"     → functions-development
├── "check execution status", "exec status"   → functions-development
├── "get function logs", "show logs"          → functions-development
├── "list executions"                         → functions-development
├── "test my function" (function tests.yml)   → functions-development
└── "run tests", "test cases"                 → functions-development

Debug a function failure
├── "debug my function", "why did it fail"    → debugging-workflows
├── "function returning errors"               → debugging-workflows
└── "no logs available"                       → debugging-workflows

Implement a known pattern (pagination, enrichment, ingestion)
└── Search use-cases/*.md for matching pattern → load for context

Debug / troubleshoot      → debugging-workflows
Security review           → security-patterns
E2E testing / Playwright  → e2e-testing

Standalone Fusion workflow (no app — trigger + existing actions only)
└── fusion-redirect (declines and points to the Falcon Fusion plugin)
```

### Routing When Sub-Skills Are Not Registered

Sub-skills live beside this one as `../<name>/SKILL.md`. On a single-entry-point install only this skill is discoverable, so capability-level requests land here — that is intended, not a mis-route. Read the sub-skill file from disk before writing any capability content, then:

- **`manifest.yml` already present** — skip Steps 1-2 and Step 4. Run the Step 3 prerequisite check, add the capability with its command from **Capability Create Commands** in [references/advanced-patterns.md](references/advanced-patterns.md), and follow Manifest Coordination.
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
| "AI agent", "Charlotte agent", "agentic" | AI Agent | `foundry agents create` |
| "knowledge base", "give the agent docs" | Knowledge Base | `foundry knowledge-bases create` |
| "run function", "execute", "test handler" | Function Execution | `foundry functions exec` |
| "get logs", "show execution logs" | Log Retrieval | `foundry functions logs` |
| "check status", "execution result" | Execution Status | `foundry functions exec status` |
| "test function", "run tests", "test cases" | Function Testing | `foundry functions test` |
| "debug function", "why did it fail" | Function Debugging | → debugging-workflows skill |

> **⚠️ "Summarize/list alerts, detections, or incidents" (a population the workflow doesn't already have) implies a source-of-truth fetch.** A request like "a workflow that emails a summary of high-severity alerts" needs the *set* of alerts, which is not reliably in NG-SIEM (Event Query can silently return nothing — repo contents are connector-dependent). Fetch it from the source of truth: a native platform action (e.g. Cases → Search Cases) first, or a FalconPy `Alerts`/`Detects` function when none fits — so the app needs BOTH that capability (plan the `alerts:read` scope) AND a workflow to schedule it and send email. **Exception:** *enriching* a detection the workflow was already triggered on (query by its ID) stays an Event Query and needs no function. See the `functions-falcon-api` skill and the `workflows-development` skill's `references/event-query-vs-api.md`.

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
foundry profile list     # First line shows the active profile
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

`foundry apps create` always makes a **subdirectory named after the app** (spaces included). When converting an existing repo, run `create` beside it and move the freshly generated `manifest.yml` to the repo root rather than leaving a nested app directory.

### Step 5: Add Capabilities (CLI Commands)

Run in dependency order (**API integrations → collections → validate → functions → knowledge bases → agents → workflows → UI pages → extensions**). Write spec/schema files to `/tmp/` — the CLI copies them into the project and updates `manifest.yml` with generated IDs. The full annotated command sequence for every capability is in [references/advanced-patterns.md](references/advanced-patterns.md) → **Capability Create Commands**.

**Fail fast:** Validate right after API integrations and collections — `foundry apps validate --no-prompt` is a seconds-long dry-run of deploy validation (specs + schemas; NOT workflow semantics or app-name uniqueness, which only deploy checks). If it fails, STOP and fix the spec/schema before building UI on a broken backend; let `adapt_spec_for_foundry.py` fix known spec issues and tell the user what it missed. Don't validate right before deploy — deploy runs the same checks plus more.

### Step 6: Write Domain-Specific Content

The CLI scaffolds structure but cannot generate app logic. Delegate to sub-skills:

- **OpenAPI spec** → api-integrations
- **Workflow YAML** → workflows-development
- **UI components** → ui-development
- **Function handlers** → functions-development
- **Collection schemas** → collections-development
- **AI agents / knowledge bases** → ai-agents-development

> **Load the relevant sub-skill before writing domain-specific code.** Foundry formats and SDK calls differ from what general knowledge suggests — writing without the sub-skill loaded is the top cause of invented formats (wrong workflow YAML, raw HTTP instead of FalconPy, agents created before their KBs). The per-capability "what goes wrong without it" table is in [references/advanced-patterns.md](references/advanced-patterns.md) → **Sub-Skill Loading**.

### Step 7: Final Build and Deploy

```bash
# Build UI (required before deploy) — MUST cd back to app root afterward
cd ui/pages/my-page && npm install && npm run build && cd ../../..
# For extensions: cd ui/extensions/my-ext && npm install && npm run build && cd ../../..

# IMPORTANT: Verify you are in the app root (where manifest.yml lives) before running
# foundry apps/ui commands. The CLI resolves paths relative to cwd, not the manifest location.

# Deploy never builds a UI: it ships dist/ as is. Check new dist/assets files are listed:
foundry apps deploy --diff-only --no-prompt

# Final deploy (run ONCE, never re-deploy to check status)
foundry apps deploy --no-prompt --change-type Patch --change-log "Complete app"

# Poll deployment status — run immediately, do NOT prepend sleep
foundry apps list-deployments
# If still in progress, wait 5s then poll again:
# sleep 5 && foundry apps list-deployments

# Local UI development (deploy first if UI calls backend capabilities)
foundry ui run
```

**Deploy once, poll `list-deployments`** for the deployment version `deploy` printed (release numbers differ); re-deploying duplicates it. A `Failed` deployment shows no reason in the CLI — read it in the console (**App manager > the app > "Show errors (N)"**). While a deploy runs, `foundry apps validate` fails with `deployment is currently in progress` — wait, it is not a manifest error.

```bash
# Release (run ONCE after deploy succeeds)
foundry apps release --change-type Patch --deployment-id <id> --notes "Release notes" --no-prompt
```

There is no `list-releases` command — check status via the App Manager URL printed in the output. `foundry ui run` serves UI locally only; backend capabilities resolve from the cloud, so deploy those first.

> **Deploy & release operational depth** — `--re-deploy` retries the latest failed deployment (never to test an edit); the post-update console-cache hard-refresh (Cmd/Ctrl+Shift+R, don't re-deploy to "fix" a stale view); patch-release credential entry (**Modify settings** vs a `--change-type Major` **Accept update**); and the version numbers (catalog vs deployment vs any version shown in the UI) — all in [references/advanced-patterns.md](references/advanced-patterns.md) → **Deploy & Release**.

## Multi-Cloud Deployment

To deploy the same app to a second cloud (US-1/US-2/US-3/EU-1): **strip all IDs** (`yq -i 'del(.. | select(has("id")).id) | del(.. | select(has("app_id")).app_id)' manifest.yml` — delete, don't null), `foundry profile activate` the target cloud, deploy + release, then **explicitly install from the App Catalog** (no auto-install; allow a few minutes for propagation). Full steps + the manifest-backup note in [references/advanced-patterns.md](references/advanced-patterns.md) → **Multi-Cloud Deployment**.

## Existing App Workflow

With an existing `manifest.yml`, edit files; use the CLI only for:
- `foundry apps run` / `foundry ui run` — local development
- `foundry apps deploy` / `foundry apps release` — deployment
- `foundry api-integrations create` etc. — adding capabilities

## Manifest Coordination

**Dependency order:** the Step 5 order (each may depend on the previous)

- **MUST NOT edit manifest.yml** unless a deploy fails with "app name already exists" on a true name collision (rename only); if the deploy-written IDs were lost, restore them instead (see below). The CLI sets `path`, `entrypoint`, scopes, and IDs correctly — manual edits cause double-path errors and wasted deploy cycles.
- **The first (cold) deploy writes the provisioned `app_id` + page/function/workflow/agent IDs back into `manifest.yml` — COMMIT those.** They identify your app on that cloud; without them the next deploy fails with `an app with the provided name already exists`. This is the OPPOSITE of the e2e-sample `git checkout manifest.yml` step (see `references/advanced-patterns.md` → Testing an Existing App Locally), which is for throwaway CI runs of the public `foundry-sample-*` repos that commit blanked IDs to install into any CID. For an app you own and operate, keep the written-back IDs.
- **Narrow exceptions:** `ai.agents[].model` and `.tools` (see `ai-agents-development`), `auth.scopes` names `scopes add` rejects (see `security-patterns`), renaming a deployed KB (see `knowledge-bases.md`), and RBAC `permissions:` keys. (Agent `exposure` *does* have `--expose-*` flags; set it at create time.)
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
| Common wrong turns (CLI vs hand-written files) | [references/counter-rationalizations.md](references/counter-rationalizations.md) |
| Lifecycle phases, manifest patterns, CLI state, app operations, local e2e runs | [references/advanced-patterns.md](references/advanced-patterns.md) |
| Capability create commands, sub-skill loading, deploy & release depth, multi-cloud | [references/advanced-patterns.md](references/advanced-patterns.md) |

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
