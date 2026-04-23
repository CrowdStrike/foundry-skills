---
name: foundry-debugging-workflows
description: Systematic troubleshooting for Falcon Foundry CLI errors, manifest validation failures, deploy failures, and development server issues. TRIGGER when user encounters CLI errors, `foundry ui run` not working, deploy failures, authentication issues, or any unexpected behavior during Foundry app development. Also trigger for headless/CI environment setup failures.
version: 1.0.0
updated: 2026-04-09
metadata:
  author: CrowdStrike
  category: troubleshooting
  tags: [foundry, debugging, cli, deployment]
---

# Foundry Debugging Workflows

Systematic procedures for diagnosing and resolving common CrowdStrike Falcon Foundry development issues.

## Quick Diagnosis

```
What's happening?

CLI command hangs
├── In headless/CI environment → Missing --no-prompt or required flags (see Headless section)
└── In interactive terminal   → Check network/auth with foundry profile active

Deploy fails
├── Validation error → Check manifest YAML syntax, then deploy again
├── "Unknown error"  → Duplicate workflow name across apps in tenant
└── Silent failure   → Tenant may be missing required module (SKU) for requested scopes

foundry ui run fails
├── On new app              → Deploy backend capabilities first (API integrations, functions, collections resolve from cloud)
├── Permission errors       → Check manifest OAuth scopes, restart server, verify auth
└── Blank page / CORS error → noAttr() or base path removed from vite.config.js (see foundry-ui-development)

Auth fails
├── 401/403 from API   → Check OAuth scopes in manifest
├── Login hangs        → Headless environment, no browser — use env vars or profile create --no-prompt
└── Works locally, fails in CI → Set FOUNDRY_API_CLIENT_ID env vars in CI config
```

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
| Local server won't start | Port conflicts | Use `--port` flag or kill existing processes |
| Auth works locally, fails in CI | No config file in CI | Set `FOUNDRY_API_CLIENT_ID` env vars |
| Page 404 after deploy/release | App not installed from App Catalog | Install from catalog, wait for propagation |
| Page 404 on new cloud only | Cloud-specific IDs in manifest | Strip IDs with yq before deploying to new cloud |
| Blank page, no CORS errors | Vite `root` changed from `src` | Restore `root: 'src'` in vite.config.js |
| Blank page with CORS errors | `noAttr()` removed from vite.config.js | Restore the `noAttr()` plugin in vite.config.js |
| Dialog white background in dark mode | Shoelace panel defaults | Override `--sl-panel-background-color` with `var(--ground-floor)` |
| App install fails with no detail | Workflow CEL expression error | Test API integration in console, then inspect workflow editor for errors |

## Debugging App Install Failures

When a Foundry app fails to install with no useful error message, isolate the problem by testing each component in the Falcon console:

1. **Test the API integration first** — In the Falcon console, use the credentials from the install config to test the operation directly (e.g., run `listUsers` with the Okta domain and API key). This proves whether the spec and credentials work independently of the app.

2. **Eliminate unlikely suspects** — Static UI files (extensions, pages) don't cause install failures. If the API integration works, the problem is almost certainly in a workflow.

3. **Inspect the workflow in the console** — Open Falcon Fusion SOAR, edit the workflow, and look at each action's configuration. The workflow editor shows validation errors (like unknown variable references in CEL expressions) that the install API doesn't surface.

> **Example:** Apps failed to install with no detail. API integration tested fine. Editing the workflow in the console revealed "unknown variable" on the Print data action — the CEL variable path was missing the `Custom_` prefix the platform adds to all API integration names. The install error gave no hint; the workflow editor showed it immediately.

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
- [ ] Validated OpenAPI specs with `npx @redocly/cli lint` (if applicable)
- [ ] Tested with minimal configuration
- [ ] Reviewed CLI error messages
- [ ] Attempted recovery procedures
- [ ] Documented reproduction steps

## Reference Files

| Topic | Reference |
|-------|-----------|
| Performance optimization, support resources, escalation paths | [references/advanced-patterns.md](references/advanced-patterns.md) |
