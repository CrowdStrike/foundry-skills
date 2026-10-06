---
name: debugging-workflows
description: Systematic troubleshooting for Falcon Foundry CLI errors, manifest validation failures, deploy failures, artifact runtime errors, and development server issues. TRIGGER when user encounters CLI errors, `foundry ui run` not working, deploy failures, authentication issues, function execution failures, "debug my function", "why did my deployment fail", "why did this fail", "what went wrong with my deploy", or any unexpected behavior during Foundry app development. Also trigger for app lifecycle log retrieval (deploy, release, install and publish records) and headless/CI environment setup failures.
version: 1.6.0
updated: 2026-10-01
tags: [foundry, debugging, cli, deployment, artifacts, functions, logs, execution, app-lifecycle-logs]
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
└── In interactive terminal   → Check network/auth with foundry profile active

Deploy fails
├── Reported as failed → Read the platform's own record of why:
│                        foundry apps logs --deployment-id <id> --no-prompt
├── Validation error → Check manifest YAML syntax, then deploy again
├── "Unknown error"  → Duplicate workflow name across apps in tenant
├── "no deployable artifacts found" → Diff is only manifest/logo/metadata; deploy needs an artifact change (function/collection/UI/agent). No --force; bundle it or put the logo in the first deploy
├── "Failed" with no reason in the CLI → Falcon console: App manager > app > "Show errors (N)" (per capability)
├── validate says "deployment is currently in progress" → A deploy is still running; poll list-deployments, then retry
└── Silent failure   → Tenant may be missing required module (SKU) for requested scopes

Release, install, publish or delete fails
└── Read the app's lifecycle records: foundry apps logs --level error --no-prompt

foundry ui run fails
├── On new app              → Deploy backend capabilities first (API integrations, functions, collections resolve from cloud)
├── Permission errors       → Check manifest OAuth scopes, restart server, verify auth
└── Blank page / CORS error → noAttr() or base path removed from vite.config.js (see ui-development)

Function execution fails
├── Status 500 + "Server Error"  → Check function logs: foundry functions logs <exec_id>
├── Status 202 + no result       → Async execution: foundry functions exec status <exec_id>
├── 403 "app is not installed"   → Deployed but not released + installed from App Catalog; FalconPy calls need an installed app
├── 401 on every FalconPy call, scopes correct → Client constructed at module scope; move it inside the handler
├── "authorization failed"       → Missing custom-apps:write scope on API client
├── "artifact is not deployed"   → Deploy first: foundry apps deploy --no-prompt
├── No logs available            → Wait ~5 min, then: foundry functions logs <exec_id> --refresh
│   └── Still "Log query failed"   → Temporarily return the diagnostic values in the handler's response body, redeploy, exec once, then remove them
├── UI page: repeated 404s on /api2/faas-gateway/entities/execution/v1 in the browser console → foundry-js polling for the cloud-function result before it is ready; non-fatal if the data still loads, not a failure
└── Unexpected response          → Read logs + source, correlate timestamps against handler code

Auth fails
├── 401/403 from API   → Check OAuth scopes in manifest
├── Login hangs        → Headless environment, no browser — use env vars or profile create --no-prompt
└── Works locally, fails in CI → Set FOUNDRY_API_CLIENT_ID env vars in CI config
```

## App Lifecycle Logs (`foundry apps logs`)

The platform keeps its own record of every lifecycle operation it performed on an app — create, deploy, release, publish, install, update, uninstall, delete, import — including why one failed. Read these first when a lifecycle operation fails: the CLI reports only the final status, while these records name the failing artifact and a stable reason code.

> **Requires Foundry CLI 2.1.2+.** `foundry apps logs` does not exist in earlier CLIs — including 2.1.0 and 2.1.1, which satisfy this plugin's own minimum, so the session-start check stays quiet and the command still fails. Confirm with `foundry apps logs --help` before relying on it, and offer to upgrade: `brew upgrade crowdstrike/foundry-cli/foundry`. Until then the fallback is `foundry apps list-deployments` plus App manager's "Show errors" in the Falcon console.

This is a different source from `foundry functions logs <exec_id>`, which returns one function execution's own output and lags ~5 minutes behind. `apps logs` never shows a handler's `print()`, and `functions logs` never explains a failed deploy.

### Debugging a Failed Deployment

```bash
foundry apps list-deployments                                  # get the deployment ID
foundry apps logs --deployment-id <deployment_id> --no-prompt  # read that deployment's records
```

**Always scope with `--deployment-id`.** Unscoped output covers every operation on the app in the window, including earlier successful deploys — the fastest way to diagnose the wrong failure.

**Diagnose from the first error, not the last.** Records print oldest first. The final line is usually the generic `DEPLOY_FAILED` summary; the *first* `ERROR` names the artifact that actually broke, by its manifest name. Fix that artifact, redeploy, then re-read the new deployment's records to confirm the narrative changed.

**Check `fix=` before auditing anything.** Each failure record says who can act on it. `fix=customer` means the app is at fault — and wherever a `fields=` part is present, it names the part of the app's own file that was rejected, so go straight there. `fix=crowdstrike` means the platform has attributed the failure to itself: retry, then escalate with the `trace=` value. Do not spend a cycle changing app code on a `fix=crowdstrike` record. `fix=unclear` means the failure was not attributed, so look for a more specific record before concluding anything.

**Act on the indented `↳` steps.** They are the platform's own remediation for that reason, joined onto the record as it is read, so they are current even for old records. Prefer them over any table in this skill, which is a summary and can lag the platform.

### Records Arrive After the Operation

Records are handed to the platform's log store and indexed asynchronously, so a query run straight after a deploy, release or install can legitimately come back empty. **Within the first few minutes of an operation, an empty result means "not indexed yet", not "nothing happened".**

When the operation being diagnosed has just finished, poll before concluding anything:

```bash
for _ in $(seq 1 18); do
  OUT=$(foundry apps logs --deployment-id <deployment_id> --no-prompt)
  echo "$OUT" | grep -q "No log records for app" || { echo "$OUT"; break; }
  sleep 10
done
```

Allow up to ~3 minutes at a 10-second interval — that is the tolerance the platform's own integration tests use before treating a missing record as a real failure. Two things not to do while waiting: do **not** re-run the deploy to make records appear, since the deploy already happened and a second one just adds a second narrative to disentangle; and do **not** report "the deployment produced no logs" without having waited, because that conclusion is indistinguishable from having asked too early.

### When the Command Itself Fails

The CLI reports any non-200 from the API as a bare status code with no detail — `failed to retrieve app logs: failed to get app logs as server returned : 403`. Map it before changing anything in the app:

| Failure | What it means | What to do |
|---|---|---|
| `... server returned : 403` | The API credential lacks read on Custom Apps | A permissions problem, never an app problem. Fix the credential's scopes; do not debug the app |
| `... server returned : 500` | Failure inside the platform | Retry; if it persists, escalate with the app ID and the time of the query |
| `no app ID available; run from a deployed app's directory or pass --app-id` | Run outside an app directory with no `--app-id` | `cd` to the app root (where `manifest.yml` is) or pass `--app-id` |
| `invalid --since …`, `invalid --limit …` | Rejected locally before any call | Fix the flag. `--since` wants a duration (`30m`, `168h`), `--limit` a positive integer |
| `API client not available; check your configuration` | No usable profile or credentials | `foundry profile active` |
| `unknown command "logs"` | The CLI is below 2.1.2 | Upgrade (`brew upgrade crowdstrike/foundry-cli/foundry`); until then use `foundry apps list-deployments` plus the console |

**A nonexistent app ID is not an error.** The query is scoped to the caller's own tenant and no existence check runs, so a typo'd `--app-id` returns an empty result that looks exactly like a healthy app with nothing to report. Confirm the ID before reading anything into an empty result.

### Reasons and Operations This Skill Does Not List

The platform's vocabulary grows, so a record can carry a reason code or an operation name newer than this skill. That is not an error, and such a record is no less actionable — because the parts that tell you what to do are not supplied by this skill. **`fix=` and the `↳` steps are joined onto each record from the platform's own live catalog at read time**, so they are correct for a reason released after this text was written. The CLI holds no vocabulary of its own either; reasons and operations pass through as opaque strings, so there is nothing local to be stale.

Read every record structurally, in this order, and an unrecognized code costs you nothing:

1. **`level`** — `error` and `warn` need attention; `info` is narrative. Level always wins: it is written by the emitting operation, so it is right even when nothing else about the record is recognizable.
2. **Is a `fix=` part printed?** On an `info` record, no `fix=` means the platform marked it `none` — progress or success, nothing to act on. This is a rule, not a list, so it holds for codes that do not exist yet. On an `error` record it means the opposite: the platform has a reason it has not described, which is a gap to report with the `trace=` value, not a success.
3. **`fix=`'s value** — who acts (see above).
4. **The `↳` steps** — what to do, in order.
5. **`artifact=`** — present means the record is about one artifact and names it, which is where to look. Absent means the record is about the app as a whole: usually a summary, but not always — a failure that happens before any artifact exists is app-scoped and *is* the cause.

When a code is not in the [reason table](references/app-lifecycle-logs.md), do **not** report it as a bug, an unknown error, or an out-of-date CLI, and do not guess at it from the message alone. It means this skill is behind the platform. Report what the record says and act on `fix=` and the `↳` steps.

New codes share the build-and-run lifecycle vocabulary, so the shape of a name places it without a lookup:

| Shape | Where it sits | What to do |
|---|---|---|
| `<OPERATION>_STARTED` | the operation began | Nothing yet — find its terminal record |
| `_SUCCEEDED`, `_CREATED`, `_SAVED`, `_DELETED`, `_DISTRIBUTED`, `_SENT`, `_SUBMITTED` | it finished | Read the message: several of these mean *accepted*, not *done* |
| `<OPERATION>_FAILED` | that operation's terminal summary, typically `fix=unclear` | Not the cause — find the earlier, narrower error |
| `*_VALIDATION_FAILED`, `INVALID_*` | content the app shipped was rejected | Yours to fix; go to the artifact named by `artifact=`, at `fields=` |
| A bare condition: `TIMEOUT`, `RATE_LIMITED`, `PERMISSION_DENIED`, `NOT_FOUND`, `DEPENDENCY_UNREACHABLE`, `INTERNAL_ERROR` | the condition itself, whatever the operation | Trust `fix=` over an instinct about the condition — `TIMEOUT` is `fix=crowdstrike` |

`UNKNOWN` is the only code that genuinely means unclassified: the platform could not attribute the failure, so escalate with `trace=`. Do not confuse it with a code this skill merely does not list — the first is the platform saying it does not know, the second is only this document being behind.

An unfamiliar **operation** is another lifecycle verb alongside create, deploy, release, publish, install, update, uninstall, delete and import. Treat it as part of the same app lifecycle: read it, keep it in the narrative, and do not filter it out to make the output match this skill. There is no `--operation` filter to exclude it with anyway.

### Narrowing the Search

| Question | Flags |
|---|---|
| Why did this deployment fail? | `--deployment-id <id>` |
| Why did a deploy rejected at validation fail? | `--deployment-version 1.0.3` — a deploy that fails validation has no deployment ID on its app-scoped record |
| Has anything failed lately? | `--level error --since 168h` |
| What happened to one artifact? | `--artifact-id <id>` or `--artifact-type FAAS_FUNCTION` |
| One artifact version, across redeploys | `--artifact-version <version>` |
| An app whose directory you are not in | `--app-id <app_id>` |
| Everything sharing a trace with a failure | `--trace-id <trace_id>` |

Those eight flags plus `--since` and `--limit` are the entire query surface. Filters are ANDed, so each one only narrows further. Defaults are the last `24h` and 50 records; `--since` takes a duration (`30m`, `168h`) and `--limit` caps at 100 server-side. Inside an app directory `--app-id` defaults to the manifest's app.

**There is no `--operation` or `--reason` filter.** Operation and reason are columns to read, not flags — to see only the install records, query unscoped and read the operation column.

**A truncated result drops the cause, not the tail.** The limit is applied newest-first server-side and the CLI reverses for display, so hitting it discards the *oldest* records in the window — exactly where the first `ERROR` is. When the CLI warns that records were dropped, narrow with `--deployment-id` or shorten `--since`; raising `--limit` only helps up to 100. Do not diagnose from a truncated set.

**`--level warn` returns nothing.** No operation emits the `warn` level today, so an empty result there says nothing about the app's health. Use `--level error`.

**A filter value the platform does not recognize returns nothing rather than an error.** Neither `--level` nor `--artifact-type` is validated server-side, so `--level warning` instead of `warn`, or a misspelled enum, produces an empty result that reads exactly like a clean app. The accepted levels are `info`, `warn` and `error`; case does not matter, the CLI lowercases the value.

**`--artifact-type` is an exact match** on the platform's enum name (`UI_DASHBOARD`, `FAAS_FUNCTION`, …). A near-miss returns no records rather than an error, so read the value off an existing record's `artifact=` rather than guessing.

**Take `trace=` from a failure line.** The trace ID is the same for every record in one operation, so `--trace-id` retrieves that whole operation including records your other filters excluded. The CLI prints it only on `warn` and `error` records, so an `INFO` line will not show it.

### What the Records Do Not Cover

`apps logs` records the platform's *lifecycle* actions on an app. These produce no record at all, so an empty result is not evidence of health:

| Not recorded | Use instead |
|---|---|
| A deployed function or workflow failing at **runtime** | `foundry functions logs <exec_id>`; the workflow execution view in the console |
| A **successful** App Builder artifact save | Nothing to look for — only failed saves are recorded, by design |
| A release that stopped at an **MFA challenge** | `RELEASE_STARTED` with no terminal record is the signature — complete the challenge and re-release |
| A release that failed **before its deployment loaded** | The app is not yet known at that point; check `foundry apps list-deployments` |
| Artifact provisioning on the **v2 path** (flag-gated artifact types) | The Falcon console |

So a `DEPLOY_STARTED` with no terminal record means the operation is still running *or* failed in a way that is not recorded. Confirm which with `foundry apps list-deployments` before concluding either.

An empty result overall is not proof the app is healthy — widen `--since`, drop filters, and confirm the app was ever deployed.

See [references/app-lifecycle-logs.md](references/app-lifecycle-logs.md) for the record format, the `fix=` / `fields=` context keys, the reason-code table, and artifact type names.

## Local Testing

### Function Testing

```bash
# Via Foundry CLI with Docker (random ports, closest to production)
foundry functions run --name my-function

# Direct Go execution (port 8081, no Docker)
cd functions/my-function && go run main.go

# Direct Python execution (port 8081, no Docker)
cd functions/my-function && python3 main.py
curl -X POST http://localhost:8081/api/process -d '{"key":"value"}'

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

When a deployed function returns unexpected results or errors:

**Step 1: Execute and observe**
```bash
foundry functions exec --handler <handler> --logs '{"test": "input"}' --no-prompt
```

Note the exec_id and status code from the output.

**Step 2: Retrieve logs if not already displayed**
```bash
foundry functions logs <exec_id>
```

Logs arrive ~5 minutes after execution via the Firehose pipeline. The CLI polls automatically with a countdown.

**Step 3: Correlate logs against source**

The function source lives at the path in `manifest.yml`:
```yaml
functions:
  - name: my-function
    path: functions/my-function
    handlers:
      - name: my_handler
        method: POST
        api_path: /api/process
```

Read the handler source and compare against log timestamps and error messages.

**Step 4: Common runtime failures**

| Log Pattern | Likely Cause | Fix |
|-------------|-------------|-----|
| `ImportError: No module named X` | Missing from `requirements.txt` | Add dependency, redeploy |
| `KeyError: 'field'` | Missing field in request body | Add input validation |
| `401 Unauthorized` from FalconPy | Missing OAuth scope in manifest | Add scope, redeploy |
| `401 Unauthorized` on every call, scopes correct | FalconPy client constructed at module scope (no request token at import) | Construct the client inside the handler |
| `403` with `app is not installed` | App deployed but not released and installed | `foundry apps release`, then install from the App Catalog |
| `Timeout` / no logs appear | Function exceeded `max_exec_duration_seconds` | Increase timeout or optimize |
| Status 202, no result | Async execution | Poll: `foundry functions exec status <exec_id>` |
| Logs say "available" but empty | Logs not yet in pipeline | Wait 5 min or use `--refresh` |

**Step 5: Fix, redeploy, verify**
```bash
# After fixing the code:
foundry apps deploy --change-type Patch --change-log "fix handler error" --no-prompt

# Re-execute to verify
foundry functions exec --handler <handler> --logs '{"test": "input"}' --no-prompt
```

### RTR Script Testing

RTR scripts can only be tested via the CLI (not the Falcon console):

```bash
foundry rtr-scripts run --name my-script
```

Platforms: Windows (`script.ps1`), Linux (`script.sh`), macOS (`script.zsh`). Script size limit ~40KB. Deletion requires Falcon Administrator role in Falcon console UI.

### Workflow Mock Testing

```bash
foundry workflows triggers view --mock
foundry workflows actions view --mock
foundry workflows executions validate --mocks mymocks.json
foundry workflows executions start --definition my-workflow --mocks mymocks.json
foundry workflows executions view <execution_id>
```

### Deployment Diagnostics

Deployment is two-phase: validation (checks manifest and schemas) then artifact build. Use `foundry apps validate --no-prompt` to dry-run the validation phase after adding API integrations or collections (catches spec/schema issues in seconds). Don't validate right before deploy — deploy runs the same validation plus workflow semantics and name uniqueness checks.

When a deploy fails, `foundry apps logs --deployment-id <id> --no-prompt` is the fastest route to the cause — see the App Lifecycle Logs section above.

## CLI Troubleshooting

### Step 1: Environment Validation

```bash
foundry version         # Check CLI version
foundry profile list    # Check available profiles
foundry profile active  # Verify active profile
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
| Deploy reported as failed, no detail | CLI shows status only | `foundry apps logs --deployment-id <id> --no-prompt` |
| Release or install failed, no detail | CLI shows status only | `foundry apps logs --level error --no-prompt` |
| `apps logs` returns nothing | Default 24h window, app never deployed, or the failure is not one the platform records | Widen with `--since 168h`, drop filters, then check [What the Records Do Not Cover](#what-the-records-do-not-cover) |
| `foundry ui run` fails on new app | Backend not deployed | Run `foundry apps deploy` first |
| API calls return 403 | Insufficient OAuth scopes | Review manifest oauth section |
| Deploy fails silently | Tenant missing required module (SKU) | Verify tenant has Falcon module for scopes |
| Deployment `Failed`, CLI gives no reason | Reasons are console-only | App manager > app > "Show errors (N)" |
| `deployment is currently in progress` from `validate` | A deploy is still running | Poll `foundry apps list-deployments` until it settles, then retry |
| Local server won't start | Port conflicts | Use `--port` flag or kill existing processes |
| Auth works locally, fails in CI | No config file in CI | Set `FOUNDRY_API_CLIENT_ID` env vars |
| `connection issue` in a sandboxed agent | Denied write to the CLI's token cache | Grant write to `~/.config/foundry/`; the token refresh is expected |
| Tenant command works for user, not agent | Agent network sandbox | Request elevation, then retry once |
| Page 404 after deploy/release | App not installed from App Catalog | Install from catalog, wait for propagation |
| Page 404 on new cloud only | Cloud-specific IDs in manifest | Strip IDs with yq before deploying to new cloud |
| Blank page, no CORS errors | Vite `root` changed from `src` | Restore `root: 'src'` in vite.config.js |
| Blank page with CORS errors | `noAttr()` removed from vite.config.js | Restore the `noAttr()` plugin in vite.config.js |
| Blank page, no errors in console | `falcon.connect()` not awaited | The platform iframe stays blank until the postMessage handshake completes — add `await falcon.connect()` before any rendering |
| Data not appearing after writes | Schema mismatch or missing error check | Verify field names/enums match schema exactly; check `result?.errors?.length` after writes |
| Dialog white background in dark mode | Shoelace panel defaults | Override `--sl-panel-background-color` with `var(--ground-floor)` |
| App install fails with no detail | Workflow CEL expression error | Test API integration in console, then inspect workflow editor for errors |

## Debugging App Install Failures

When a Foundry app fails to install with no useful error message, isolate the problem by testing each component in the Falcon console:

1. **Read the install records first** — `foundry apps logs --level error --no-prompt`. An `INSTALL_FAILED` record often names the artifact and reason directly, which skips the isolation work below. If it only gives the generic summary, continue.

2. **Test the API integration** — In the Falcon console, use the credentials from the install config to test the operation directly (e.g., run `listUsers` with the Okta domain and API key). This proves whether the spec and credentials work independently of the app.

3. **Eliminate unlikely suspects** — Static UI files (extensions, pages) don't cause install failures. If the API integration works, the problem is almost certainly in a workflow.

4. **Inspect the workflow in the console** — Open Falcon Fusion SOAR, edit the workflow, and look at each action's configuration. The workflow editor shows validation errors (like unknown variable references in CEL expressions) that the install API doesn't surface.

> **Example:** Apps failed to install with no detail. API integration tested fine. Editing the workflow in the console revealed "unknown variable" on the Print data action — the CEL variable path was missing the `Custom_` prefix the platform adds to all API integration names. The install error gave no hint; the workflow editor showed it immediately.

## Visual Debugging with Screenshots

Claude Code can read images directly. When the Falcon console shows something unexpected — a blank page, an error modal, a disabled button — a screenshot is often the fastest way to diagnose the issue.

**Without Playwright MCP (fastest):** Ask the user to take a screenshot of what they're seeing and paste or drag it into the conversation. Claude reads it immediately and can identify error messages, missing elements, wrong page states, or styling issues without any setup.

**With Playwright MCP:** If Playwright MCP is configured (`claude mcp add playwright -- npx @playwright/mcp@latest`), Claude can take screenshots directly via `browser_take_screenshot`. This is useful for interactive debugging sessions. See `e2e-testing/references/debugging-with-mcp.md` for details.

**From test failure artifacts:** When e2e tests fail, Playwright saves screenshots to `test-results/`. Read the `.png` file directly — it shows the exact page state at the moment of failure.

Screenshots are particularly effective for:
- Blank pages after deploy (missing iframe, broken Vite config)
- Extension buttons that don't appear or expand
- Error banners or modals with messages not surfaced by the CLI
- `foundry ui run` rendering issues (dark mode, missing Shoelace styles)
- App install dialogs with unexpected form fields

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
1. Backup current `manifest.yml`
2. Start with minimal working manifest
3. Incrementally add capabilities back, deploying after each addition

## Pre-Escalation Checklist

Before seeking external help:

- [ ] Verified CLI version with `foundry version`
- [ ] Checked authentication with `foundry profile active`
- [ ] Read the app's lifecycle records with `foundry apps logs` (scoped with `--deployment-id` for a failed deploy)
- [ ] Captured the `trace=` value from the failing record to quote to support
- [ ] Validated OpenAPI specs with `npx @redocly/cli lint` (if applicable)
- [ ] Tested with minimal configuration
- [ ] Reviewed CLI error messages
- [ ] Attempted recovery procedures
- [ ] Documented reproduction steps
