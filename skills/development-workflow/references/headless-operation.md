# Headless / Non-Interactive Operation

**FOUNDATIONAL PRINCIPLE: The Foundry CLI defaults to interactive browser-based flows that fail in headless environments (CI/CD pipelines, SSH sessions, Claude Code, containers). All CLI operations MUST use non-interactive flags and patterns.**

## Authentication Without a Browser

The default `foundry login` command opens a browser for OAuth authorization. This **will hang or fail** in headless environments. Use these alternatives:

**Option 1: Environment Variables (Preferred for CI/CD and Agents)**

Set these environment variables to bypass local credential storage entirely:

```bash
export FOUNDRY_API_CLIENT_ID="<your-api-client-id>"
export FOUNDRY_API_CLIENT_SECRET="<your-api-client-secret>"
export FOUNDRY_CID="<your-customer-id>"
export FOUNDRY_CLOUD_REGION="us-1"  # us-1, us-2, us-3, eu-1, us-gov-1, us-gov-2
```

Environment variables override local credentials. No `foundry login` needed.

**Option 2: Non-Interactive Profile Creation (Preferred for Developer Machines)**

Create a profile directly from an existing API client ID and secret:

```bash
foundry profile create \
  --name "my-profile" \
  --api-client-id "<client-id>" \
  --api-client-secret "<client-secret>" \
  --cid "<customer-id>" \
  --cloud-region "us-1" \
  --no-prompt
```

Then activate it non-interactively:

```bash
foundry profile activate --name "my-profile"
```

**Option 3: Extract Credentials for Later Headless Use**

Run `foundry login --no-config` once in an interactive environment. This outputs credentials to stdout instead of saving to the config file, allowing you to capture and store them as environment variables.

**Configuration File Location:**
- Linux/macOS: `${XDG_CONFIG_HOME:-$HOME/.config}/foundry/configuration.yml`
- Windows: `C:\Users\<username>\.config\foundry\configuration.yml`

## Non-Interactive Command Flags

Commands that prompt for user input support `--no-prompt` to suppress prompts and fail with an error if required flags are missing. **Always use `--no-prompt` when running commands from agents or scripts.**

| Command | Non-Interactive Form |
|---------|---------------------|
| `foundry apps create` | `foundry apps create --name "app" --description "desc" --no-prompt --no-git` |
| `foundry apps delete` | `foundry apps delete --force-delete --no-prompt` |
| `foundry apps validate` | `foundry apps validate --no-prompt` |
| `foundry apps deploy` | `foundry apps deploy --change-type minor --change-log "description" --no-prompt` |
| `foundry apps release` | `foundry apps release --deployment-id <id> --change-type minor --notes "notes"` |
| `foundry profile create` | `foundry profile create --name <n> --api-client-id <id> --api-client-secret <s> --cid <c> --cloud-region <r> --no-prompt` |
| `foundry profile activate` | `foundry profile activate --name "profile-name"` |
| `foundry profile delete` | `foundry profile delete --name "profile-name" --no-prompt` |
| `foundry collections create` | `foundry collections create --name "col" --schema /tmp/schema.json --description "desc" --no-prompt` |
| `foundry functions create` | `foundry functions create --name "fn" --language go --description "desc" --handler-name h --handler-method GET --handler-path /path --no-prompt` |
| `foundry rtr-scripts create` | `foundry rtr-scripts create --name "script" --platform Linux --no-prompt` |
| `foundry ui pages create` | `foundry ui pages create --name "pg" --description "desc" --from-template React --homepage --no-prompt` |
| `foundry ui extensions create` | `foundry ui extensions create --name "ext" --from-template React --sockets "hosts.host.panel" --no-prompt` |
| `foundry workflows create` | `foundry workflows create --name "wf" --spec /tmp/workflow.yml --no-prompt` |
| `foundry api-integrations create` | `foundry api-integrations create --name "api" --description "desc" --spec /tmp/spec.json --no-prompt` |
| `foundry docs create` | `foundry docs create --name "doc.md"` |

> **Note:** `apps release` does not need `--no-prompt` — it works non-interactively when `--deployment-id`, `--change-type`, and `--notes` are provided. `apps deploy` accepts `--no-prompt` but also works without it when `--change-type` and `--change-log` are provided.

**Commands that do NOT exist** (do not attempt these):
- `foundry apps init` — use `foundry apps create` instead

## Disabling the Enhanced UI (TUI) — TTY Error Fix

The Foundry CLI has an enhanced UI mode (TUI progress monitor) that requires a TTY. In non-interactive environments (Claude Code, CI/CD, SSH), the TUI will fail with:

```
Error: could not open a new TTY: open /dev/tty: device not configured
```

or hang and produce garbled output.

**Fix:** As of Foundry CLI v2.0.1, headless mode is detected automatically. No env var or prefix needed. If using an older CLI version, set the env var manually:

```bash
export FOUNDRY_UI_HEADLESS_MODE=true
```

This disables the TUI progress monitor and falls back to plain text output suitable for non-interactive environments.

**Keywords:** TTY, TUI, `/dev/tty`, `device not configured`, `could not open a new TTY`, enhanced UI, progress monitor

## US-GOV-1 Headless Configuration

US-GOV-1 environments require additional environment variables:

```bash
export FOUNDRY_UI_DOMAIN="https://falcon.laggar.gcw.crowdstrike.com"
export FOUNDRY_API_GW_DOMAIN="https://api.laggar.gcw.crowdstrike.com"
```

## Agent-Specific Guidance

When operating as a CLI agent:

1. **Check for existing profiles first:** Run `foundry profile list` to see if authentication is already configured
2. **Prefer environment variables:** If profiles don't exist, ask the user to set `FOUNDRY_API_CLIENT_ID`, `FOUNDRY_API_CLIENT_SECRET`, `FOUNDRY_CID`, and `FOUNDRY_CLOUD_REGION`
3. **Never run `foundry login` without user confirmation:** The browser flow will hang in headless environments
4. **Always pass all required flags:** Never rely on interactive prompts — always include `--no-prompt` where supported
5. **Use `--no-git` on `foundry apps create`:** Prevents git init prompts in environments where git may not be configured
6. **Headless mode** is detected automatically by Foundry CLI v2.0.1+. For older versions or standalone scripts/CI, export `FOUNDRY_UI_HEADLESS_MODE=true` manually.
7. **Choose the app directory automatically:** Use the current directory unless it is an unrelated repository; in that case use a sibling directory and request write access if the sandbox requires it.

### The token cache write is expected — approve it

The CLI stores long-lived client credentials in `configuration.yml`, but keeps the short-lived access token in a **separate** file, `~/.config/foundry/token.json`. That token lasts about 30 minutes. When it expires, the next tenant command mints a new one and writes it back to that file.

**This write is normal and is the more secure design.** A 30-minute token that gets rotated on disk is safer than a long-lived one held anywhere, and keeping it outside the workspace means it never lands in the app directory or gets committed. Seeing `token.json` change is correct behavior, not tampering.

Sandboxed assistants that confine writes to the workspace will be denied that write. The CLI then reports only `connection issue`, which describes the symptom and not the cause — nothing is wrong with the network or the credentials. Because a session usually starts with an already-expired token, this fails within the first few seconds rather than after 30 minutes of work.

When the write is denied, **request write access to `~/.config/foundry/` and retry the same command.** Do not stop the workflow, and do not ask the user to relaunch their assistant — this is a routine, low-risk escalation of the same kind as reading the profile, and it is the expected way to proceed. State plainly why you need it: the CLI is refreshing its own token cache.

Do not respond by rewriting the profile, redirecting the config path into the workspace, or copying `configuration.yml` anywhere — each hides the working credentials instead of granting the one write that is needed.

### Sandboxed network access

If the token write succeeds and tenant commands still fail with `connection issue`, then suspect the network. Ask the user to run the same command in their terminal; when it works there, request elevated or unsandboxed network access and retry once. If elevation is unavailable, tell the user which permission to enable, or give them the exact command to run and ask for its output. Local profile commands do not prove the agent process can reach the tenant.

## Counter-Rationalizations for Interactive Mode

| Your Excuse | Reality |
|-------------|---------|
| "foundry login is the documented first step" | It requires a browser — use `profile create --no-prompt` or env vars instead |
| "I'll just run the command and see" | Interactive prompts will hang the agent session |
| "The user can handle the prompt" | Agents cannot pass interactive input to subprocesses |
| "I'll skip --no-prompt, it probably works" | Missing required flags without --no-prompt causes an interactive prompt that blocks |
