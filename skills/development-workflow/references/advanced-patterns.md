# Advanced Patterns

## Lifecycle Phases

### Phase 0: CLI Prerequisite Check

Before any Foundry work, verify the CLI is installed and authenticated:

```bash
# 1. Check CLI is installed (cross-platform — fails if not installed)
foundry version

# If not installed:
#   macOS/Linux: brew tap crowdstrike/foundry-cli && brew install crowdstrike/foundry-cli/foundry
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

> **Note:** OAuth scopes are auto-managed by the platform for CLI-created artifacts. Do NOT manually add scopes like `api-integrations:read` to `manifest.yml` — Foundry handles permissions for its own artifacts automatically. Only use `foundry auth scopes add` for additional Falcon Platform API scopes (e.g., `devices:read`, `detects:read`) not covered by the scaffolded capabilities.

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
| **Sync** | CLI: `foundry apps sync` | Pulls a deployed version's files (including the IDs the deploy assigned) into a **new subdirectory named after the app**, not the current directory |

```bash
# Clone an existing deployed app to local
foundry apps clone --name "existing-app"

# Sync a deployed version's files (and the IDs the deploy assigned) into the CURRENT directory.
# -d . targets the current dir instead of a new subdirectory; --replace-all overwrites existing files.
# Under --no-prompt, --deployment-version is required, else: "flag --deployment-version is required
# when --no-prompt flag is used". --app-id selects the app when the manifest's app_id is blank.
foundry apps sync --deployment-version v0.1.0-pre-release -d . --replace-all --no-prompt
```

**`sync`'s target directory defaults to the app name.** Without `-d/--directory` it writes into a new `AppName/` directory (spaces included), which looks like it ignored your project — pass `-d .` (with `--replace-all` when the directory already has files) to sync in place. *(Confirm the exact flags with `foundry apps sync --help`; CLI flags can change between releases.)*

**The ID-stripping convention fights local tooling.** If you commit `manifest.yml` with blanked IDs (the `foundry-sample-*` pattern, so the app installs into any CID), local commands still need the real IDs present. `foundry functions exec` fails with `app_id not found in manifest; deploy the app first`, and `foundry apps deploy` needs them to target the existing app instead of creating a new one. Re-fill the IDs from the deployed app before working locally, then blank them again before committing.

Don't sync into the working copy to do it: `-d . --replace-all` replaces **every** file with the deployed version, so any function, UI, or manifest edit that isn't deployed yet is lost. Sync into a scratch directory and copy only the IDs across. Copying the whole synced `manifest.yml` has the same problem for undeployed manifest edits (a changed `model`, a new `ignored` pattern), and the synced file is re-indented besides. The `yq` merge below matches pages by key and functions and agents by name; extend it for other artifact types your app has (extensions, workflows, API integrations):

```bash
foundry apps sync --app-id <app-id> --deployment-version <version> -d /tmp/app-deployed --replace-all --no-prompt
S=/tmp/app-deployed/manifest.yml
yq -i "
  .app_id = load(\"$S\").app_id |
  .ui.pages |= with_entries(.key as \$k | .value.id = load(\"$S\").ui.pages[\$k].id) |
  .ui.navigation.id = load(\"$S\").ui.navigation.id |
  .functions[] |= (.name as \$n | .id = (load(\"$S\").functions[] | select(.name == \$n) | .id)) |
  .docs.id = load(\"$S\").docs.id |
  .ai.agents[] |= (.name as \$n | .id = (load(\"$S\").ai.agents[] | select(.name == \$n) | .id))
" manifest.yml
git diff manifest.yml   # only id lines should change
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

### What the Deploy Packages (`ignored:`)

`foundry apps deploy` walks the app directory and packages every file except:

- **Hidden paths.** Any path with a component starting with `.` is skipped, so `.venv`, `.pytest_cache`, `.env`, and `.git` never need `ignored:` entries.
- **SVG files.** `*.svg` is always excluded (an XSS guard), which is why a page should inline an SVG rather than reference one by path.
- **Anything matching an `ignored:` entry.**

Each `ignored:` entry is a **Go regular expression**, not a glob, matched unanchored against the path relative to the app root. A glob like `**/*.test.ts` is an invalid regex and fails `foundry apps validate` with `ignored item "..." is not a valid regular expression`. Because matching is unanchored, `tests` also matches `contests.py`; anchor on path separators:

```yaml
ignored:
  - (^|/)__pycache__(/|$)
  - ^functions/[^/]+/tests(/|$)
  - (^|/)node_modules(/|$)
  - \.test\.ts$
```

`__pycache__/` and `tests/` are the entries a Python function usually needs; without them, the deploy lists the `.pyc` files and test modules.

**Ignoring `tests/` makes `exec` warn on every run.** `foundry functions exec` compares the whole local function directory against the last deployment, and the deployment has no `tests/`, so it reports undeployed local changes even right after a successful deploy. Pass `--ignore-deploy-warning` once you have confirmed the handler itself is deployed (see `functions-development/references/execution-and-testing.md`).

**Deploy never builds a UI.** It uploads each page's and extension's gitignored `dist/` as it is, so a deploy after a UI edit without `npm run build` ships the previous bundle with no error, and tests and lint can't catch it. Build last, then check the package with `foundry apps deploy --diff-only --no-prompt`, which prints the file diff without deploying: a UI change must list new `dist/assets` files. `foundry apps validate --no-prompt` prints the same `Computed diff ... from version <deployed>` list.

Every deploy takes the next deployment number, failed ones included, but a release continues from the last release: releasing `v1.6.3-pre-release` after `v1.6.2-pre-release` failed produced `1.6.2`.

### App Logo

The manifest `logo:` field is a relative path to a small square PNG, ~160x160, matching the `foundry-sample-*` apps (e.g. `logo: images/logo.png`). Two things about it are easy to get wrong:

- **It is only picked up on the app's first deploy.** The App Catalog icon is set from `logo:` when the app is first created on a cloud. Adding or changing the logo in a later patch deploy does not update the catalog icon; it keeps the generated text avatar (the app's initials). To change an existing app's icon you effectively need a fresh app (delete and redeploy), so get the logo right before the first deploy.
- **A logo-only change will not deploy.** `foundry apps deploy` versions artifacts (functions, collections, UI pages, agents). If the diff from the last version contains only the logo image and/or manifest metadata with no artifact change, deploy fails with `no deployable artifacts found`. There is no `--force`. Bundle the logo with an artifact change, or include it in the first deploy.

If a UI page displays the same logo, inline the SVG in the page markup rather than referencing the PNG by path. The page runs in a sandboxed iframe without `allow-same-origin` and cannot load an image file from outside its own `src/` directory.

**Deleting an app:** `foundry apps delete --force-delete --no-prompt` removes the app from the cloud but keeps the local files. The `--local-files` flag *also* deletes the local manifest and app directory, so omit it unless you intend to erase the local project too.

**Deploying a deleted app again from the same directory:**

- Strip the `id` and `app_id` keys first, with the same `yq` command as Multi-Cloud Deployment in `SKILL.md`. With the old IDs, `foundry apps validate` refuses collections that "existed previously, but were deleted".
- Version numbers come from the cloud: each deploy takes the next number for its change type, failed deploys included, and no flag sets one. For the new app they start over, so the first `--change-type Minor` deploy is `v0.1.0`.
- Objects the old app created through Falcon APIs are separate tenant objects and outlive it. Examples: dashboards, saved searches, and Falcon Next-Gen SIEM persisted aggregations, which keep running and storing data. Clean them up before you delete the app, or in the console afterward.

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

## Testing an Existing App Locally

When running e2e tests against a CrowdStrike/foundry-sample-* app on GitHub:

1. **Configure credentials** — copy `.env.sample` to `.env` in the `e2e/` directory and fill in valid Falcon credentials (username, password, TOTP secret, base URL) and app name. `APP_NAME` defaults to the repo name. `FALCON_` credentials must be for a non-SSO user because TOTP is used in e2e tests. This file is gitignored and required for local test runs.

2. **Align the app name** — the manifest `name` and the e2e test `APP_NAME` environment variable (in `.env`) must match for local test runs. CI pipelines typically rewrite the manifest name automatically (e.g., `${REPO}-ci-${PIPELINE_ID}`), so this only affects local development. Preferred approach: update the manifest `name` to match the repo name (e.g., `foundry-sample-logscale`) to avoid spaces and simplify artifact lookup. Remember to `git checkout manifest.yml` after deploy to revert ID changes.

3. **Deploy and release:**

   ```bash
   foundry apps deploy --change-type Patch --change-log "e2e testing" --no-prompt
   # Poll until successful
   foundry apps list-deployments
   # Release
   foundry apps release --deployment-id <id> --change-type Patch --notes "e2e testing" --no-prompt
   ```

4. **Run tests:** `cd e2e && npm test`

5. **Revert manifest:** `git checkout manifest.yml` (deploy writes IDs into the manifest). **This revert applies ONLY to throwaway e2e runs of the public `foundry-sample-*` repos, which commit blanked IDs so the app installs into any CID. For an app you own and operate, do the OPPOSITE — commit the IDs the first deploy writes back (see `SKILL.md` → Manifest Coordination); reverting them breaks the next deploy, which fails with `an app with the provided name already exists` (see `debugging-workflows` → Manifest Issues).**

## Capability Create Commands

Full capability-create sequence (from `SKILL.md` → App Creation Flow → Step 5). Run in dependency order: knowledge bases before agents, and agents before the workflows that call them. Write spec/schema files to `/tmp/` — the CLI copies them into the project and updates `manifest.yml` with generated IDs.

```bash
# 1. API integrations — delegate spec work to api-integrations sub-skill
#    IMPORTANT: Download specs inline with gh/curl. Do NOT spawn Explore agents for spec download.
foundry api-integrations create --name "MyApi" --description "desc" --spec /tmp/MyApi.yaml --no-prompt

# 2. Collections (names: letters, numbers, underscores ONLY)
foundry collections create --name "my_col" --schema /tmp/my_schema.json --description "desc" --no-prompt

# 3. VALIDATE EARLY — fail fast if specs or schemas are bad
foundry apps validate --no-prompt
# If validation fails, STOP. Fix the spec/schema — do not build UI on a broken backend.
# The adapt script handles known spec issues. If one remains, patch only that spot and tell the user what the script missed.

# 4. Functions
foundry functions create --name "my-fn" --language python --description "desc" \
  --handler-name process --handler-method POST --handler-path /api/process --no-prompt

# 5. Knowledge bases BEFORE agents — the agent create command validates KB refs.
#     --files is required with --no-prompt (accepts local paths or HTTP(S) URLs).
foundry knowledge-bases create --name "Runbook Docs" --description "desc" \
  --files /tmp/runbook.md --no-prompt

# 6. AI agents — reference KBs by NAME. Exposure is set with --expose-* flags;
#     see ai-agents-development for the model/tools manifest hand-edits.
foundry agents create --name "My Agent" --description "desc" \
  --system-prompt /tmp/system_prompt.md \
  --knowledge-bases "Runbook Docs" --expose-charlotte-chat --no-prompt

# 7. Workflows — MUST load workflows-development sub-skill before writing the spec file.
#    After agents, so a workflow can call one by its ai_agents.<name> alias.
foundry workflows create --name "My Workflow" --spec /tmp/My_workflow.yml --no-prompt

# 8. UI pages (standalone full-page views)
foundry ui pages create --name "my-page" --description "desc" --from-template React --homepage --no-prompt
foundry ui navigation add --name "My Page" --path / --ref pages.my-page

# 8b. UI extensions (sidebar widgets embedded in detection/host/incident pages)
# Run `foundry ui extensions list-sockets` to see available socket IDs
foundry ui extensions create --name "my-ext" --description "desc" --from-template React --sockets "activity.detections.details" --no-prompt
```

**Fail fast:** Validate right after API integrations and collections. `foundry apps validate` is a dry-run of deploy validation — it checks specs and schemas in seconds without building artifacts. It does NOT check workflow semantics or app name uniqueness (those are only checked on deploy). Don't validate right before deploy — deploy runs the same validation plus more. Let `adapt_spec_for_foundry.py` fix spec issues; if it misses one, patch only that spot and tell the user what it missed.

## Sub-Skill Loading

Load the relevant sub-skill before writing domain-specific code (from `SKILL.md` → App Creation Flow → Step 6). Foundry formats and SDK calls differ from what general knowledge suggests; these are the failures seen when the sub-skill wasn't loaded:

| Writing... | Load | What goes wrong without it |
|---|---|---|
| Workflow YAML | `workflows-development` | Invented `definition/node_types/sdk_type` format instead of correct `trigger` + `actions` with `version_constraint` |
| Function code calling Falcon APIs | `functions-falcon-api` | Invented `request.falcon_client.api_request(url='/foundry/entities/...')` instead of FalconPy SDK classes (`from falconpy import Hosts`) |
| Function code calling a third-party API (Slack, Jira, PagerDuty, etc.) | `functions-falcon-api` + check `use-cases/` | Invented `falcon.command("createNotification")` or raw HTTP calls instead of `APIIntegrations().execute_command(definition_id="...", operation_id="...")`. The app MUST have an API integration (OpenAPI spec) for the service, then call it from the function via FalconPy `APIIntegrations` class. See foundry-sample-functions-python for reference. |
| Function code accessing collections | `collections-development` | Invented REST endpoints for collection CRUD instead of FalconPy `CustomStorage` service class |
| AI agent or knowledge base manifest | `ai-agents-development` | Invented `model` values, wrong `tools` reference format, or agents created before the knowledge bases they reference (fails validation) |

## Deploy & Release

Operational depth behind `SKILL.md` → App Creation Flow → Step 7.

> **`foundry apps deploy --re-deploy` retries the latest failed deployment** (`--help`). It's for retrying that deployment, not for shipping a new edit: to test an edit, run a plain `foundry apps deploy`.

**Patch releases update an installed app in place**; no reinstall. Enter or rotate API integration credentials, including for an integration added in a later patch, under **App catalog > the app > ⋮ > Modify settings**. That option only exists if the app had settings at first install. If ⋮ shows only **Uninstall app**, release with `--change-type Major`; **Accept update** then shows the credential form, and Modify settings works after that. Don't reinstall; dependent workflows can break.

> **After an update, hard-refresh before you trust what you see.** The Falcon console iframe caches the built bundle, so a correctly released change can keep showing the old UI or logic until a hard refresh (Cmd/Ctrl+Shift+R). If a visual or behavioral change doesn't appear, hard-refresh first — do NOT re-deploy to "fix" it. Content-hashed asset names help, but the console shell still caches. To confirm the fix is in the package before assuming the deploy failed, use the `--diff-only` check under **Deploy never builds a UI** above.

> **Three version numbers — don't conflate them.**
> - **App Catalog version** (`v0.1.x`) — bumped by `foundry apps release --change-type`; authoritative; what App Manager shows.
> - **Pre-release deploy number** (`v0.1.x-pre-release`) — bumped by every `foundry apps deploy`, failed ones included; shown in `list-deployments`. It differs from the catalog version a release produces (see the release-numbering note above).
> - **Display-only `UI_BUILD` const** (if the app keeps one in source) — set it to the version THIS release will produce. It is cosmetic, not the release number.
>
> `foundry apps release --deployment-id` takes the ID of a deployment record from `list-deployments`; the catalog version it produces is not the deployment's number.

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
