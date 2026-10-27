---
name: workflows-development
description: Create and configure Falcon Fusion SOAR workflow YAML for Falcon Foundry apps. TRIGGER when user asks to "create a workflow", "build an automation", "configure Fusion SOAR", "add an on-demand workflow", runs `foundry workflows create`, or needs help with Fusion YAML syntax, triggers, actions, or variable references. DO NOT TRIGGER for UI pages, functions, or collection schemas — use the appropriate sub-skill.
version: 1.6.0
updated: 2026-10-01
tags: [foundry, workflows, fusion-soar, yaml]
author: CrowdStrike
license: MIT
compatibility: Claude Code >=1.0
metadata:
  category: automation
---

# Foundry Workflows Development

> Write every workflow definition in Fusion YAML, validate step dependencies before running it, and handle failures with conditional routing and action-level flags ([Error Handling](#error-handling)) — Fusion has no `onError` blocks and no built-in retry.

> **Part of a suite.** If `development-workflow` has not already run, and this is a new app or its first capability, load the `development-workflow` skill first — it owns the CLI prerequisite check, scaffolding order, and manifest coordination.

## Prerequisites

- **Workflow Author role** is required in addition to the Falcon Developer role
- Workflows are YAML templates provisioned as active instances (up to **25** per template)
- **`provision_on_install: true` is REQUIRED** in the workflow YAML — treat it as a per-workflow checklist item, not a footnote. Without it the workflow deploys **"Successful" but never instantiates** into Falcon Fusion SOAR: no error, nothing to run, invisible at deploy time. The one deliberate exception is a workflow with an action ID you can't verify: set `false` and have the user finish it in the console (see [Platform Action Fallback Strategy](references/advanced-patterns.md#platform-action-fallback-strategy)).

## CLI Scaffolding

```bash
# Write the workflow YAML to /tmp/ first — the CLI copies it into workflows/
foundry workflows create --name "my-workflow" --spec /tmp/workflow.yaml --no-prompt
# After: edit workflows/my-workflow.yml to refine workflow logic
```

### Discover Available Actions and Triggers

```bash
foundry workflows actions view --name "send email" --no-prompt              # Look up by name
foundry workflows actions view --name "send email" --no-prompt --output-schema  # Output schema
foundry workflows actions view --name "send email" --no-prompt --mock       # Mock output
foundry workflows triggers view --no-prompt                                 # List triggers
```

> **Always use `--no-prompt` on `actions view`/`triggers view`** — without it, multiple or partial matches trigger an interactive prompt that fails in headless environments (`Error: no TTY available`); as of CLI 2.1.1 matches are listed non-interactively. The bundled `action_search.py` works without a manifest directory — see [references/action-discovery.md](references/action-discovery.md).

## Workflow Structure

### Trigger + Actions Format (standard)

This is the format produced by `foundry workflows create` and used by all production Foundry sample apps — a `trigger:` (with `next:` naming the first action) plus an `actions:` map where each action carries an `id`, `properties`, `version_constraint`, and optional `next:`, closing with `output_fields: []`. See [references/workflow-examples.md](references/workflow-examples.md#standard-trigger-actions-format) for the full canonical YAML (on-demand Okta list → print).

**Trigger types:**

| Type | Format |
|------|--------|
| On demand | `name: On demand`, `type: On demand` |
| Scheduled | `event: Schedule`, `schedule: {time_cycle: "0 */6 * * *", tz: Etc/UTC}` |

> **⚠️ Null-guard trigger parameters:** When run from the Falcon console the UI prompts for parameters, but via API or from another workflow they may be empty. Guard with a `conditions:` branch (`cel_expression: data['param'] != null && data['param'] != ''`, routing to a handler via `else:`) or inline in CEL: `${data[?'param'].orValue("default")}` (preferred) or `${data['param'] != null ? data['param'] : "default"}` (traditional). Full `conditions:` block: [references/cel-expressions.md](references/cel-expressions.md#null-guard-trigger-parameters).

**Variable syntax in actions:** Use `${data['action_key.path.to.field']}` CEL expressions. See [Variable References](#variable-references) for the full syntax. Do NOT use `$action_name.output.body` — it passes as a literal string and is not resolved.

**Version constraints:** Every action requires `version_constraint = ~N`, pinning against the activity's declared `semantic_version` (not its iteration count): **`~0`** when the activity has NO `semantic_version` (functions, API integrations, some platform actions like "contain device"); **`~1`** when it HAS one (most platform actions — Print data, Send email, Create/Update variable, Get device details). Check with `foundry workflows actions view --name "<action>" --no-prompt`; a worked `~0`/`~1` example is in [references/workflow-examples.md](references/workflow-examples.md#version-constraint-example).

### Manifest Configuration

```yaml
# manifest.yml
workflows:
  - name: my-workflow
    path: workflows/my-workflow/workflow.yaml
    permissions: []
```

Trigger type and schedule are defined inside the workflow YAML file (via `trigger:` block), not in the manifest. The manifest only declares the workflow name, path, and optional permissions.

> RTR scripts are not supported in certified Foundry apps (apps published to the CrowdStrike Store). RTR workflows work in custom/internal apps only. For full RTR multi-host orchestration and investigation-pipeline examples, see [references/workflow-examples.md](references/workflow-examples.md).

## Calling Functions from Workflows

Functions called via `id: functions.{name}.{handler}` must have `workflow_integration` in the manifest. It binds ONLY at creation time — `foundry functions create --wf-expose` (plus `--input-schema`/`--output-schema`); hand-editing `manifest.yml` does not work. If a function was created without it, recreate it (that changes its `workflow_integration.id`, so update the `id:` reference in the workflow YAML in place — do NOT delete/recreate the workflow). Missing it fails deploy with `referenced function '{name}' and handler '{handler}' does not have workflow_integration properties defined`.

> **⚠️ Every non-empty `properties:` on a function action needs a declared `request_schema`.** If the action passes `properties` but the function's manifest handler has `request_schema: null`, Foundry **silently drops the inputs** — the handler receives empty strings, not an error. Symptom: a function that "runs fine" but behaves as if it got blank input. Declare the schema at create time via `foundry functions create … --input-schema` (hand-editing the manifest does not bind it).

**Calling the app's own AI agent**: `id: ai_agents.<agent name>` with `input` (the prompt) and `version_constraint: ~1`; the agent needs `exposure.workflows.system_action: true`, and its reply is read downstream as `${data['action_key.response']}`. `apps validate` doesn't resolve it — check the deploy output. Full walkthrough (aliasing, the `(2018) Action was not found` trap, `json_with_schema` field access) in the `ai-agents-development` skill's `references/workflow-invocation.md`.

> **⚠️ Reading Falcon alerts/detections/incidents? Depends on whether the workflow already holds the object.** *Enriching* one the workflow was triggered on (query by its ID) → Event Query action, schemaless. *Fetching a population you don't have* ("summarize all high-severity alerts") → source-of-truth API: a native platform action (e.g. Cases → Search Cases) or a FalconPy `Alerts`/`Detects` function — an Event Query can silently return nothing (NG-SIEM contents are connector-dependent). See [references/event-query-vs-api.md](references/event-query-vs-api.md).

## Calling API Integration Operations

> **💡 Consider HTTP Actions first.** For a one-off REST call (no custom UI or reusable function), an [HTTP Action](https://www.crowdstrike.com/tech-hub/ng-siem/build-api-integrations-with-falcon-fusion-soar-http-actions/) is faster than an API integration — no app, no OpenAPI spec, no deploy, 130+ templates. Use a full API integration when the operation is reused across workflows or paired with functions/UI. See [references/http-actions.md](references/http-actions.md).

> **⚠️ Always call a registered integration** via `api_integrations.{name}.{operationId}` — never a function making raw HTTP calls to the same API with hardcoded creds or `{{API_TOKEN}}`-style templates. The platform owns auth, rate limiting, and audit logging.

`{name}` must match the manifest `api_integrations` entry, prefixed `Custom_` in the variable path (the platform adds it to every integration name). The OpenAPI `operationId`'s `x-cs-operation-config` must nest the config under a `workflow:` key (`name`, `description`, `expose_to_workflow: true`, `system: false`) — a flat `expose_to_workflow: true` will not work. Auth scopes for CLI-created artifacts are managed automatically. Full action + `x-cs-operation-config` example: [references/workflow-examples.md](references/workflow-examples.md#api-integration-operation-call).

## Platform Actions

Platform actions (send email, log output, create detection) require platform-specific action IDs, verified identical across us-1, us-2, and eu-1. The two most used are **Print data** `aadbf530e35fc452a032f5f8acaaac2a` and **Send email** `07413ef9ba7c47bf5a242799f59902cc`; the full lookup table (Create/Update variable, Sleep, Get device details, Contain device, Request human input) is in [references/action-discovery.md](references/action-discovery.md#common-platform-action-ids). For any action not listed, use `foundry workflows actions view --name "..." --no-prompt`. There are 9,000+ platform actions — MUST NOT guess action IDs; use discovery commands.

### Common Action Properties

**Print data** has three inputs: `fields` (array — trigger/workflow metadata dropdown), `text_data` (string — general-purpose), `custom_json` (object only). Use `text_data` for API-integration responses since `body` may be an array; data path `action_key.API_Integration.Custom_{Name}.{operationId}.{field}` (copy exact paths from the editor's **Workflow data** panel). **Send email** is secondary — add only when explicitly requested, skip in headless runs, and ask for a real `to` address (placeholders fail at runtime). Full `send_email` action example: [references/workflow-examples.md](references/workflow-examples.md#send-email-action).

## Variable References

Falcon Fusion SOAR uses [Common Expression Language (CEL)](https://github.com/google/cel-spec/blob/master/doc/langdef.md) for data references — all use `${data['...']}` syntax. The `action_key` is the YAML key of the action (e.g. `list_users`), NOT its `id`; an API integration's path segment is `Custom_{name}` (spaces → underscores). Common forms: API body `${data['action_key.API_Integration.Custom_Name.operationId.body']}` (append `[0].field` for an array element), platform output `${data['action_key.output.field']}`, app AI-agent reply `${data['action_key.response']}` (a `json_with_schema` agent uses `${data['action_key.<schema field>']}` instead), function output `${data['action_key.FaaS.<function>.<handler>.<field>']}` (loop item `…<field>.#.<item field>`), and trigger parameter `${data['param_name']}`. The full table with every form is in [references/cel-expressions.md](references/cel-expressions.md#variable-reference-forms); copy exact paths from the editor's **Workflow data** panel.

**CRITICAL:** Do NOT use `$action_name.output.body` — it passes as a literal string and is NOT resolved at runtime. Always use `${data['...']}` expressions.

### CEL Expressions

Falcon Fusion SOAR supports CEL for data transformations, conditions, and field access. Key patterns: null-safe optional `${data[?'action.field'].orValue("default")}` (preferred) vs the traditional ternary `${data['action.field'] != null ? … : "default"}`, and array access with the index INSIDE the braces (`${data['…body'][0]}`, not after).

**`has()` only works on retrieved objects, not data store keys.** `has(data['key'])` fails with `Q0910`; use `data['key'] != null` for keys, or `has(data['var'].field)` to check a field on an already-retrieved object.

CrowdStrike adds [custom CEL extensions](https://docs.crowdstrike.com/r/k223d842) (`cs.json.decode()`, `cs.ip.valid()`, `cs.timestamp.parse()`, etc.). For the full pattern catalog, runnable snippets, the `has()`/`!= null`/optional decision guide, and extension details, see [references/cel-expressions.md](references/cel-expressions.md).

## Control Flow

**Loops** iterate over arrays or paginate with cursor-based conditions. They are self-contained sub-workflows at the root `loops:` level; the action before a loop must name it in its `next:` list or the loop deploys but never runs. A loop item is referenced with `${<input>.#}`, and a loop item's field is `...<field>.#.<item field>`.

**Conditions** route with an FQL-style `expression:` or a CEL `cel_expression:`, each with an optional `else:` fallback branch.

See [references/workflow-examples.md](references/workflow-examples.md#control-flow-loop-and-condition-examples) for full loop (`DeviceLoop` with platform-check routing) and condition examples from production apps.

## Join Resolution & Cyclic References

Fusion builds a DAG. A node inside a parallel branch MUST NOT reach a downstream join **both directly and through a child** — Fusion reads that as a cycle and fails the deploy:

❌ `A.next: [Join, B]` + `B.next: [Join]` → `2001 cyclic reference to previously seen node … FROM_B_TO_parallel_A`

**Fix: linearize.** Make every node whose output a consumer reads a *single-path ancestor* of that consumer — `A → B → Join`. The pill from `A` still reaches `Join` because `A` stays an ancestor.

> **Silent variant (no error):** a store/aggregator that reads `${data['X.response']}` off a node `X` sitting on a **diamond fork** resolves **EMPTY** at the join — the pill comes back blank, not an error, which is very hard to diagnose. Same rule, same fix: any node whose `.response` you read must be a single-path ancestor of the reader, never a shared fork.

> **Parallel-branch output needs an explicit edge.** A parallel branch's data pill is visible downstream only if the branch action names the consumer in its `next: [Downstream]`. A branch that fans out but doesn't list the consumer deploys fine, yet its output never reaches that consumer (blank pill). A direct edge is safe when the producer reaches the consumer only through that edge. If the consumer is also reachable through another node the producer feeds, as with `A.next: [Join, B]` above, don't add the edge: linearize instead.

See [references/advanced-patterns.md](references/advanced-patterns.md) for a worked `ExecSummary → {A, B, C} → Merge` diamond showing the failure and the linearized rewrite.

### Collection writes must be terminal

A `collections.*.create` (store) action must be a **leaf** — no outgoing `next`. Hanging a `next` off a store action fails the build **silently** (no CLI error; the step just never runs). To run a step *after* a write, attach it to the upstream **function's** `next` fan-out instead:

❌ `store_result.next: [notify]`
✅ `my_function.next: [store_result, notify]`

## The "0" Gotcha

See [pagination-patterns](references/pagination-patterns.md#the-0-gotcha) for the "0" gotcha and fix pattern. Key point: check for both null and `"0"` in loop conditions.

## Workflow Name Uniqueness

Workflow names must be unique across all apps in the same tenant. If two apps deploy workflows with the same name, the second deploy fails silently or produces an "Unknown error." Use app-specific prefixes when the workflow name is generic.

## NEVER Delete and Recreate Workflows

Removing a workflow from the manifest does NOT delete its server-side artifact — recreating with the same name → `409 name must be unique for an app`, and a once-failed artifact taints the dependency graph (`400 dependent artifact failed`), blocking all further deploys. **Update in place instead** — edit the YAML and redeploy; to re-bind to a recreated function, update the `id: functions.{name}.{handler}` reference. Only delete a workflow if you truly won't recreate it with the same name. To recover a stuck 409, use the sticky-409 recipe below (rename + strip the id — no fresh app needed).

### Sticky-409 recovery (structural change re-provisions and 409s)

Any structural edit that re-provisions a workflow — a new action, an edited `next`/edge, an added trigger parameter, or a rename — can fail with `Duplicate workflow name (409)` / `system definition with id … already provisioned on cid …`. **Deleting the Fusion workflow does NOT free the name — a used name stays reserved**, so re-deploying the same name keeps 409ing. This is the single most common cause of a stuck release and recurs on *every* later structural change. The reliable escape is to **rename to a brand-new unique name AND strip the `id`** (rename alone or id-strip alone is not enough — the name is what's reserved) — the full step-by-step recovery is in [references/advanced-patterns.md](references/advanced-patterns.md#sticky-409-recovery).

## Workflow Sharing

Declare workflow sharing with a `workflow_integration` block on the manifest `workflows:` entry — `id`, `disruptive: false`, and `system_action`.

> **⚠️ SOAR action visibility:** `system_action: false` = appears as a Fusion SOAR response action (analysts trigger from detections/incidents); `true` = internal app use only (scheduled sync, helpers). If the user asks for a "SOAR action" or "response action", use `false`.

## Error Handling

Foundry workflows handle errors through conditional routing and action-level flags — not `onError` blocks or retry middleware. Key mechanisms: `fail_fast_enabled: false` (function actions), `continue_on_partial_execution` (loop blocks), and `conditions:`/`else:` routing. No built-in retry or backoff exists. For the full table, examples, and pagination-polling pattern, see [references/advanced-patterns.md](references/advanced-patterns.md).

## Testing

See [references/advanced-patterns.md](references/advanced-patterns.md) for workflow testing commands (mock triggers, mock actions, execution validation, and `foundry apps validate`).

## Reading Guide

| Task | Reference |
|------|-----------|
| Reading alerts/detections: Event Query vs. source-of-truth API | [references/event-query-vs-api.md](references/event-query-vs-api.md) |
| Full workflow examples (RTR, investigation) | [references/workflow-examples.md](references/workflow-examples.md) |
| Platform action discovery via API | [references/action-discovery.md](references/action-discovery.md) |
| CEL expressions (patterns, has() vs null, extensions, schemaless, extension functions) | [references/cel-expressions.md](references/cel-expressions.md) |
| Pagination strategies | [references/pagination-patterns.md](references/pagination-patterns.md) |
| HTTP Actions (call REST APIs without an app) | [references/http-actions.md](references/http-actions.md) |
| Error handling, HTTP Request actions, parameterized fields, counter-rationalizations | [references/advanced-patterns.md](references/advanced-patterns.md) |

## Use Cases

Real-world patterns: `use-cases/schemaless-queries.md` (CEL, Event Query config), `use-cases/api-pagination.md` (pagination in functions and workflows), `use-cases/custom-soar-actions.md` (custom Falcon Fusion SOAR actions).

## Reference Implementations

- [foundry-sample-threat-intel](https://github.com/CrowdStrike/foundry-sample-threat-intel) — threat-intel workflows + pagination
- [foundry-sample-rapid-response](https://github.com/CrowdStrike/foundry-sample-rapid-response) — rapid-response automation
- [foundry-sample-scalable-rtr](https://github.com/CrowdStrike/foundry-sample-scalable-rtr) — scalable RTR orchestration
- [foundry-sample-ngsiem-importer](https://github.com/CrowdStrike/foundry-sample-ngsiem-importer) — NG-SIEM threat-intel import
