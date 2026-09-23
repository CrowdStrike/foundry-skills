# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [1.7.0] - TBD

### Added

- **`ai-agents-development` skill** — Covers the two new Foundry AI capabilities, `foundry agents` and `foundry knowledge-bases` (alias `kb`), which land under a single top-level `ai:` block as `ai.agents` and `ai.knowledge_bases`. Both support `create` and `delete`; there is no `list` or `edit`. Documents the full manifest schema, every validation error string, the input/output format matrix, and the agent tool reference formats. Two references carry the detail: [knowledge-bases.md](skills/ai-agents-development/references/knowledge-bases.md) for file sourcing, encryption, and deploy packaging, and [manifest-schema.md](skills/ai-agents-development/references/manifest-schema.md) for the field-by-field reference.
- **Agent exposure flags** — `agents create` takes `--expose-charlotte-chat`, `--expose-agent-as-tool`, and `--expose-workflow-system-action`. The `exposure` block is a pointer with `omitempty`, so it is omitted from the manifest entirely when nothing is exposed — an absent block is correct, not a missing default, and means the same as all three `false`. `--expose-agent-as-tool` requires `--input-schema`, since a calling agent needs the callee's signature; the rule is enforced both pre-flight (`--input-schema is required when --expose-agent-as-tool is set`) and on every manifest load (`input_schema is required when exposure.agent_as_tool is true`), so hand-adding the switch without a schema breaks every subsequent CLI command in that app.
- **Agent and knowledge base deletion** — `agents delete` and `knowledge-bases delete` remove the manifest entry and the artifact directory, taking `--name` plus the standard `--no-prompt` like every other Foundry command. A knowledge base still referenced by an agent is protected: `cannot delete knowledge base "X": still referenced by agent(s): Y`. The manifest is saved before the directory is removed, so a failed removal reports an orphaned directory by path rather than losing the manifest edit. The CLI guard adds a confirmation step before an irreversible delete, matching the existing create-time name confirmation.
- **Agent tool exposure for collections** — `collections-development` now documents `--agent-tools-expose` and the `agent_tools_integration: {exposed: true}` block it writes. Exposure is only half the wiring: the agent must also name each operation in its own `tools` list as `collections.<name>.<Operation>`, using one of `CreateObject`, `GetObject`, `DeleteObject`, `ListObjects`, `SearchObjects`. Neither half alone errors — it just yields an agent that silently cannot reach the data.
- **Agent tool exposure for API integrations** — `api-integrations` now documents `x-cs-operation-config.agent_tools`, a sibling of the existing `workflow` block, with `name`, `description`, and `expose_to_agent`. The agent references the operation as `api_integrations.<integration>.<agent_tools.name>` — not the `operationId` and not the URL path. `adapt_spec_for_foundry.py` now flags a misplaced `expose_to_agent` the same way it already flagged `expose_to_workflow`, and the skill router blocks on either.
- **Build-order, `--files`, and exposure enforcement in the CLI guard** — `foundry agents create --knowledge-bases X` fails outright when `X` is not already in the manifest, so the guard warns before the round trip is wasted. `foundry knowledge-bases create` without `--files` is rejected by the CLI under `--no-prompt`, and `--expose-agent-as-tool` without `--input-schema` is rejected before any files are written; the guard catches both. `mkdir agents/` and `mkdir knowledge-bases/` are blocked alongside the other app directories.

### Changed

- **`development-workflow` dependency order** is now Collections → Functions → Knowledge bases → Agents → Workflows → UI, with scaffolding commands for both new capabilities in Step 5.
- **A narrow carve-out to the "never edit manifest.yml" rule.** `ai.agents[].model` and `.tools` have no CLI flags — `agents create` always writes `model: ""` and omits `tools`. Editing the manifest is the only way to set them. Both the orchestrator and the new skill scope the exception to those two keys so it does not erode the rule that protects `id`, `path`, and `entrypoint`. Agent `exposure` is explicitly *not* part of the carve-out; it has flags.
- **Knowledge base name and description validation is asymmetric.** The manifest validator now accepts a one-character KB name and no longer checks the description at all — the AI platform imposes no restriction, so the CLI stopped adding one. The `kb create` flag validators still enforce name 5–100 and description 3–500, so the looser rules only surface for a manifest you inherit or hand-write.
- **Corrected the skill count in AGENTS.md** — it claimed 9 and had been stale for several releases; the repo now ships 12.

## [1.6.0] - TBD

### Added

- **Attributing AgentWorks executions to an agent** — `functions-falcon-api` (advanced-patterns) now documents that agentic-studio spans carry no agent id or version id: `/queries/spans/v1` filters only on `span_type`, `trace_id`, `status`, `name`, `duration_ms`, `start_time`, and an `aw_agent` span identifies its agent through `attributes.aw_agent.definition.name` plus `aw_agent.invocation_id`. So a `attributes.aw_agent.agent_id` filter matches nothing, per-version counting isn't possible from spans, and matching by name is ambiguous because AgentWorks does not enforce unique agent names per CID (unlike Foundry apps and workflows). To observe a run, fetch spans by the invocation's `ai_trace_id`.
- **App logo lifecycle** — `development-workflow`'s [advanced-patterns reference](skills/development-workflow/references/advanced-patterns.md) now documents the manifest `logo:` field (a small square PNG such as `images/logo.png`, like the `foundry-sample-*` apps): the App Catalog icon is set from it only on an app's *first* deploy, so adding or changing it in a later patch does not update the icon (it keeps the generated text avatar). A deploy whose diff is only the logo or other manifest metadata, with no artifact, fails with `no deployable artifacts found` and there is no `--force`. It also notes that `foundry apps delete --local-files` deletes the local manifest and app directory (omit the flag to delete only the cloud app) and that a UI page showing the logo should inline the SVG, since the sandboxed iframe cannot load a file from outside the page directory. `debugging-workflows` gains a matching Quick Diagnosis branch for `no deployable artifacts found`.
- **Installable from the OpenAI/Codex, Cursor, and GitHub Copilot marketplaces.** Beyond the Anthropic marketplace, the plugin is now published to the OpenAI/Codex curated CLI marketplace (`codex plugin add crowdstrike-falcon-foundry@openai-api-curated`; ChatGPT-authenticated Codex installs via `/plugins`), the Cursor marketplace, and the GitHub Copilot (awesome-copilot) directory. The skills-only bundle now ships the square interface icon the OpenAI directory requires, and the README install table links each live listing.
- **FDK `Request` field reference** in `functions-development` — `body`, `params.query`, `params.header` (both `Dict[str, List[str]]`), `context`, `method`, `url`, `access_token`, `trace_id`, `fn_id`, `fn_version`, `files`. There is no `request.query`, and `request.params` is a dataclass without `.get()`; both mistakes only surface at runtime in the deployed function. The `functions-falcon-api` examples that used `request.params.get(...)` are corrected.
- **Adding a handler to an existing function** — no CLI command does it. `functions-development` now documents editing that function's `handlers:` list (`name`, `method`, `api_path`) as an explicit carve-out to the no-manifest-edits rule, scoped the same way as the `ai.agents[].model` / `.tools` exception.
- **`--max-exec-duration-seconds` and `--max-exec-memory-mb`** in the `functions create` scaffolding example, so timeouts and memory are set at create time instead of by hand-editing the manifest.
- **Charlotte AI AgentWorks (`/agentic-studio/*`) from functions** — `functions-falcon-api` documents the Uber-class route override and adds the `charlotte-ai-agent-definition` scopes to the reference table; `api-integrations` blesses a minimal hand-written spec for Falcon API families FalconPy does not wrap, since the Falcon swagger is not downloadable without console auth.
- **Invoking an agent from code** in `ai-agents-development` — `credit_cents_limit` has an undocumented floor of `100` (a `400` below that). Links to the now-public product docs for AI capabilities, agents, and knowledge bases.
- **No Web Storage in UI pages and extensions** — the iframe is sandboxed without `allow-same-origin`, so `localStorage` / `sessionStorage` throw. `ui-development` covers in-memory state, collections, and a `try/catch` wrapper for legacy code, plus following the console theme via the `theme-light` / `theme-dark` class foundry-js sets on `<html>`.
- **Deploy diagnostics** — a `Failed` deployment's reason is only in the console (App manager > app > "Show errors (N)"), `foundry apps validate` fails with `deployment is currently in progress` while a deploy runs, and a FalconPy call from a deployed-but-not-installed app returns `403 app is not installed`. Added to `development-workflow` Step 7 and `debugging-workflows`.

### Changed

- **Minimum CLI version bumped to 2.1.0** — The session-start hook now warns users on CLI 2.0.x and offers to upgrade. CLI 2.1.0 added `foundry functions exec`, `test`, and `logs`, and CLI 2.1.1 fixed non-interactive output for `actions view` and `triggers view` when multiple actions match a fuzzy name filter.
- **`action_search.py` is now a convenience, not a workaround** — With CLI 2.1.1, `foundry workflows actions view --name "..." --no-prompt` lists multiple matches non-interactively instead of dropping into a picker. The bundled `action_search.py` remains useful for working without a manifest directory, but the warning framing it as a required fallback is removed.
- **`json_with_schema` is no longer the recommended agent output format.** With CLI 2.1.1 an agent created with `--output-format json_with_schema --output-schema file.json` fails every deploy with `output schema is required when using JSON format`, even with a valid schema file. `ai-agents-development` now scaffolds with `--output-format json`, describes the shape in the system prompt, and validates in the consumer.
- **FalconPy clients must be constructed inside the handler.** Context auth only has a request token while a request is being handled, so a module-scope `Alerts()` / `APIHarnessV2()` / `CustomStorage()` returns `401` on every call. Stated explicitly in `functions-development`, `functions-falcon-api`, and the collections Python example, and added to the debugging tables.
- **`foundry agents delete` is local-only.** Redeploying does not remove the platform-side agent; it stays under Charlotte AI > AgentWorks as an unpublished orphan and a recreated agent shows up twice. `ai-agents-development` says to delete the orphan in the console and to match agents by name prefix or manifest IDs.
- **`foundry apps create` always makes a subdirectory** named after the app, spaces included. `development-workflow` explains moving `manifest.yml` to the repo root when converting an existing repository.
- **Patch releases update an installed app in place**; a reinstall is only needed to reach an API integration's credential form again.

### Fixed

- **`--system-prompt` silently accepts a bad path.** The CLI tries the value as a file path or URL and falls back to treating it as inline prompt text, so a typo becomes the agent's entire instruction set with no error. The skill tells you to read back `agents/<path>/system_prompt.txt` after every create, and the CLI guard repeats it.
- **`.svg` files in a knowledge base are silently dropped at deploy.** The packager unconditionally ignores SVGs, so the file passes `foundry apps validate` and then is absent from the bundle — the agent behaves as if it were never added. Documented alongside the shared 25 MB package cap, which a large PDF corpus can exhaust on its own.
- **`api-integrations create --description` is capped at 50 characters** (`input must be at most 50 characters long`); the skill insisted on the flag without stating the limit.
- **API integration requests are schema-validated before proxying.** Query values must be scalars typed per the spec (`{"params": {"query": {"limit": 1}}}`), not the string arrays the foundry-js `Params` type and the FDK's `params.query` suggest; otherwise `400 request failed schema validation`. Documented in `api-integrations` and its calling-patterns reference.
- **Collection descriptions with commas pass `collections create` and fail `apps validate`.** `collections-development` now says to check the allowed character set before creating.
- **Redeploying a changed collection schema does not update an existing collection.** `collections-development` says to ship top-level `additionalProperties: true` when fields may be added later and to treat breaking schema changes as a new collection.
- **A failed agent deploy keeps the pinned model.** `ai-agents-development` adds the `model <id> is not available` pitfall: model IDs are CID-specific, and after the failure `model: ""` alone does not recover; pick an available ID or recreate the agent.
- **`foundry functions exec` behaviors** — `undeployed local changes detected` fires on any file under the function directory, not just the handler; platform API calls from the handler return `403 app is not installed` until the app is released and installed; and `exec` has been observed to hang for many minutes after the function returned a non-2xx payload status — wrap it in `timeout` and fall back to `exec status <id>`.
- **Function manifest example used `path:` for handler routes**; the field is `api_path`.

## [1.5.0] - 2026-08-19

### Added

- **Install instructions for five AI coding assistants** — Claude Code, Codex, Copilot CLI, Cursor, and Antigravity CLI each get a verified marketplace command. A collapsible table covers local clones for testing a branch. Claude Code, Copilot CLI, and Cursor take `--plugin-dir`; Antigravity CLI takes `agy plugin install`. Codex has no such flag and reads skills from `~/.agents/skills/` instead.
- **`fusion-redirect` skill** — Declines a standalone Falcon Fusion workflow request (a trigger plus actions that already exist) and points to the sibling Falcon Fusion plugin. The advice previously lived in `development-workflow`'s body, where only the skill router hook could surface it, so it never fired on assistants that don't run hooks. As its own skill it needs no hook. When the Falcon Fusion plugin is installed, that plugin's skill takes the request instead.
- **Agent Plugins manifest** — A root `plugin.json` following the [Agent Plugins](https://agent-plugins.org) 1.0.0 spec, so any conforming client recognizes the repo as a plugin. CI validates it and `release.sh` bumps its version with the rest.
- **Function execution, testing, and debugging (CLI 2.1.0+)** — The `functions-development` skill now covers `foundry functions exec`, `test`, and `logs`. Documents the deploy-first rule (exec and test run the deployed artifact, not local code), request-data confirmation before exec, handler disambiguation from the manifest, and the `tests.yml` schema for integration test cases. Adds a code-review checklist for logging, secrets, and schema coverage. The CLI guard enforces `--no-prompt` on the new commands. Users on CLI 2.0.x are told why the commands are unavailable and offered an upgrade.
- US-3 cloud region to the cloud-region documentation: added `us-3` to the `FOUNDRY_CLOUD_REGION` value lists (headless-operation reference, e2e-testing env var table) and the multi-cloud deployment section. Foundry CLI 2.0.2 added US-3 support; the base URL (`api.us-3.crowdstrike.com`) is in FalconPy as of v1.6.4.

### Changed

- **NGSIEM `start_search` keyword guidance updated for FalconPy 1.6.5** — The `search=` keyword remains the recommended approach (works on all versions), but the explanation now notes that `body=` was fixed in FalconPy 1.6.5 ([#1497](https://github.com/CrowdStrike/falconpy/pull/1497)). Since FalconPy is unpinned, `search=` is still the safe default.

### Fixed

- **`connection issue` on tenant commands** — In a workspace-scoped sandbox the CLI cannot write `~/.config/foundry/token.json`, where it keeps its short-lived access token. It reports only the symptom, which sent agents investigating networks and credentials. The debugging skill now explains that the token refresh is expected and that the fix is granting write access to that directory. Observed on Codex.
- **Three commands that reject `--no-prompt`** — `foundry version`, `apps list`, and `apps list-deployments` fail with `unknown flag`. This is CLI behavior, not assistant-specific. Two of the three are in the prerequisite check, so "always add `--no-prompt`" broke the first thing an agent runs.
- **OpenAPI adapter dependencies without hooks** — Claude Code's skill router runs `adapt_spec_for_foundry.py` automatically. Copilot CLI, Cursor, and Antigravity CLI don't, so their users invoke it directly. It needs `pyyaml`, which a bare `pip install` cannot supply on Homebrew or system Pythons (PEP 668). The API integrations skill now documents a virtualenv setup.
- **Sub-skill routing survives a single-entry-point install** — `development-workflow` now says where sub-skills live on disk (`../<name>/SKILL.md`) and what to do when a capability request lands on the orchestrator: read the sub-skill first, then go straight to the CLI command if `manifest.yml` exists. The orchestrator's trigger description is unchanged, so a fully-registered install routes as before.
- **Sub-skills point back to the orchestrator** — Every capability sub-skill now links to `development-workflow` near the top, so an assistant without routing hooks that picks a sub-skill directly still finds the CLI prerequisite check and scaffolding order. Previously only `e2e-testing` mentioned it, and only in a footer.

## [1.4.1] - 2026-08-07

### Fixed

- **Replaced deprecated Detects API with Alerts API** — The `functions-falcon-api` skill now directs users to `from falconpy import Alerts` with `query_alerts_v2()` / `get_alerts_v2()` instead of the deprecated `Detects` class, which returns 405 Method Not Allowed. Filter by `product:'detections'` to scope results to detections only.

## [1.4.0] - 2026-07-31

### Added

- **LogScale query recipe** — Complete `NGSIEM.start_search()` / `get_search_status()` pattern for querying LogScale from Foundry functions. Documents the `search-all` repository requirement (specific repo names cause 403), the `search=` keyword requirement (FalconPy documents `body=` but its guard never honors it — see [falconpy#1491](https://github.com/CrowdStrike/falconpy/issues/1491)), the `resources` vs `body` response-key asymmetry between `start_search` and `get_search_status`, and clarifies that `NGSIEM` is the query class while `FoundryLogScale` is ingestion-only. Adds `humio-auth-proxy:read` to the scope reference table, verified against a live CID.
- **Function I/O schema requirements** — Functions called from workflows must be created with `--input-schema` and `--output-schema`. Schemas bind only at creation time; the CLI writes `null` for both without these flags, even when `--wf-expose` is set. Functions without a response schema produce no visible output in Fusion actions.
- **Workflow deletion warning** — Documents that deleting a workflow and recreating it with the same name causes `409 name must be unique for an app` followed by `400 dependent artifact failed`, blocking all further deploys. Recovery requires a fresh app.
- **Cross-plugin redirect to the Falcon Fusion plugin** — The development-workflow orchestrator now recognizes standalone Falcon Fusion workflow requests (trigger + actions, no UI/function/collection/API integration) and advises the `crowdstrike-falcon-fusion` plugin instead of scaffolding a Foundry app. Adds `detect_fusion_redirect.py` classifier with unit tests.
- **GraphQL APIs use case** — Integrate GraphQL APIs (Falcon Identity Protection, GitHub, Snyk) into Foundry apps using FalconPy or HTTP POST. Covers zero-arg auth for Falcon GraphQL endpoints and the security tradeoff of env vars vs API integrations for third-party APIs.
- **`scripts/action_search.py`** — API-based action discovery script that works in headless/CI environments where the CLI's interactive `actions view` prompt fails. Uses FalconPy with FQL fuzzy matching and prints action IDs with `version_constraint` values.
- **CLI guard for `actions view` / `triggers view`** — Hook now catches missing `--no-prompt` on these commands to prevent TTY hangs.
- **`foundry apps list` in prerequisite check** — New CLI 2.0.2 command that lists all deployed apps on the CID from any directory. Added to Step 3 to help avoid name collisions.
- **Collection description validation constraints** — Documents the 3–500 character length limit, alphanumeric-start requirement, and allowed character set for collection descriptions.
- **Function logs in testing-patterns reference** — Added function logs (viewing in UI and Advanced Event Search) to the reference table entry for testing patterns.
- **Query parameter type matching for API integrations** — Documents that `apiIntegration().execute()` types params as `Record<string, unknown>`, so a quoted number like `limit: '25'` passes type-checking and fails server-side with `got string want integer`. The extension still renders, so the failure reads as an API or credential error rather than a code bug.
- **Content regression tests** — `tests/test_skill_content.py` guards critical documentation (LogScale recipe, schema requirements, workflow deletion warning) against accidental removal.

### Changed

- **Fusion redirect names the plugin, not the repo** — The cross-plugin advisory pointed users at the `fusion-skills` GitHub repo. It now names the plugin (`crowdstrike-falcon-fusion`) with the `/plugin install` command and the marketplace link, since most users install from the marketplace and a repo detour is confusing to anyone unfamiliar with GitHub. `detect_fusion_redirect.py` reports `target` as `crowdstrike-falcon-fusion` / `crowdstrike-falcon-foundry` rather than the repo names.
- **Gemini CLI → Antigravity CLI** — Google transitioned Gemini CLI to Antigravity CLI (binary: `agy`). Updated README with new command, skills paths (`~/.gemini/antigravity-cli/skills/` for user scope, `.agents/skills/` for workspace scope). Removed `GEMINI.md` since we never shipped Gemini CLI support; Antigravity reads `AGENTS.md` directly.
- **Codex docs link** — Updated from `developers.openai.com/codex/skills` to `learn.chatgpt.com/docs/build-skills`.
- **Renamed Python scripts to snake_case** — `scripts/adapt-spec-for-foundry.py` → `adapt_spec_for_foundry.py` and `scripts/test-adapt-spec.py` → `test_adapt_spec.py`, matching the repo's `snake_case` lint convention and allowing the test to import the module directly. The PreToolUse hook and all skill docs reference the new names; no behavior changed. If you invoked the old path directly in your own tooling, update it to the underscore name.

### Fixed

- **Fusion redirect was never wired to a hook** — `detect_fusion_redirect.py` shipped as a standalone script that nothing invoked, so its verdict never reached the agent at runtime. The `fusion-redirect` eval passed only 1 of 5 trials: in three runs the agent declined to scaffold an app but never mentioned the Fusion plugin, and in one it scaffolded an app anyway. The skill router now runs the classifier on Foundry-matched prompts and injects an explicit redirect advisory when it fires. The advisory in `development-workflow` also states that naming the plugin is *required output* — declining to scaffold is only half a redirect — and that hand-writing the workflow YAML defeats the purpose, since the Fusion plugin discovers real action IDs, validates against the platform schema, and imports to the CID.
- **Fusion redirect classifier mishandled negation** — `detect_fusion_redirect.py` matched app-capability keywords without regard to negation, so a prompt saying "no Foundry app, no UI, no functions" registered `UI` and `Foundry app` as *requests* for those capabilities and suppressed the redirect. Standalone Fusion workflow requests that explicitly ruled out app capabilities — the clearest possible case for redirecting — were the ones most likely to be kept in this plugin. Negated spans are now stripped before app signals are matched, and the verdict reports `negated_app_signals` so the reasoning stays visible. Caught by the `fusion-redirect` eval, which failed 0/5 trials before this fix.
- **Removed "delete and re-create" advice** — The old guidance for fixing missing `workflow_integration` said to delete and recreate the function. This is technically correct (schemas only bind at creation), but was misleading about workflows: you must never delete and recreate a *workflow* to refresh a binding. Both skills now give consistent guidance — recreate the function, update the workflow YAML reference in place.
- **Action discovery guidance** — Updated all `actions view` examples to include `--no-prompt` and pointed to `action_search.py` as the primary fallback. The CLI ignores `--no-prompt` for these commands (tracked upstream), so the script is the reliable path.
- **Alert and detection query routing (population vs. enrich)** — The orchestrator and workflows skills now distinguish two cases. Fetching a *population* the workflow doesn't already have ("summarize all high-severity alerts") goes to a source-of-truth API — a native platform action (e.g. Cases → Search Cases) first, or a FalconPy `Alerts`/`Detects` function when none fits — since an Event Query against NG-SIEM can silently return nothing (repo contents are connector-dependent). *Enriching* a detection the workflow already holds (query by its ID) stays an Event Query, as does historical/aggregate telemetry. New reference [event-query-vs-api.md](skills/workflows-development/references/event-query-vs-api.md); the functions-falcon-api example keeps the verified `severity_name` + `created_timestamp` FQL filter.
- **Removed `apps delete` workaround** — The 500/stuck-in-Deleting issue is fixed in CLI 2.0.2. Removed guidance about using Falcon App Manager UI as fallback.
- **Corrected "commands that work from anywhere"** — Replaced `foundry apps list-deployments` (which requires a manifest) with `foundry apps list` (which actually works from any directory).
- **Fixed invalid error-handling references in workflow advanced-patterns** — Removed non-existent `onError` blocks, `maxConcurrency`, and automatic retries. Replaced with the real mechanisms: conditional routing on `Workflow.Execution.Errors`, loop `continue_on_partial_execution`, and sequential loops for stateful actions.

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
- **`.cursorrules`** — Redirect for Cursor.
