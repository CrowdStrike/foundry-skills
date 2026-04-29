---
name: development-workflow
description: Orchestrates the complete Falcon Foundry app lifecycle from requirements through deployment. TRIGGER when user asks to "create a Foundry app", "build a Foundry app", "plan a Foundry app", runs any `foundry apps` CLI command, or discusses Foundry app architecture. DO NOT TRIGGER when user is working on a specific capability (UI, function, workflow, collection) within an existing app — use the appropriate sub-skill instead. This skill OWNS the entire Foundry development flow. Do not delegate Foundry app creation to superpowers:brainstorming or superpowers:writing-plans — those skills do not know about the Foundry CLI.
version: 1.0.0
updated: 2026-04-29
metadata:
  author: CrowdStrike
  category: orchestration
  tags: [foundry, lifecycle, cli, deployment]
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
> **CRITICAL: `--no-prompt` is supported by nearly all commands.** Always add `--no-prompt` to prevent interactive prompts that cause `Error: EOF` in non-interactive environments. Supported commands include: `apps create`, `apps validate`, `apps deploy`, `apps release`, `apps delete` (also needs `--force-delete`, but may still prompt interactively in some CLI versions — delete via Falcon App Manager UI if it hangs), `functions create`, `collections create`, `ui pages create`, `ui extensions create`, `rtr-scripts create`, `profile create`, `workflows create`, and `api-integrations create`. When unsure, run `foundry <command> --help` to check. When a CLI command fails, MUST NOT fall back to `mkdir` — fix the command and retry.
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
```

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

### Step 1b: Check for Known Patterns

Before scaffolding, check if the user's request matches a known use case. Glob `use-cases/*.md` and scan the `description` field in each file's frontmatter. If a match is found, read the use case file for implementation context (architecture, capability order, gotchas) before proceeding.

Use cases cover common scenarios like API pagination, detection enrichment, lookup table creation, LogScale data ingestion, SOAR custom actions, and more. See `use-cases/README.md` for the full catalog.

### Step 2: Confirm App Name and Capabilities

**Always confirm the app name with the user via AskUserQuestion before creating anything.** Derive a reasonable default from the user's request (e.g., "okta-integration" for an Okta API integration), then present it as the recommended option with 1-2 alternatives. Include a brief description of what will be created.

**Page vs Extension disambiguation:** When the user mentions "UI" without specifying "page" or "extension", ask which they want via AskUserQuestion. Offer two options: "Page" (standalone full-page view — dashboards, lists, management UIs) and "Extension" (sidebar widget embedded in detection/host/incident pages). Default to Page when running non-interactively (e.g., `claude -p` or test automation) since pages are the more common case.

For other decisions, prefer reasonable defaults: use React for UI, download public OpenAPI specs from vendor GitHub repos. Only ask additional clarifying questions when the prompt is genuinely ambiguous and a wrong guess would produce an unusable app.

### Step 3: CLI Prerequisite Check

```bash
foundry version          # Verify CLI installed
foundry profile active   # Verify authentication
```

If either fails, see [references/headless-operation.md](references/headless-operation.md) for setup options (env vars, non-interactive profile creation).

### Step 4: Scaffold the App

**Prerequisite:** User must have confirmed the app name in Step 2. Do not run this without confirmation.

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

# 5. Workflows
foundry workflows create --name "My Workflow" --spec /tmp/My_workflow.yml --no-prompt

# 6. UI pages (standalone full-page views)
foundry ui pages create --name "my-page" --description "desc" --from-template React --homepage --no-prompt
foundry ui navigation add --name "My Page" --path / --ref pages.my-page

# 6b. UI extensions (sidebar widgets embedded in detection/host/incident pages)
# Run `foundry ui extensions list-sockets` to see available socket IDs
foundry ui extensions create --name "my-ext" --description "desc" --from-template React --sockets "activity.detections.details" --no-prompt
```

**Fail fast:** Validate right after API integrations and collections. `foundry apps validate` is a dry-run of deploy validation — it checks specs and schemas in seconds without building artifacts. It does NOT check workflow semantics or app name uniqueness (those are only checked on deploy). Don't validate right before deploy — deploy runs the same validation plus more. Don't manually fix spec issues — improve `adapt-spec-for-foundry.py` instead.

### Step 6: Write Domain-Specific Content

The CLI scaffolds structure but cannot generate app logic. Delegate to sub-skills:

- **OpenAPI spec** → api-integrations
- **Workflow YAML** → workflows-development
- **UI components** → ui-development
- **Function handlers** → functions-development
- **Collection schemas** → collections-development

### Step 7: Final Build and Deploy

```bash
# Build UI (required before deploy)
cd ui/pages/my-page && npm install && npm run build && cd ../../..

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

To deploy the same app to multiple clouds (US-1, US-2, EU-1, etc.):

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

## Testing an Existing App Locally

When running e2e tests against an existing app:

1. **Update manifest name** if needed (to match `APP_NAME` in `e2e/.env`)
2. **Deploy and release:**
   ```bash
   foundry apps deploy --change-type patch --change-log "e2e testing" --no-prompt
   # Poll until successful
   foundry apps list-deployments
   # Release
   foundry apps release --deployment-id <id> --change-type patch --notes "e2e testing" --no-prompt
   ```
3. **Run tests:** `cd e2e && npx playwright test`
4. **Revert manifest:** `git checkout manifest.yml` (deploy writes IDs into the manifest)

### App Name Alignment

The manifest `name` and the e2e test `APP_NAME` environment variable must match for local test runs. CI pipelines typically rewrite the manifest name automatically (e.g., `${REPO}-ci-${PIPELINE_ID}`), so this only affects local development.

Two approaches:
- **Update manifest to match .env** (preferred): Use the repo name (e.g., `foundry-sample-logscale`) to avoid spaces and simplify artifact lookup. Remember to `git checkout manifest.yml` after deploy to revert ID changes.
- **Update .env to match manifest**: Works but names with spaces can cause issues in some tooling.

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
| Lifecycle phases, manifest patterns, CLI state, app operations | [references/advanced-patterns.md](references/advanced-patterns.md) |

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
