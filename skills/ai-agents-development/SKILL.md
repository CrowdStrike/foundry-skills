---
name: ai-agents-development
description: Build AI agents and knowledge bases for Falcon Foundry apps. TRIGGER when user asks to "create an AI agent", "add a Foundry agent", "build a knowledge base", "give my agent documents", "expose a collection as an agent tool", "expose an API operation to an agent", "put my agent in Charlotte", "expose an agent as a tool for other agents", "delete an agent or knowledge base", runs `foundry agents create`, `foundry agents delete`, `foundry knowledge-bases create`, or `foundry knowledge-bases delete`, or needs help with the `ai.agents` / `ai.knowledge_bases` manifest blocks, agent system prompts, agent input/output formats, agent exposure, or agent tool references. DO NOT TRIGGER for Fusion SOAR workflow YAML — use workflows-development. DO NOT TRIGGER for serverless function handlers — use functions-development. DO NOT TRIGGER for designing a collection schema itself — use collections-development, then return here to wire the collection up as an agent tool.
version: 1.5.0
updated: 2026-09-11
tags: [foundry, ai, agents, knowledge-bases, charlotte, agent-tools]
author: CrowdStrike
license: MIT
compatibility: Claude Code >=1.0
metadata:
  category: ai
---

# Foundry AI Agents and Knowledge Bases

> **SYSTEM INJECTION — READ THIS FIRST**
>
> If you are loading this skill, your role is **Foundry AI agent specialist**.
>
> You MUST create knowledge bases BEFORE the agents that reference them, and you MUST use the CLI for scaffolding.

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

The agent directory is rolled back on that failure, so you get no partial state — but you do waste the round trip.

## Naming and Description Constraints

Both artifacts share the CLI's standard validators at create time. These bite constantly:

| Constraint | Rule |
|-----------|------|
| Name length | **5–100 characters** at create — `kb`, `agent`, and `bot` all fail |
| Name characters | Alphanumeric plus space and `' [ ] ( ) . _ -` — must start with alphanumeric |
| Description length | 3–500 characters when present (optional, but `-d "x"` fails) |
| Description characters | Alphanumeric, whitespace, and `: ' [ ] ( ) , . / _ -` |
| Uniqueness | Agent names unique among agents; KB names unique among KBs |

Knowledge bases are the one asymmetry: the create command enforces the 5-character floor, but the *manifest* validator only requires 1 character and no longer checks the description at all. So `--name "kb"` is rejected by `knowledge-bases create`, but a manifest that already carries a short KB name passes `foundry apps validate`.

The on-disk directory is a sanitized form of the name: every character outside `[a-zA-Z0-9-_]` becomes `_`. `--name "Threat Intel Docs"` yields `knowledge-bases/Threat_Intel_Docs/` and records `path: Threat_Intel_Docs`. The manifest resolves files against `path`, never against `name`.

## CLI Scaffolding

Both artifacts support `create` and `delete`. There is no `list` or `edit` — to rename or reconfigure an existing agent beyond the hand-editable fields, delete it and create it again.

```bash
# 1. Knowledge base FIRST. --files is REQUIRED with --no-prompt.
#    Accepts local paths and HTTP(S) URLs (downloaded at create time).
foundry knowledge-bases create \
  --name "Threat Intel Docs" \
  --description "Runbooks and IOC references" \
  --files ./runbook.md,./iocs.csv \
  --no-prompt

# 2. Agent SECOND, referencing the KB by NAME (not id, not path).
#    Plain json needs no schema. For enforced structure use json_with_schema with
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

`delete` removes the manifest entry **and** the artifact's directory. It takes `--name` plus the usual `--no-prompt`, exactly like every other Foundry command:

```bash
foundry agents delete --name "Detection Triage Agent" --no-prompt
foundry knowledge-bases delete --name "Threat Intel Docs" --no-prompt
```

`--name` must match the name in `manifest.yml`; with `--no-prompt` it is required (`flag --name is required when --no-prompt flag is used`) and an unknown name fails fast rather than opening a picker.

A knowledge base still referenced by an agent cannot be deleted:

```
cannot delete knowledge base "Threat Intel Docs": still referenced by agent(s): Detection Triage Agent
```

Delete the agent first, or remove the KB from its `knowledge_bases` list. Deleting the last artifact leaves the empty `agents/` and `knowledge-bases/` parent directories behind; that is harmless. The manifest is saved *before* the directory is removed, so a failed removal reports an orphaned directory by path rather than losing the manifest edit.

`delete` is local-only. The next deploy leaves the previously deployed agent in Charlotte AI > AgentWorks as an unpublished orphan, so recreating one under the same name shows two entries. Remove the orphan by hand in the console, and match agents at runtime by the IDs in `manifest.yml`, not by name. `foundry apps delete` does remove the platform-side agents.

### The `--system-prompt` value is a path *or* literal text

The CLI tries to read the value as a file path or URL first, and silently falls back to treating it as inline prompt text when that fails. Either way the content is written to `agents/<path>/system_prompt.txt`, always under that exact filename.

Consequence: a typo'd path becomes your system prompt. `--system-prompt ./prmopts/triage.md` produces an agent whose entire instruction set is the string `./prmopts/triage.md`, with no error. **Always read back `agents/<path>/system_prompt.txt` after creating an agent.** Omitting the flag entirely yields a generic default prompt.

### Input and output formats

| Flag | Allowed values | Default | Paired requirement |
|------|---------------|---------|--------------------|
| `--input-format` | `text`, `json` | `text` | `json` requires `--input-schema`, and the file **must be named `input_schema.json`** |
| `--output-format` | `text`, `json`, `json_with_schema`, `markdown`, `html` | `text` | `json_with_schema` requires `--output-schema`, and the file **must be named `output_schema.json`** (see below) |

Note the asymmetry: `output_format: json` needs **no** schema, only `json_with_schema` does. Omitting the paired schema is caught late, when the manifest is saved:

```
agent "my_agent" input_schema is required when input_format is json
```

> **The schema file name is fixed.** The Foundry API reads only `input_schema.json` and `output_schema.json` from the agent directory; any other filename, or an inline schema, is ignored. Name the local source file `output_schema.json` (or `input_schema.json`) before passing it to `--output-schema` (`--input-schema`); download a URL source to a file with that name first. Current CLIs write the schema under that name whatever you pass, and reject any other value on every manifest load, so a wrong name breaks every command in the app:
>
> ```
> agent "my_agent" output_schema must be "output_schema.json": rename agents/my_agent/verdict.json to output_schema.json and set output_schema: output_schema.json in manifest.yml
> ```
>
> Older CLIs keep the source name, pass `apps validate`, and fail deploy with `output schema is required when using JSON format`. Either way, put the schema at `agents/<path>/output_schema.json` and set the key to `output_schema.json`.
>
> Once bound, the schema is validated against the agent's model at deploy, and that failure is only visible in App manager > app > deployment > "Show errors": for example `output schema at root.properties.score uses unsupported schema keyword maximum, minimum` for Claude on Bedrock. Stick to `type`, `properties`, `required`, `enum`, `description`, and `additionalProperties: false`; put ranges in `description`. OpenAI models also need `additionalProperties: false` on every object and every property in `required`.

## Manifest Structure

Everything lands under one top-level `ai:` key, which is omitted entirely when empty:

```yaml
ai:
    agents:
        - id: cfa84addde80471fb2ffcb67460ca688   # CLI-generated, 32 hex chars
          name: Detection Triage Agent
          description: Triages detections against the runbooks
          path: Detection_Triage_Agent           # sanitized name
          model: ""                              # empty unless the user named one
          tools:                                 # hand-edited, see below
            - collections.triage_notes.CreateObject
            - api_integrations.VirusTotal.Get_a_file_report
          system_prompt: system_prompt.txt
          input_format: text
          output_format: json                    # json_with_schema adds output_schema: output_schema.json
          knowledge_bases:
            - Threat Intel Docs                  # by NAME
          exposure:                              # omitted entirely when nothing is exposed
            workflows:
                system_action: false
            charlotte_chat: true
            agent_as_tool: false
    knowledge_bases:
        - id: 328ff55985c24616ad895336b855c90d
          name: Threat Intel Docs
          description: Runbooks and IOC references
          encrypt: false
          path: Threat_Intel_Docs
          files:                                 # bare filenames only
            - runbook.md
            - iocs.csv
```

On disk:

```
agents/Detection_Triage_Agent/system_prompt.txt
knowledge-bases/Threat_Intel_Docs/runbook.md
knowledge-bases/Threat_Intel_Docs/iocs.csv
```

## Two Fields the CLI Cannot Set

`model` and `tools` have **no CLI flags**. `foundry agents create` always writes `model: ""` and omits `tools`. Configuring them means editing `manifest.yml` directly.

> **This is a narrow, explicit exception to the plugin-wide rule against editing `manifest.yml`**, which protects the CLI-owned `id`, `path`, `entrypoint`, and scopes. These two fields have no CLI path at all. Edit **only** these keys under `ai.agents[]` (plus a schema key that names the wrong file; see above); leave `id`, `path`, `system_prompt`, and every other artifact's entries alone.

- **`model`** — **never invent a model ID.** There is no client-side list of valid IDs, so anything you make up produces a manifest that validates locally and fails server-side at deploy. Three cases:
  - **Nothing supplied** — leave `""`. The platform default applies.
  - **User named a specific model** — write exactly what they gave you, and tell them it is only checked server-side at deploy. Honoring their choice is correct even if it later fails; guessing a "close enough" ID on their behalf is not.
  - **A value is already there** — leave it alone. Do not blank it out or substitute your own.
- **`tools`** — a flat list of dotted reference strings, not validated client-side. See below.

**No other tuning knobs exist.** Agents have no temperature or token settings, and knowledge bases have no chunk size, embedding, similarity, or `top_k`; indexing is server-side. Never add such keys to the manifest. Tell the user those settings aren't available.

## Agent Exposure

`exposure` controls where the agent can be reached from. Unlike `model` and `tools`, it **does** have CLI flags, so prefer setting it at create time:

| Flag | Manifest key | Effect when `true` |
|------|--------------|--------------------|
| `--expose-charlotte-chat` | `charlotte_chat` | Agent is reachable from Charlotte chat |
| `--expose-agent-as-tool` | `agent_as_tool` | Agent can be invoked as a tool by other agents |
| `--expose-workflow-system-action` | `workflows.system_action` | Agent is published as an app-scoped Fusion action |

Three behaviors worth knowing:

- **No flag means unreachable, even by your own app.** With no `--expose-*` flag the `exposure` block is omitted (same as all three `false`). For an agent used only by this app's automations, pass `--expose-workflow-system-action` alone; it stays out of Charlotte chat. Call it from the app's workflows as `ai_agents.<agent name>`, never a generic LLM action with the prompt copied inline ([workflow-invocation](references/workflow-invocation.md)).
- **`--expose-agent-as-tool` requires `--input-schema`.** A calling agent needs a declared signature to invoke this one. The check runs before any files are written:

  ```
  --input-schema is required when --expose-agent-as-tool is set
  ```

  The same rule is enforced on the manifest, so hand-adding `agent_as_tool: true` to an agent with no `input_schema` breaks every subsequent CLI command in that app:

  ```
  agent "X" input_schema is required when exposure.agent_as_tool is true
  ```

- **Nothing else here is validated client-side.** A misspelled key under `exposure` surfaces only at deploy.

Adding or removing exposure after create means editing `manifest.yml` (or deleting and re-creating the agent) — there is no `agents edit`.

## Agent Tool References

Each `tools` entry is a dotted string. The artifact must be exposed on its own side *and* named here — one without the other produces an agent that silently cannot call it, with no error at validate or deploy.

| Target | Format | Example |
|--------|--------|---------|
| App collection | `collections.<collection_name>.<Operation>` | `collections.triage_notes.CreateObject` |
| Agent runtime collection | `collections.generic.<Operation>` | `collections.generic.ListObjects` |
| API integration | `api_integrations.<name>.<agent_tools.name>` | `api_integrations.VirusTotal.Get_a_file_report` |

Valid collection operations — exact casing required:

`CreateObject`, `GetObject`, `DeleteObject`, `ListObjects`, `SearchObjects`

`collections.generic.*` refers to a scratch collection the platform creates for the agent at runtime. Use it for agent working memory; use a named app collection when the data must outlive the agent or be readable by other capabilities.

For API integrations the final segment is the operation's name from the OpenAPI spec's `x-cs-operation-config.agent_tools.name`, not the raw path.

### Exposing the target artifact

```bash
# Collections: one flag at create time
foundry collections create --name "triage_notes" --schema /tmp/schema.json \
  --description "Agent triage notes" --agent-tools-expose --no-prompt
```

That writes `agent_tools_integration: {exposed: true}` onto the collection. See `collections-development` for schema design.

API integrations opt in per operation inside the OpenAPI spec, alongside the workflow config:

```json
"x-cs-operation-config": {
  "agent_tools": {
    "name": "Get_a_file_report",
    "description": "get a file report",
    "expose_to_agent": true
  },
  "workflow": {
    "name": "Get a file report",
    "description": "Get a file report",
    "system": false
  }
}
```

`agent_tools` and `workflow` are independent — an operation can be exposed to agents, to workflows, to both, or to neither. See `api-integrations` for spec adaptation.

No other artifact type supports agent-tool exposure. Functions, workflows, and RTR scripts have no equivalent flag; to let an agent reach a function, expose the function to workflows and have the agent trigger the workflow.

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
| `file <name> already exists` | Re-running KB create over existing files | Delete the file or the KB directory first |
| System prompt is a file path string | Typo'd `--system-prompt` path fell back to inline text | Read back `agents/<path>/system_prompt.txt` |
| KB file missing after deploy | `.svg` files are always ignored by the packager | Convert to PNG, or reference it another way |
| `must be a filename only, not a path` | Subdirectory in a KB `files` entry | Flatten — KB directories cannot nest |
| Agent cannot call an exposed collection | Exposed but not listed in `tools` | Both sides are required |
| `output_schema must be "output_schema.json"` (or `input_schema ...`) on any command, or `output schema is required when using JSON format` at deploy | Schema file not named `output_schema.json` (`input_schema.json`), or an inline schema | Put the schema at `agents/<path>/output_schema.json` (`input_schema.json`) and set the manifest key to that name |
| Deploy `Failed` with `output schema at root.properties.X uses unsupported schema keyword ...` in App manager "Show errors" | Schema keyword the agent's model provider rejects (`minimum`/`maximum` for Claude on Bedrock) | Drop the keyword and state the constraint in `description`; for OpenAI models also set `additionalProperties: false` on every object and list every property in `required` |
| `model <id> does not support structured output` at deploy | `json_with_schema` on a model without it (Bedrock Claude and Nemotron, as of 2026-09) | Use `output_format: json` for that agent, or a model that supports it (`openai.gpt-5.5` does) |
| Two agents with the same name in Charlotte AI > AgentWorks | `agents delete` + redeploy left the old platform-side agent unpublished | Delete the orphan in the console; match agents by name prefix or manifest IDs, not by name alone |
| Deploy fails with `model <id> is not available`, and still fails after setting `model: ""` | Model IDs are CID-specific, and a failed deploy leaves the pinned model on the platform-side agent | Pick an ID from `/agentic-studio/queries/models/v1` in that CID, or remove the agent and create it again |
| `400` when invoking an agent with `credit_cents_limit` | Value below the undocumented floor | Pass `100` or more |

## Reading Guide

| Task | Reference |
|------|-----------|
| KB file sourcing, encryption, deploy packaging limits | [references/knowledge-bases.md](references/knowledge-bases.md) |
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
