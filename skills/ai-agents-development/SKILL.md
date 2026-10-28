---
name: ai-agents-development
description: Build AI agents and knowledge bases for Falcon Foundry apps. TRIGGER when user asks to "create an AI agent", "add a Foundry agent", "build a knowledge base", "give my agent documents", "expose a collection as an agent tool", "expose an API operation to an agent", "put my agent in Charlotte", "expose an agent as a tool for other agents", "delete an agent or knowledge base", runs `foundry agents create`, `foundry agents delete`, `foundry knowledge-bases create`, or `foundry knowledge-bases delete`, or needs help with the `ai.agents` / `ai.knowledge_bases` manifest blocks, agent system prompts, agent input/output formats, agent exposure, or agent tool references. DO NOT TRIGGER for Fusion SOAR workflow YAML — use workflows-development. DO NOT TRIGGER for serverless function handlers — use functions-development. DO NOT TRIGGER for designing a collection schema itself — use collections-development, then return here to wire the collection up as an agent tool.
version: 1.6.0
updated: 2026-10-01
tags: [foundry, ai, agents, knowledge-bases, charlotte, agent-tools]
author: CrowdStrike
license: MIT
compatibility: Claude Code >=1.0
metadata:
  category: ai
---

# Foundry AI Agents and Knowledge Bases

> Create knowledge bases before the agents that reference them, and scaffold both with the CLI.

> **Part of a suite.** If `development-workflow` has not already run, and this is a new app or its first capability, load the `development-workflow` skill first — it owns the CLI prerequisite check, scaffolding order, and manifest coordination.

An **AI agent** is a Foundry artifact that pairs a system prompt with a model, a set of tools, and optional knowledge bases. A **knowledge base** is a named bundle of files the agent can draw on. Both live under a single `ai:` block in `manifest.yml`.

Agents are the only consumer of knowledge bases. A knowledge base on its own does nothing; a collection or API integration becomes agent-usable only when it is exposed as a tool and named in the agent's `tools` list.

## Build Order Is Mandatory

```
1. Collections / API integrations   (if the agent needs them as tools)
2. Knowledge bases                  → foundry knowledge-bases create
3. Agents                           → foundry agents create  (exposure via --expose-* flags)
4. Hand-edit ai.agents[].model / .tools   (no CLI flags exist for these two)
```

**Create knowledge bases first.** `foundry agents create --knowledge-bases X` validates that `X` is already in the manifest and fails the whole command otherwise:

```
agent "my_agent" references knowledge base "X" which is not defined in the manifest
```

The agent directory is rolled back, so nothing is left half-created.

## Naming and Description Constraints

Both artifacts share the CLI's create-time validators, which bite constantly: **names are 5–100 chars** (must start alphanumeric; `kb`, `agent`, `bot` all fail), **descriptions 3–500 chars** when present (`-d "x"` fails), agent names unique among agents and KB names among KBs. KBs are the one asymmetry — `knowledge-bases create` enforces the 5-char floor, but the *manifest* validator accepts a KB name as short as 1 character (and no longer checks the description), so a short name already in the manifest passes `apps validate`. The on-disk directory is a sanitized form of the name (every char outside `[a-zA-Z0-9-_]` → `_`, then leading/trailing `_` trimmed): `--name "Threat Intel Docs"` yields `knowledge-bases/Threat_Intel_Docs/` and records `path: Threat_Intel_Docs`; the manifest resolves files against `path`, never `name`. Full regex/length table: [references/manifest-schema.md](references/manifest-schema.md#shared-validators).

## CLI Scaffolding

Both artifacts support `create` and `delete`. There is no `list` or `edit`. To change an agent beyond the [allowed hand-edits](#allowed-manifest-hand-edits), delete and recreate it, which orphans the deployed copy in AgentWorks (see below).

```bash
# 1. Knowledge base FIRST (--files REQUIRED with --no-prompt; accepts local paths and HTTP(S) URLs).
foundry knowledge-bases create \
  --name "Threat Intel Docs" \
  --description "Runbooks and IOC references" \
  --files ./runbook.md,./iocs.csv \
  --no-prompt

# 2. Agent SECOND, referencing the KB by NAME. Plain json needs no schema; json_with_schema needs
#    --output-schema pointing at a file named output_schema.json (see below).
foundry agents create \
  --name "Detection Triage Agent" \
  --description "Triages detections against the runbooks" \
  --system-prompt ./prompts/triage.md \
  --knowledge-bases "Threat Intel Docs" \
  --output-format json \
  --expose-charlotte-chat \
  --no-prompt
```

`foundry kb create` is a working alias for `knowledge-bases create`.

### Deleting agents and knowledge bases

`delete` removes the manifest entry **and** the artifact's directory. It takes `--name` (matching `manifest.yml`) plus `--no-prompt` (required — an unknown name then fails fast instead of opening a picker):

```bash
foundry agents delete --name "Detection Triage Agent" --no-prompt
foundry knowledge-bases delete --name "Threat Intel Docs" --no-prompt
```

A KB still referenced by an agent cannot be deleted (`cannot delete knowledge base "X": still referenced by agent(s): …`) — delete the agent first, or remove the KB from its `knowledge_bases` list. Empty parent dirs are left behind (harmless). `delete` is local-only: the next deploy leaves the previously deployed agent in Charlotte AI > AgentWorks as an unpublished orphan (recreating under the same name shows two entries), so remove the orphan by hand and match agents at runtime by the IDs in `manifest.yml`, not by name. `foundry apps delete` does remove the platform-side agents.

### The `--system-prompt` value is a path *or* literal text

The CLI reads the value as a file path/URL first and silently falls back to treating it as inline prompt text when that fails — always writing to `agents/<path>/system_prompt.txt`. So a typo'd path (`./prmopts/triage.md`) becomes your entire system prompt with no error. **Always read back `agents/<path>/system_prompt.txt` after creating an agent.** Omitting the flag yields a generic default prompt.

### Input and output formats

| Flag | Allowed values | Default | Paired requirement |
|------|---------------|---------|--------------------|
| `--input-format` | `text`, `json` | `text` | `json` requires `--input-schema`, and the file **must be named `input_schema.json`** |
| `--output-format` | `text`, `json`, `json_with_schema`, `markdown`, `html` | `text` | `json_with_schema` requires `--output-schema`, and the file **must be named `output_schema.json`** (see below) |

Note the asymmetry: `output_format: json` needs **no** schema; only `json_with_schema` does. Omitting the paired schema is caught late at manifest save (`agent "my_agent" input_schema is required when input_format is json`).

> **The schema file name is fixed** — it must be `input_schema.json` / `output_schema.json` in the agent directory (a manifest key naming any other file breaks every CLI command in the app; CLI 2.1.2+ renames the file you pass to `--input-schema`/`--output-schema`), and the bound schema is re-validated against the agent's model at deploy (unsupported keywords like `minimum`/`maximum` surface only in App manager "Show errors"). Full error strings + allowed keywords: [references/manifest-schema.md](references/manifest-schema.md#schema-file-names-are-fixed).

### Keeping a large-JSON agent from bailing to prose or timing out

An agent asked for a big structured object fails two ways: it emits a prose preamble before the JSON (breaking downstream `JSON.parse`), or it runs long enough that the action times out (observed at about 10 minutes). The driver is almost always **output + reasoning volume, not input size** — a large prompt with a small, capped output is fine; a modest prompt asking for an unbounded list is not. Fixes, in order:

1. Impose a hard **output contract** in the system prompt: top-N caps on every array, terse field values, and an explicit "emit only the JSON object — no preamble or explanation before or after it."
2. Lower reasoning volume. A manifest agent has no reasoning setting (see below), so for it rely on 1 and 3. For an agent built in AgentWorks, open its **Agent configuration** page, open the menu, select **Model settings**, and set **Reasoning Effort** lower; a high **Maximum Length** can also cause timeouts.
3. **Split the agent** (per-domain shards + a deterministic merge function) only if a capped single-shot still overflows; a split adds workflow nodes and cost, so exhaust 1–2 first.
4. As a last resort, add a **client-side JSON salvage** in the renderer (drop anything before the first `{` / after the last `}`, then parse) so a stray preamble degrades gracefully instead of blanking the view.

`output_format: json` drops replies that aren't valid JSON, and agents the app creates are app-owned: see [manifest-schema](references/manifest-schema.md#output-format-json-and-long-replies).

## Manifest Structure

Both artifact lists live under one top-level `ai:` key (omitted when empty) — never a top-level `agents:` key. This is a shape sketch, not YAML to copy; the CLI writes the entries:

```yaml
ai:
  agents:           # ai.agents[]: id, name, description, path, model, tools,
    - id: …         #   system_prompt, input/output_format, knowledge_bases (by NAME), exposure
  knowledge_bases:  # ai.knowledge_bases[]: id, name, description, encrypt, path, bare-filename files
    - id: …
```

System prompts live at `agents/<path>/system_prompt.txt`; KB files at `knowledge-bases/<path>/<file>`. Full annotated YAML + on-disk layout: [references/manifest-schema.md](references/manifest-schema.md#full-worked-example).

## Allowed Manifest Hand-Edits

`model` and `tools` have **no CLI flags**. `foundry agents create` always writes `model: ""` and omits `tools`. Configuring them means editing `manifest.yml` directly.

> **This is a narrow, explicit exception to the plugin-wide rule against editing `manifest.yml`** (which protects the CLI-owned `id`, `path`, `entrypoint`, scopes). The complete list of allowed hand-edits: `model`, `tools`, and `exposure` keys under `ai.agents[]`; a schema key naming the wrong file; and the KB rename in [knowledge-bases](references/knowledge-bases.md#changing-a-deployed-knowledge-base). Leave everything else alone.

- **`model`** — **never invent a model ID** (there's no client-side list, so a made-up ID validates locally and fails server-side at deploy). Nothing supplied → leave `""` (platform default). User named one → write it verbatim and note it's only checked at deploy; don't guess a "close enough" ID. Already set → leave it.
- **`tools`** — a list of `<type>:<reference>` strings, not validated client-side. See below.

**No other tuning knobs exist in `manifest.yml`.** Manifest agents have no temperature, maximum length, or reasoning settings (agents built in AgentWorks set those under **Model settings**), and knowledge bases have no chunk size, embedding, similarity, or `top_k`; indexing is server-side. Never add such keys to the manifest. Tell the user those settings aren't available.

## Agent Exposure

`exposure` controls where the agent can be reached from. Unlike `model` and `tools`, it **does** have CLI flags, so prefer setting it at create time:

| Flag | Manifest key | Effect when `true` |
|------|--------------|--------------------|
| `--expose-charlotte-chat` | `charlotte_chat` | Agent is reachable from Charlotte chat |
| `--expose-agent-as-tool` | `agent_as_tool` | Agent can be invoked as a tool by other agents |
| `--expose-workflow-system-action` | `workflows.system_action` | Agent is published as an app-scoped Fusion action |

Three behaviors worth knowing:

- **No flag means unreachable, even by your own app.** With no `--expose-*` flag the `exposure` block is omitted entirely when nothing is exposed (the same as all three `false`) — an absent block is correct, not a missing default to "repair" — and no workflow can call the agent. For an agent used only by this app's automations, pass `--expose-workflow-system-action` alone; it stays out of Charlotte chat. Call it from the app's workflows as `ai_agents.<agent name>`, never a generic LLM action with the prompt copied inline ([workflow-invocation](references/workflow-invocation.md)).
- **`ai_agents.<name>` binds only to an agent in this app's `ai.agents` block.** The alias resolves against that agent's manifest `name`, nothing else. An agent already in the CID but not in this app's manifest (one built in Charlotte AI > AgentWorks, say) has no manifest entry, so `ai_agents.<its name>` resolves to nothing. A workflow can reach such an agent only by its resolved `<uuid>_<cid>` action ID, which differs in every CID, so the workflow won't port. To make it portable, recreate it as a manifest agent (a new, app-owned copy, not a link).
- **An AgentWorks agent must be published before a workflow that references it deploys.** Only an agent's published version is exposed to Falcon Fusion SOAR workflows. Deploy a workflow that references an unpublished agent's `<uuid>_<cid>` and Falcon Fusion SOAR rejects it with `(2015) action <uuid>_<cid> does not exist`. Publish the agent in AgentWorks, then deploy.
- **`--expose-agent-as-tool` requires `--input-schema`.** A calling agent needs a declared signature; the check runs before any files are written (`--input-schema is required when --expose-agent-as-tool is set`), and the same rule is enforced on the manifest, so hand-adding `agent_as_tool: true` without an `input_schema` breaks every subsequent CLI command in the app.
- **Nothing else here is validated client-side.** The CLI ignores unknown keys, so a misspelled `exposure` key raises no error and vanishes on the next CLI save.

Adding or removing exposure after create means editing `manifest.yml`; there is no `agents edit`.

## Agent Tool References

Each `tools` entry is `<type>:<reference>`. The artifact must be exposed on its own side *and* named here — one without the other produces an agent that silently cannot call it, with no error at validate or deploy.

| Target | Entry |
|--------|-------|
| App collection | `action:collections.<collection_name>.<Operation>` |
| Agent runtime collection | `action:mcp/gce/collections:collections:generic:<Operation>` |
| API integration | `action:mcp/gce/integration:<integration id>~<hash>` (its platform tool ID) |

Any other form fails the whole deploy, usually with a bare `500`. A concrete `tools` entry (note the required `action:` prefix) looks like:

```yaml
tools:
  - action:collections.triage_notes.CreateObject
```

An API-integration tool ID exists only after the integration deploys, so deploy without that entry, look the ID up, then add it. See [manifest-schema](references/manifest-schema.md#tool-reference-format).

Valid collection operations — exact casing required:

`CreateObject`, `GetObject`, `DeleteObject`, `ListObjects`, `SearchObjects`

The generic collection is a scratch collection the platform creates for the agent at runtime. Use it for agent working memory; use a named app collection when the data must outlive the agent or be readable by other capabilities.

Exposing the target artifact on its own side — the collection `--agent-tools-expose` flag and the API-integration `x-cs-operation-config.agent_tools` block — is covered in [references/manifest-schema.md](references/manifest-schema.md#exposing-an-artifact-as-an-agent-tool) (and owned by `collections-development` / `api-integrations`). No other artifact type supports agent-tool exposure, and no `tools` form reaches a function or workflow. To pair an agent with a function, have a workflow call `ai_agents.<name>`, then a function action ([workflow-invocation](references/workflow-invocation.md)).

## Invoking an Agent from Code

Charlotte chat and the app's own workflows (`ai_agents.<agent name>`) invoke an agent for you. Calling the agent definition API yourself (from a function or the UI) has one thing the API reference does not spell out:

- **`credit_cents_limit` has an undocumented floor of `100`.** Lower values are rejected with a `400`, so budget in whole credits.

## Common Pitfalls

| Symptom | Cause | Fix |
|---------|-------|-----|
| `must be at least 5 characters long` | Name under 5 chars at create | Lengthen the name; `kb` and `agent` are both too short |
| `invalid value for --description` | Description under 3 chars | Write a real description or omit `-d` |
| `references knowledge base "X" which is not defined` | Agent created before its KB | Create the KB first, then re-run the agent command |
| `flag --files is required when --no-prompt flag is used` | KB create without `--files` | KBs must ship at least one file |
| `input_schema is required when input_format is json` | Format/schema mismatch | Pass the paired `--input-schema` |
| `--input-schema is required when --expose-agent-as-tool is set` | Agent exposed as a tool with no declared signature | Add `--input-schema`, or drop the exposure flag |
| `input_schema is required when exposure.agent_as_tool is true` | Hand-added `agent_as_tool` to an agent with no input schema | Add `input_schema` to that agent, or set the flag back to `false` |
| `flag --name is required when --no-prompt flag is used` | `delete` without `--name` | Pass the artifact name as it appears in `manifest.yml` |
| `still referenced by agent(s): Y` | Deleting a KB an agent still lists | Delete the agent first, or remove the KB from its `knowledge_bases` |
| `file <name> already exists` | Re-running KB create over existing files | Delete the file or the KB directory first. As a deploy `409`: see [knowledge-bases](references/knowledge-bases.md) |
| System prompt is a file path string | Typo'd `--system-prompt` path fell back to inline text | Read back `agents/<path>/system_prompt.txt` |
| KB file missing after deploy | The packager ignores any path containing `svg` (any case), not just `.svg` files | Rename it; convert SVGs to PNG |
| `must be a filename only, not a path` | Subdirectory in a KB `files` entry | Flatten — KB directories cannot nest |
| Agent cannot call an exposed collection | Exposed but not listed in `tools` | Both sides are required |
| Bare `500` from deploy, agent has `tools` | An entry isn't in a form from Agent Tool References | Fix the entry |
| `output_schema must be "output_schema.json"` (or `input_schema …`), or `output schema is required when using JSON format` at deploy | Schema file misnamed, or an inline schema | Name it `output_schema.json` / `input_schema.json` under `agents/<path>/`; see [manifest-schema](references/manifest-schema.md#schema-file-names-are-fixed) |
| Deploy `Failed` with `output schema … uses unsupported schema keyword …` in App manager "Show errors" | Keyword the agent's model provider rejects (`minimum`/`maximum`, for example) | Drop it, state the constraint in `description`; see [manifest-schema](references/manifest-schema.md#schema-file-names-are-fixed) |
| `model <id> does not support structured output` at deploy | `json_with_schema` on a model without it (newer Claude models such as Opus 4.7+ and Sonnet 5+, and Nemotron) | Use `output_format: json` for that agent, or a model that supports it (`openai.gpt-5.5` does) |
| Two agents with the same name in Charlotte AI > AgentWorks | `agents delete` + redeploy left the old platform-side agent unpublished | Delete the orphan in the console; match agents by the IDs in `manifest.yml`, not by name |
| Deploy fails with `model <id> is not available`, and still fails after setting `model: ""` | Model IDs are CID-specific, and a failed deploy leaves the pinned model on the platform-side agent | Pick an ID from `/agentic-studio/queries/models/v1` in that CID, or remove the agent and create it again |
| `400` when invoking an agent with `credit_cents_limit` | Value below the undocumented floor | Pass `100` or more |
| Deploy fails with Falcon Fusion SOAR `(2015) action <uuid>_<cid> does not exist` | Workflow references an AgentWorks agent that isn't published yet | Publish the agent in Charlotte AI > AgentWorks first, then deploy the referencing workflow. For the other cause of 2015, see [workflow-invocation.md](references/workflow-invocation.md) |
| Agent's JSON won't `JSON.parse`, or the action times out (observed at about 10 minutes) | Prose preamble before the JSON, or output/reasoning volume too high (not input size) | Output contract (top-N caps, terse fields, "no preamble"); for an AgentWorks agent, lower **Reasoning Effort** in **Model settings**; split only if still overflowing; client-side JSON salvage as fallback |

## Reading Guide

| Task | Reference |
|------|-----------|
| KB sourcing, encryption, packaging, changes after deploy | [references/knowledge-bases.md](references/knowledge-bases.md) |
| Full field-by-field schema, every validation error string | [references/manifest-schema.md](references/manifest-schema.md) |
| Product docs: Falcon Foundry AI capabilities overview | [AI Capabilities](https://docs.crowdstrike.com/access?ft:originId=ce325bab) |
| Product docs: agents via the CLI | [AI agents (Foundry CLI)](https://docs.crowdstrike.com/access?ft:originId=d82146c3) |
| Product docs: knowledge bases via the CLI | [Knowledge bases (Foundry CLI)](https://docs.crowdstrike.com/access?ft:originId=l69669e4) |

## Related Skills

- `collections-development` — schema design for collections used as agent tools
- `api-integrations` — OpenAPI spec work, including `x-cs-operation-config`
- `workflows-development` — Fusion workflows that call the agent as `ai_agents.<agent name>`
- `security-patterns` — prompt-injection surface review before exposing an agent to Charlotte
- `debugging-workflows` — deploy and validation failures
