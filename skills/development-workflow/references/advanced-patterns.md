# Advanced Patterns

## Lifecycle Phases

### Phase 0: CLI Prerequisite Check

Before any Foundry work, verify the CLI is installed and authenticated:

```bash
# 1. Check CLI is installed (cross-platform — fails if not installed)
foundry version

# If not installed:
#   macOS/Linux: brew tap crowdstrike/foundry-cli && brew install foundry
#   Windows: Download https://assets.foundry.crowdstrike.com/cli/latest/foundry_Windows_x86_64.zip
#            Expand the archive and add the installation directory to PATH

# 2. Check authentication
foundry profile active

# If no profile exists, guide through one of:
#   foundry profile create --name "my-profile" --api-client-id "<id>" --api-client-secret "<secret>" --cid "<cid>" --cloud-region "us-1" --no-prompt
#   foundry login  (interactive — opens browser)
```

### Phase 1: Discovery
- Profile setup and environment validation
- Requirements gathering and capability mapping
- Template selection based on app type

### Phase 2: Scaffolding (CLI-First)

**CRITICAL: Use CLI scaffolding commands first, even when using superpowers planning skills.** If an external planning skill (e.g., `superpowers:writing-plans` or `superpowers:subagent-driven-development`) generates a plan, the plan's tasks MUST use CLI commands for scaffolding. Do not manually create manifest.yml, workflow YAML shells, or UI boilerplate that the CLI can generate.

Use CLI scaffolding commands to generate artifacts. The CLI creates directories, copies files, and updates manifest.yml with generated IDs. **Write spec/schema files to `/tmp/` first** — the CLI copies them into the project. Hand-write only what the CLI cannot generate (workflow YAML content, OpenAPI spec JSON, UI component code, collection schema JSON, Foundry-specific OpenAPI annotations like `x-cs-operation-config`).

> **Note:** OAuth scopes are auto-managed by the platform for CLI-created artifacts. Do NOT manually add scopes like `api-integrations:read` to `manifest.yml` — Foundry handles permissions for its own artifacts automatically. Only use `foundry auth scopes add` for additional Falcon Platform API scopes (e.g., `hosts:read`, `detects:read`) not covered by the scaffolded capabilities.

### Phase 3: Development
- **MANDATORY sub-skill delegation** for all capability development
- `foundry ui run` state management across development sessions
- Continuous manifest.yml coordination and validation

### Phase 4: Integration
- Manifest validation and testing
- End-to-end testing patterns
- `foundry apps deploy` for cloud testing

### Phase 5: Release
- Cloud environment testing
- `foundry apps release` to catalog
- Documentation and handoff

## Manifest Coordination Patterns

**Manifest-First Development (MANDATORY):**
1. Define all capabilities in manifest.yml BEFORE implementation
2. Specify permissions, routes, and dependencies upfront
3. Validate manifest before starting capability development
4. Update manifest immediately when adding capabilities

**Schema-Driven Coordination:**
- Collections define data contracts for all capabilities
- Functions reference collection schemas in TypeScript/Go types
- UI components use generated types from schemas
- Workflows access collections through validated operations

**Permission Coordination:**
- UI extensions declare required Falcon API scopes
- Functions request minimal necessary permissions
- Workflows inherit permissions from component capabilities
- RTR scripts specify endpoint access requirements

**Dependency Resolution:**
- Collections MUST exist before functions that use them
- Functions MUST exist before workflows that call them
- UI MUST exist before workflows that display results
- API integrations MUST exist before capabilities that consume them

**Continuous Validation:**
- Use `npx @redocly/cli lint` to validate OpenAPI specs — do NOT use Python, Ruby, or other language-specific YAML parsers
- Use `foundry apps validate --no-prompt` to validate the manifest and schemas without deploying
- Use `foundry apps run` to validate the manifest on startup
- Restart `foundry ui run` when permissions change
- Test capability integration with minimal viable examples

## CLI State Management

**Current Working Directory:** Always maintain awareness of current project context
- `pwd` before any foundry command
- Navigate to correct app directory: `cd path/to/foundry-app`
- Verify manifest.yml exists: `ls manifest.yml`

**Foundry Profile State:** CLI authentication and environment
- Check current profile: `foundry profile list`
- Check active profile: `foundry profile active`
- Switch if needed: `foundry profile activate --name <profile-name>`

**Development Server State:** UI serving for local development
- Run `foundry ui run` during UI development — **deploy first if the UI calls API integrations, collections, or functions** (those resolve from the cloud)
- Use `foundry apps run` to start the full app locally in dev mode (validates manifest on startup)
- Monitor for permission errors indicating manifest drift
- Restart server after manifest.yml changes

**Build State:** Asset compilation and deployment readiness
- Track dependency changes: monitor `package.json` / `go.mod` modifications
- Rebuild on schema changes: collections affect TypeScript types

## App Lifecycle Operations

### Import, Export, Clone, and Sync

| Operation | Tool | Notes |
|-----------|------|-------|
| **Import** | Falcon console only (not CLI) | Accepts tar.gz or ZIP |
| **Export** | Falcon console only (not CLI) | Exports full app package |
| **Clone** | CLI only: `foundry apps clone` | Creates a local copy of a deployed app |
| **Sync** | CLI: `foundry apps sync` | Syncs local project with deployed state |

```bash
# Clone an existing deployed app to local
foundry apps clone --name "existing-app"

# Sync local project with deployed state
foundry apps sync
```

### Development Mode vs Preview Mode

| Feature | Development Mode | Preview Mode |
|---------|-----------------|--------------|
| Activation | `foundry ui run` | Enable in console after deploy |
| Port | 25678 | N/A (uses deployed assets) |
| Source | Polls localhost | Uses deployed build |
| Purpose | Active UI development | Testing deployed UI |
| Hot reload | Yes | No |

> **Mutually exclusive:** Only one mode can be active at a time. Disable development mode before enabling preview mode, and vice versa.

### Package Size Optimization

Use the `ignored` field in `manifest.yml` to exclude files from the deployment package:

```yaml
ignored:
  - "**/*.test.ts"
  - "**/*.spec.js"
  - "**/node_modules/.cache/**"
  - "**/__pycache__/**"
```

## Session Handoff

When transferring Foundry development between sessions, preserve:
- Current foundry profile and authentication status
- Development server state (`foundry ui run` status and port)
- Current working directory and manifest.yml validation state
- Last deployment status and environment
- Capability development progress per sub-skill
- OAuth scope conflicts and resolution decisions

## Implementation Planning

Before implementing Foundry capabilities, plan the following:

1. **Manifest dependency ordering**: Collections before functions that use them, functions before workflows that call them, UI after backend capabilities are ready
2. **OAuth scope inventory**: List all required scopes across capabilities; request minimal permissions
3. **Capability mapping**: Map each requirement to the correct sub-skill (UI, Collections, Functions, Workflows, API Integration)
4. **CLI state requirements**: Identify which profiles, environments, and development servers are needed

### Execution Checkpoints

Between capability phases, verify:
- `foundry ui run` reflects latest manifest changes (restart if permissions changed)
- Tests pass for completed capabilities before starting dependent ones

## OpenAPI Spec Sourcing

**NEVER write OpenAPI specs from scratch.** When users need API integrations, ask first if they have an existing spec or know where to download one. Search locally, download from the vendor's GitHub/docs, or trim a large spec to the needed operations. The api-integrations sub-skill handles all spec preparation including Foundry-specific server variable fixes and `x-cs-operation-config` annotations.

## Workflow YAML Action ID Patterns

For action IDs in workflow YAML, use the `api_integrations.{name}.{operationId}` pattern for API integration operations. Do NOT guess platform action docIDs (e.g., `send_email`, `log`). If the workflow needs platform actions, set `provision_on_install: false` and add a TODO comment -- the user will configure these in the Falcon console's App Builder.

## Deployment Nuance

`foundry apps deploy` requires `--change-type` and `--change-log`. The `--no-prompt` flag is available as a global Controller flag and skips the deployment confirmation prompt and TUI monitor, but is not required when all flags are provided. `foundry apps release` requires `--deployment-id`, `--change-type`, and `--notes` and works fully non-interactively when all three flags are provided.
