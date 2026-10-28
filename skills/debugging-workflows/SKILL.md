---
name: debugging-workflows
description: Systematic troubleshooting for Falcon Foundry CLI errors, manifest validation failures, deploy failures, artifact runtime errors, and development server issues. TRIGGER when user encounters CLI errors, `foundry ui run` not working, deploy failures, authentication issues, function execution failures, "debug my function", "why did this fail", or any unexpected behavior during Foundry app development. Also trigger for headless/CI environment setup failures.
version: 1.6.0
updated: 2026-10-01
tags: [foundry, debugging, cli, deployment, artifacts, functions, logs, execution]
author: CrowdStrike
license: MIT
compatibility: Claude Code >=1.0
metadata:
  category: troubleshooting
---

# Foundry Debugging Workflows

Systematic procedures for diagnosing and resolving common CrowdStrike Falcon Foundry development issues.

> **Part of a suite.** If `development-workflow` has not already run, and this is a new app or its first capability, load the `development-workflow` skill first — it owns the CLI prerequisite check, scaffolding order, and manifest coordination.

## Quick Diagnosis

```
What's happening?

CLI command hangs
├── In headless/CI environment → Missing --no-prompt or required flags (see Headless section)
└── In interactive terminal   → Check network/auth with foundry profile list

Deploy fails
├── Validation error → Check manifest YAML syntax, then deploy again
├── "Unknown error"  → Duplicate workflow name across apps in tenant
├── "no deployable artifacts found" → Diff is only manifest/logo/metadata; deploy needs an artifact change (function/collection/UI/agent). No --force; bundle it or put the logo in the first deploy
├── "Failed" with no reason in the CLI → Falcon console: App manager > app > "Show errors (N)" (per capability)
├── validate says "deployment is currently in progress" → A deploy is still running; poll list-deployments, then retry
├── validate or deploy says "no changes detected" → No packaged file changed since the last deploy (still true right after a failed one). Change a file the deploy packages, not one in ignored:
└── Silent failure   → Tenant may be missing required module (SKU) for requested scopes

foundry ui run fails
├── On new app              → Deploy backend capabilities first (API integrations, functions, collections resolve from cloud)
├── Permission errors       → Check manifest OAuth scopes, restart server, verify auth
└── Blank page / CORS error → noAttr() or base path removed from vite.config.js (see ui-development)

Released change doesn't show
└── UI fix missing from the app → Grep the built dist; rebuild if it's absent (see Confirm a Fix Is in the Built Bundle)

Function execution fails
├── Status 500 + "Server Error"  → Check function logs: foundry functions logs <exec_id>
├── Status 202 + no result       → Async execution: foundry functions exec status <exec_id>
├── 403 "app is not installed"   → Deployed but not released + installed from App Catalog; FalconPy calls need an installed app
├── 401 on every FalconPy call, scopes correct → Client constructed at module scope; move it inside the handler
├── "authorization failed"       → Confirm the CLI profile's API client has Apps read + write; if it does, it's a platform permission problem: report the trace ID, don't edit scopes
├── "artifact is not deployed"   → Deploy first: foundry apps deploy --no-prompt
├── 404 "no app artifacts found of type FAAS_FUNCTION" right after a deploy → Pin the deployment: add --version <the version deploy printed>, e.g. --version v0.0.4-pre-release
├── No logs available            → Wait 5-10 min, then: foundry functions logs <exec_id> --refresh
│   └── Still "Log query failed"   → Temporarily return the diagnostic values in the handler's response body, deploy a pre-release (don't release it), exec once, then remove them and deploy again so the latest deployment matches the code
├── UI page: repeated 404s on /api2/faas-gateway/entities/execution/v1 in the browser console → foundry-js polling for the cloud-function result before it is ready; non-fatal if the data still loads, not a failure
└── Unexpected response          → Read logs + source, correlate timestamps against handler code

Auth fails
├── 401/403 from API   → Check OAuth scopes in manifest
├── 403 "access denied, scope not permitted" for every input → The identity making the call lacks the scope (see Which Identity Makes the Call)
├── 404 or 400 after adding scopes, other than "no app artifacts found" → An input error (name, ID, or search domain), not a permission problem. Read the error message
├── Login hangs        → Headless environment, no browser — use env vars or profile create --no-prompt
└── Works locally, fails in CI → Set FOUNDRY_API_CLIENT_ID env vars in CI config
```

### Which Identity Makes the Call

Three identities can look alike, and each has its own scopes:

| Identity | Used by | Scopes come from |
|----------|---------|------------------|
| The CLI profile (`foundry profile list` shows it) | `deploy`, `release`, and starting an `exec` or `test` run | The API client in the profile |
| Any other API client you hold | FalconPy scripts and MCP servers run on your machine | That API client |
| The installed app | Deployed functions, including their FalconPy calls under `exec` and `test` | `auth.scopes` in `manifest.yml`, accepted when the app is installed or updated |

Granting a scope to an API client doesn't change what a function can do, even under `exec`. Add the scope to `auth.scopes`, deploy, release, and have the app's users accept the update. Until the update is accepted in the App Catalog, the call keeps answering `403`. The CLI can't list a client's scopes, so test a scope by making the call. Don't test with Hosts `query_devices_by_filter`, which has answered `200` with no declared scope.

One exception to the 403 rule above: the Falcon Next-Gen SIEM queryjobs API also answers 403 for a real repository it won't search, such as `fusion`, while `search-all` works (see the `search-all` gotcha in `functions-falcon-api`).

## Local Testing

### Function Testing

```bash
# Via Foundry CLI with Docker (random ports, closest to production)
foundry functions run --name my-function

# Direct Go execution (port 8081, no Docker)
cd functions/my-function && go run main.go

# Direct Python execution (port 8081, no Docker)
cd functions/my-function && python3 main.py

# Both FDKs route on "url" and "method" inside a JSON envelope posted to the root URL,
# not on the HTTP path, so wrap the payload in "body"
curl -X POST http://localhost:8081 -H 'Content-Type: application/json' \
  -d '{"body":{"key":"value"},"method":"POST","url":"/api/process"}'

# With configuration file (local only)
CS_FN_CONFIG_PATH=./config.json python3 main.py
```

### Function Execution & Log Retrieval (Deployed Functions)

> **Requires Foundry CLI 2.1.0+.** These commands do not exist in CLI 2.0.x.

For testing against the deployed Lambda (not local Docker), use the execution commands:

```bash
# Execute a deployed function handler
foundry functions exec --handler my_handler '{"key": "value"}' --no-prompt

# Execute and wait for logs
foundry functions exec --handler my_handler --logs '{"payload": "data"}' --no-prompt

# Check status of an async (202) execution
foundry functions exec status <exec_id>

# Retrieve logs for a past execution
foundry functions logs <exec_id>

# List recent executions to find one to debug
foundry functions exec list --function my-fn --no-prompt
```

### Function Runtime Debugging

When a deployed function returns unexpected results or errors, work the exec → logs → correlate-to-source → fix → re-verify loop, and match the symptom in the runtime-failure table (ImportError, module-scope FalconPy 401, scope 403, async 202, empty logs, …). Full step-by-step + the table: [references/function-runtime-debugging.md](references/function-runtime-debugging.md).

### RTR Script Testing

RTR scripts can only be tested via the CLI (not the Falcon console):

```bash
foundry rtr-scripts run --script-name my-script --hostname <hostname> --no-prompt
# or target by --device-id <aid>; pass script parameters with -p/--params
```

Platforms: Windows (`script.ps1`), Linux (`script.sh`), macOS (`script.zsh`). Script size limit ~40KB. Deletion requires Falcon Administrator role in Falcon console UI.

### Workflow Mock Testing

```bash
foundry workflows triggers view --name "<trigger name>" --mock --no-prompt
foundry workflows actions view --name "<action name>" --mock --no-prompt
foundry workflows executions validate --definition my-workflow --mocks mymocks.json --no-prompt
foundry workflows executions start --definition my-workflow --mocks mymocks.json --no-prompt
foundry workflows executions view <execution_id> --no-prompt
```

### Deployment Diagnostics

Deployment is two-phase: validation (manifest + schemas) then artifact build. Use `foundry apps validate --no-prompt` to dry-run validation after adding API integrations or collections (catches spec/schema issues in seconds). Don't validate right before deploy — deploy re-runs the same validation plus workflow semantics and name-uniqueness checks.

### Confirm a Fix Is in the Built Bundle

When a released UI fix doesn't show, don't diagnose it from the running app alone. Grep the built bundle, the directory the page's or extension's `path` names in `manifest.yml` (`src/dist` or `dist`; samples use both), for the change (a literal string, new token, or renamed symbol), or run `foundry apps deploy --diff-only --no-prompt` before deploying and check that new `dist/assets` files are listed. If it isn't there, the deploy shipped the previous build: deploy uploads `dist/` as it is and never builds, so run `npm run build` in that UI directory, then deploy and release again (see **Deploy never builds a UI** in `development-workflow`'s `references/advanced-patterns.md`). If it is there, hard-refresh the console before suspecting the release. This applies to UI only; functions have no `dist`.

## CLI Troubleshooting

### Step 1: Environment Validation

```bash
foundry version         # Check CLI version
foundry profile list    # Check available profiles
foundry profile list  # The first line shows the active profile
```

### Step 2: Authentication

```bash
foundry login                                    # Re-authenticate via browser (interactive)
foundry profile delete --name <name> --no-prompt # Reset corrupted profile
foundry login                                    # Re-authenticate
```

### `connection issue` on Tenant Commands (Sandboxed Agents)

**Check the token cache write first — it is the usual cause and it is not a network problem.**

The CLI keeps its short-lived access token in `~/.config/foundry/token.json`, separate from the credentials in `configuration.yml`. The token lasts about 30 minutes, and the next tenant command after it expires writes a fresh one back to that file. That write is expected and is the safer design: a rotating 30-minute token beats a long-lived one, and keeping it out of the workspace means it never gets committed.

Assistants that confine writes to the workspace are denied that write, and the CLI reports only `connection issue` — the symptom, not the cause. Since a session usually begins with an already-expired token, this appears within the first few seconds, not after half an hour.

Fix: **request write access to `~/.config/foundry/` and retry the same command.** Say why — the CLI is refreshing its own token cache — and treat it as a routine low-risk escalation rather than a blocker. Do not ask the user to relaunch their assistant, and do not rewrite the profile, redirect the config path into the workspace, or copy credentials; those hide working credentials instead of granting the one needed write.

If the write succeeds and tenant commands still fail, then treat it as network: ask the user to run the command in their own terminal, and if it works there, request unsandboxed network access and retry once.

### Manifest Validation

Use `foundry apps validate --no-prompt` to validate the manifest and schemas without deploying. For OpenAPI specs, use `npx @redocly/cli lint` to validate structure locally.

If deploy fails with validation errors:
1. Check the error message — validation errors appear first
2. Comment out capabilities one by one to isolate the issue
3. Fix and re-validate incrementally

## Headless / Non-Interactive Environments

This is the most common failure mode when Foundry CLI is driven by agents (Claude Code) or CI/CD pipelines. Most commands default to interactive mode, which blocks indefinitely.

### `foundry login` Hangs or Fails

`foundry login` opens a browser for OAuth. In headless environments, use one of these alternatives:

**Option 1: Environment variables** (no login needed):
```bash
export FOUNDRY_API_CLIENT_ID="<client-id>"
export FOUNDRY_API_CLIENT_SECRET="<client-secret>"
export FOUNDRY_CID="<customer-id>"
export FOUNDRY_CLOUD_REGION="us-1"
```

**Option 2: Non-interactive profile creation**:
```bash
foundry profile create \
  --name "ci-profile" \
  --api-client-id "<id>" \
  --api-client-secret "<secret>" \
  --cid "<cid>" \
  --cloud-region "us-1" \
  --no-prompt
foundry profile activate --name "ci-profile"
```

**Option 3: Pre-populated config file** at `~/.config/foundry/configuration.yml`:
```yaml
profiles:
- name: ci-profile
  cloud_region: us-1
  credentials:
    cid: <customer-id>
    api_client_id: <client-id>
    api_client_secret: <client-secret>
active_profile: ci-profile
```

### Command Hangs Waiting for Input

Add `--no-prompt` to prevent interactive prompts. Nearly all commands support it: `apps create`, `apps validate`, `apps deploy`, `apps release`, `apps delete` (also needs `--force-delete`), `functions create`, `collections create`, `ui pages create`, `ui extensions create`, `rtr-scripts create`, `profile create`, `profile delete`, `workflows create`, and `api-integrations create`. Provide all required flags explicitly — run `foundry <command> --help` to identify them.

### Auth Works Locally but Fails in CI

The CI environment has no `~/.config/foundry/configuration.yml`. Set environment variables in CI pipeline configuration — they override local config.

## Common Issue Patterns

| Symptom | Likely Cause | First Action |
|---------|--------------|--------------|
| `foundry login` hangs | Headless environment | Use env vars or `profile create --no-prompt` |
| Any command hangs | Missing `--no-prompt` or required flags | Add flags, run `--help` |
| Deploy hangs indefinitely | Manifest validation issue | Check YAML syntax, deploy again |
| `foundry ui run` fails on new app | Backend not deployed | Run `foundry apps deploy` first |
| API calls return 403 | Insufficient OAuth scopes | Review manifest oauth section |
| Deploy fails silently | Tenant missing required module (SKU) | Verify tenant has Falcon module for scopes |
| Deployment `Failed`, CLI gives no reason | Reasons are console-only | App manager > app > "Show errors (N)" |
| `deployment is currently in progress` from `validate` | A deploy is still running | Poll `foundry apps list-deployments` until it settles, then retry |
| Local server won't start | Port conflicts | Free the port by stopping the process holding it (`lsof -i :<port>`); `ui run` and `functions run` have no port flag |
| Auth works locally, fails in CI | No config file in CI | Set `FOUNDRY_API_CLIENT_ID` env vars |
| `connection issue` in a sandboxed agent | Denied write to the CLI's token cache | Grant write to `~/.config/foundry/`; the token refresh is expected |
| Tenant command works for user, not agent | Agent network sandbox | Request elevation, then retry once |
| Page 404 after deploy/release | App not installed from App Catalog | Install from catalog, wait for propagation |
| Page 404 on new cloud only | Cloud-specific IDs in manifest | Strip IDs with yq before deploying to new cloud |
| Blank page, no CORS errors | Vite `root` changed from `src` | Restore `root: 'src'` in vite.config.js |
| Blank page with CORS errors | `noAttr()` removed from vite.config.js | Restore the `noAttr()` plugin in vite.config.js |
| Blank page, no errors in console | `falcon.connect()` not awaited | The platform iframe stays blank until the postMessage handshake completes — add `await falcon.connect()` before any rendering |
| Data not appearing after writes | Schema mismatch or missing error check | Verify field names/enums match schema exactly; check `result?.errors?.length` after writes |
| Dialog white background in dark mode | Older falcon-shoelace or a custom panel (0.4.0 dialogs follow the theme) | Set `--sl-panel-background-color: var(--ground-floor)` on the element |
| App install fails with no detail | Workflow CEL expression error | Test API integration in console, then inspect workflow editor for errors |
| Releases stuck "In progress", never finish | A release whose install-time update failed (often a workflow data pill error deploy didn't catch), with later releases stalled behind it | Stop retrying; open a CrowdStrike support ticket (app_id + deployment id + CID + region + time); cold-deploy a fresh app_id under a new name to keep shipping |
| Console errors `deserializeSitemap`/`loadSitemapFromLegacy` + `/api2/uilogging 400` | Falcon console shell (`maverick.js`), not your app | Ignore; non-fatal (the console falls back to its default navigation). Nothing in the app causes or fixes it |

## Debugging App Install Failures

When an app fails to install with no useful error, isolate by component in the console: test the API integration directly first, rule out static UI files, then open the workflow in Falcon Fusion SOAR — its editor surfaces CEL/variable errors the install API doesn't. Worked example + steps: [references/install-and-visual-debugging.md](references/install-and-visual-debugging.md).

## Visual Debugging with Screenshots

Claude Code reads images directly, so a screenshot is often the fastest way to diagnose a blank page, error modal, or disabled button — pasted in by the user, via Playwright MCP, or from a test's `test-results/` artifacts. Details: [references/install-and-visual-debugging.md](references/install-and-visual-debugging.md).

## Recovery Strategies

### Profile Corruption
1. Delete corrupted profile: `foundry profile delete --name <name> --no-prompt`
2. Re-authenticate with `foundry login`
3. Validate with test deployment

### Development Server
1. Kill existing processes: `pkill -f "foundry ui"`
2. Clear node_modules and reinstall
3. Restart with clean environment

### Manifest Issues
Don't restore `manifest.yml` from git (`git checkout manifest.yml`) after a deploy. The deploy writes `app_id` and artifact IDs back into the file, and discarding them breaks the link to the deployed app: `exec`/`test` fail with `app_id not found in manifest`, and the next deploy fails with `an app with the provided name already exists`. In testing, putting back only `app_id` wasn't enough (`exec` then reported `artifact is not deployed` and later deploys failed); deleting the app (`foundry apps delete --force-delete --no-prompt`) and deploying fresh worked. Commit or discard the deploy-written IDs deliberately instead.

1. Backup current `manifest.yml`
2. Start with minimal working manifest
3. Incrementally add capabilities back, deploying after each addition

### Jammed Release Pipeline

One release whose install-time update fails can jam the pipeline: it stays "In progress", and every later release stalls behind it, even after the cause is fixed. A common trigger is a workflow error deploy doesn't catch, such as `property "input" contains unknown variable "<action>.response"`; a Minor or Patch release updates installed apps automatically, that update fails, and the release never finishes. Before releasing a changed workflow, open it in the Falcon Fusion SOAR editor (or App manager **Show errors**) and fix any reported errors. The queue cannot be cleared from the CLI — it needs a CrowdStrike support ticket (force-uninstall / clear the release queue). Don't retry releases blindly once one is stuck. Practical escape to keep shipping meanwhile: deploy it as a new app. Strip the provisioned IDs with the `yq` command in `development-workflow` → Multi-Cloud Deployment and give the app a new `name` (the stuck app still holds the old one, so reusing it fails with `an app with the provided name already exists`). A new app has to be installed again, its install settings entered again, and its collections start empty, so tell the user before you do it. For the support ticket, give them app_id + deployment id + CID + region + approximate time. The CLI emits no trace ID even with `--verbose` — pull `meta.trace_id` from the console `/api2/...` response in the browser DevTools Network tab.

## Pre-Escalation Checklist

Before seeking external help:

- [ ] Verified CLI version with `foundry version`
- [ ] Checked the active profile with `foundry profile list`
- [ ] Validated OpenAPI specs with `npx @redocly/cli lint` (if applicable)
- [ ] Tested with minimal configuration
- [ ] Reviewed CLI error messages
- [ ] Attempted recovery procedures
- [ ] Documented reproduction steps
