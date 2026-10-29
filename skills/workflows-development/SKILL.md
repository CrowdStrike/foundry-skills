---
name: workflows-development
description: Create and configure Falcon Fusion SOAR workflow YAML for Falcon Foundry apps. TRIGGER when user asks to "create a workflow", "build an automation", "configure Falcon Fusion SOAR", "add an on-demand workflow", runs `foundry workflows create`, or needs help with Falcon Fusion YAML syntax, triggers, actions, or variable references. DO NOT TRIGGER for UI pages, functions, or collection schemas — use the appropriate sub-skill.
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

> Write every workflow definition in Falcon Fusion YAML, validate step dependencies before running it, and handle failures with conditional routing and action-level flags ([Error Handling](#error-handling)) — Fusion has no `onError` blocks and no built-in retry.

> **Part of a suite.** If `development-workflow` has not already run, and this is a new app or its first capability, load the `development-workflow` skill first — it owns the CLI prerequisite check, scaffolding order, and manifest coordination.

## Prerequisites

- **Workflow Author role** is required in addition to the Falcon Developer role
- Workflows are YAML templates provisioned as active instances (up to **25** per template)
- **`provision_on_install: true` is REQUIRED** in the workflow YAML — treat it as a per-workflow checklist item, not a footnote. With `true`, installing the app creates the workflow in Falcon Fusion SOAR, turned on. With `false`, the deploy is "Successful" and the template is listed in the app's **Logic** section, but installing creates no workflow, so nothing runs until something provisions it (the `/workflows/system-definitions/provision` API). Use `false` deliberately: for a workflow with an action ID you can't verify, which the user finishes in the console (see [Platform Action Fallback Strategy](references/advanced-patterns.md#platform-action-fallback-strategy)), or to let an app install without the credentials a workflow needs, as the sample apps' e2e tests do.

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

This is the format produced by `foundry workflows create` and used by many Foundry sample apps — a `trigger:` (with `next:` naming the first action) plus an `actions:` map where each action carries an `id`, `properties`, `version_constraint`, and optional `next:`, closing with `output_fields: []`. See [references/workflow-examples.md](references/workflow-examples.md#standard-trigger-actions-format) for the full canonical YAML (on-demand Okta list → print).

**Trigger types:**

| Type | Format |
|------|--------|
| On demand | `name: On demand`, `type: On demand` |
| Scheduled | `event: Schedule`, `schedule: {time_cycle: "0 */6 * * *", tz: Etc/UTC}` |

**Trigger parameters** (inputs the console prompts for when an on-demand workflow runs) are a JSON Schema object under `trigger:`, read in actions as `${data['name']}`:

```yaml
trigger:
    name: On demand
    type: On demand
    parameters:
        type: object
        properties:
            recipient:
                type: string
                description: Who gets the report
        required:
            - recipient
```

> **⚠️ Null-guard trigger parameters:** When run from the Falcon console the UI prompts for parameters, but via API or from another workflow they may be empty. Guard with a `conditions:` branch (`cel_expression: data['param'] != null && data['param'] != ''`, routing to a handler via `else:`) or inline in CEL with a ternary: `${data['param'] != null ? data['param'] : "default"}`. Full `conditions:` block: [references/cel-expressions.md](references/cel-expressions.md#null-guard-trigger-parameters).

**Variable syntax in actions:** Use `${data['action_key.path.to.field']}` CEL expressions. See [Variable References](#variable-references) for the full syntax. Do NOT use `$action_name.output.body` — it passes as a literal string and is not resolved.

**Version constraints:** Set `version_constraint: ~N` on each action, where `N` is the major version of the activity's declared `semantic_version` (not its iteration count): **`~0`** when the activity has no `semantic_version` (functions, API integrations) or a `0.x` one (Contain device is `0.0.x`); **`~1`** for a `1.x` one (Print data, Send email, Create/Update variable, Get device details). Some samples omit it on function actions. Check with `scripts/action_search.py "<action>" --details`, which prints the `semantic_version` and the matching constraint; a worked `~0`/`~1` example is in [references/workflow-examples.md](references/workflow-examples.md#version-constraint-example).

### Manifest Configuration

```yaml
# manifest.yml
workflows:
  - name: my-workflow
    path: workflows/my-workflow.yml
    permissions: []
```

Trigger type and schedule are defined inside the workflow YAML file (via `trigger:` block), not in the manifest. The manifest only declares the workflow name, path, and optional permissions.

> RTR scripts are not supported in certified Foundry apps (apps published to the CrowdStrike Store). RTR workflows work in custom/internal apps only. For full RTR multi-host orchestration and investigation-pipeline examples, see [references/workflow-examples.md](references/workflow-examples.md).

## Calling Functions from Workflows

Functions called via `id: functions.{name}.{handler}` must have `workflow_integration` in the manifest. Set it at create time with `foundry functions create --wf-expose` (plus `--input-schema`/`--output-schema`). For a function created without it whose schemas are already set, add the block to the handler in `manifest.yml` (`id: ""`, `disruptive`, `system_action`, `tags`, as `--wf-expose` writes it) and redeploy: the deploy fills in the `id` and binds it, including on a function that was already deployed without one. Missing it fails deploy with `referenced function '{name}' and handler '{handler}' does not have workflow_integration properties defined`.

> **⚠️ Every non-empty `properties:` on a function action needs a declared `request_schema`.** A function action passes the handler only the properties its `request_schema` declares; an undeclared property is **silently dropped**, even with `additionalProperties: true`, and no error is raised. Symptom: a function that "runs fine" but behaves as if an input was blank. Declare every property the workflow passes. Declare the schema at create time via `foundry functions create … --input-schema` (hand-editing the manifest does not bind it).

**Calling the app's own AI agent**: `id: ai_agents.<agent name>` with `input` (the prompt) and `version_constraint: ~1`; the agent needs `exposure.workflows.system_action: true`, and its reply is read downstream as `${data['action_key.response']}`. `apps validate` doesn't resolve it — check the deploy output. Full walkthrough (aliasing, the `(2018) Action was not found` trap, `json_with_schema` field access) in the `ai-agents-development` skill's `references/workflow-invocation.md`.

> **⚠️ Reading Falcon alerts/detections/incidents? Depends on whether the workflow already holds the object.** *Enriching* one the workflow was triggered on (query by its ID) → Event Query action, schemaless. *Fetching a population you don't have* ("summarize all high-severity alerts") → source-of-truth API: a native platform action (e.g. Cases → Search Cases) or a FalconPy `Alerts`/`Detects` function — an Event Query can silently return nothing (NG-SIEM contents are connector-dependent). See [references/event-query-vs-api.md](references/event-query-vs-api.md).

## Calling API Integration Operations

> **💡 Consider HTTP Actions first.** For a one-off REST call (no custom UI or reusable function), an [HTTP Action](https://www.crowdstrike.com/tech-hub/ng-siem/build-api-integrations-with-falcon-fusion-soar-http-actions/) is faster than an API integration — no app, no OpenAPI spec, no deploy, 130+ templates. Use a full API integration when the operation is reused across workflows or paired with functions/UI. See [references/http-actions.md](references/http-actions.md).

> **⚠️ Always call a registered integration** via `api_integrations.{name}.{operationId}` — never a function making raw HTTP calls to the same API with hardcoded creds or `{{API_TOKEN}}`-style templates. The platform owns auth, rate limiting, and audit logging.

`{name}` must match the manifest `api_integrations` entry, prefixed `Custom_` in the variable path (the platform adds it to every integration name). The action `id:` uses the `operationId`, but the next segment of the output path comes from the operation's `x-cs-operation-config.workflow.name` with spaces turned into underscores: an operation with `operationId: Get leavers data` and workflow name `Workday get leavers data` is called as `api_integrations.Workday get leavers data.Get leavers data` and read as `…API_Integration.Custom_Workday_get_leavers_data.Workday_get_leavers_data.body`. Copy the path from the editor's **Workflow data** panel. The OpenAPI `operationId`'s `x-cs-operation-config` must nest the config under a `workflow:` key (`name`, `description`, `expose_to_workflow: true`, `system: false`) — a flat `expose_to_workflow: true` will not work. Auth scopes for CLI-created artifacts are managed automatically. Full action + `x-cs-operation-config` example: [references/workflow-examples.md](references/workflow-examples.md#api-integration-operation-call).

## Platform Actions

Platform actions (send email, log output, create detection) require platform-specific action IDs, verified identical across us-1, us-2, and eu-1. The two most used are **Print data** `aadbf530e35fc452a032f5f8acaaac2a` and **Send email** `07413ef9ba7c47bf5a242799f59902cc`; the full lookup table (Create/Update variable, Sleep, Get device details, Contain device, Request human input) is in [references/action-discovery.md](references/action-discovery.md#common-platform-action-ids). For any action not listed, use `foundry workflows actions view --name "..." --no-prompt`. There are 9,000+ platform actions — MUST NOT guess action IDs; use discovery commands.

### Common Action Properties

**Print data** has three inputs: `fields` (the CLI reports type `string`; the samples pass a YAML list of `${...}` pills), `text_data` (string — general-purpose), `custom_json` (object only). Use `text_data` for API-integration responses since `body` may be an array; data path `action_key.API_Integration.Custom_{Name}.{Workflow_name}.body` (copy exact paths from the editor's **Workflow data** panel). **Send email** is secondary — add only when explicitly requested, skip in headless runs, and ask for a real `to` address (placeholders fail at runtime). Its inputs are `to` (a list of addresses), `subject`, `msg`, and `msg_type` (`text` or `html`), plus optional `file_attachment` and `skip_workflow_header`. Its ID is the verified one above, so it needs no lookup; `actions view --name "Send email"` also matches similarly named actions such as Gmail - Send Email. Full `send_email` action example: [references/workflow-examples.md](references/workflow-examples.md#send-email-action).

## Variable References

Falcon Fusion SOAR uses [Common Expression Language (CEL)](https://github.com/google/cel-spec/blob/master/doc/langdef.md) for data references — all use `${data['...']}` syntax. The `action_key` is the YAML key of the action (e.g. `list_users`), NOT its `id`; an API integration's path segment is `Custom_{name}` (spaces → underscores). Common forms: API body `${data['action_key.API_Integration.Custom_Name.Workflow_name.body']}` (`Workflow_name` is the operation's `x-cs-operation-config.workflow.name` with spaces → underscores; index an array element inside the braces: `${data['…body'][0].field}`), platform output namespaced by action type (`${data['action_key.Device.GetDetails.Platform']}`, `${data['action_key.RTR.PutAndRun.stdout']}`), app AI-agent reply `${data['action_key.response']}` (a `json_with_schema` agent uses `${data['action_key.<schema field>']}` instead), function output `${data['action_key.FaaS.<function>.<handler>.<field>']}` (loop item `…<field>.#.<item field>`), and trigger parameter `${data['param_name']}`. The full table with every form is in [references/cel-expressions.md](references/cel-expressions.md#variable-reference-forms); copy exact paths from the editor's **Workflow data** panel.

**CRITICAL:** Do NOT use `$action_name.output.body` — it passes as a literal string and is NOT resolved at runtime. Always use `${data['...']}` expressions.

### CEL Expressions

Falcon Fusion SOAR supports CEL for data transformations, conditions, and field access. Key patterns: null-safe access with `!= null` (`${data['action.field'] != null ? data['action.field'] : "default"}`), `size()` before indexing a list, and array access with the index INSIDE the braces (`${data['…body'][0]}`, not after).

**`has()` only works on retrieved objects, not data store keys.** `has(data['key'])` fails with `Q0910`; use `data['key'] != null` for keys, or `has(data['var'].field)` to check a field on an already-retrieved object.

CrowdStrike adds [custom CEL extensions](https://docs.crowdstrike.com/r/k223d842) (`cs.json.decode()`, `cs.ip.valid()`, `cs.timestamp.parse()`, etc.). For the full pattern catalog, runnable snippets, the `has()` vs `!= null` guide, and extension details, see [references/cel-expressions.md](references/cel-expressions.md).

## Control Flow

**Loops** iterate over arrays or paginate with cursor-based conditions. They are self-contained sub-workflows at the root `loops:` level; the action before a loop must name it in its `next:` list or the loop deploys but never runs. A loop item is referenced with `${<input>.#}`, and a loop item's field is `...<field>.#.<item field>`.

**Conditions** route with an FQL-style `expression:` or a CEL `cel_expression:`, each with an optional `else:` fallback branch.

See [references/workflow-examples.md](references/workflow-examples.md#control-flow-loop-and-condition-examples) for full loop (`DeviceLoop` with platform-check routing) and condition examples from production apps.

## Join Resolution & Cyclic References

Falcon Fusion SOAR builds a DAG. A node inside a parallel branch MUST NOT reach a downstream join **both directly and through a child** — Falcon Fusion SOAR reads that as a cycle and fails the deploy:

❌ `A.next: [Join, B]` + `B.next: [Join]` → `2001 cyclic reference to previously seen node … FROM_B_TO_parallel_A`

**Fix: linearize.** Make every node whose output a consumer reads a *single-path ancestor* of that consumer — `A → B → Join`. The pill from `A` still reaches `Join` because `A` stays an ancestor.

> **Silent variant (no error):** a store/aggregator that reads a node `X`'s output (`${data['X.<field>']}`) when `X` sits on a **diamond fork** resolves **EMPTY** at the join — the pill comes back blank, not an error, which is very hard to diagnose. Same rule, same fix: any node whose output you read must be a single-path ancestor of the reader, never a shared fork.

> **A consumer can only read an ancestor's output.** A parallel branch whose `next:` chain never leads to the consumer deploys fine, yet its pill comes back blank there. Make the producer an ancestor of the consumer: add a direct `next:` edge when nothing else the producer feeds also reaches the consumer, and otherwise linearize as above, since a direct edge plus a path through a sibling is the `2001` cycle.

See [Diamond Joins](references/advanced-patterns.md#diamond-joins--the-2001-cyclic-reference) for a worked diamond showing the failure and the linearized rewrite.

## The "0" Gotcha

See [pagination-patterns](references/pagination-patterns.md#the-0-gotcha-in-pagination) for the "0" gotcha and fix pattern. Key point: check for both null and `"0"` in loop conditions.

## Workflow Name Uniqueness

Workflow names must be unique across all apps installed in a CID. The clash shows up at **install**, not deploy: two apps whose workflows share a name both deploy and release, but installing the second one ends in **Install failed** (the app's state reads `Installation failed`). Use app-specific prefixes when the workflow name is generic.

The exception is `multi_instance: true` at the top of the workflow YAML. With it, the second app installs, and Falcon Fusion SOAR renames its copy with a timestamp suffix (`<name> - 2026-10-29T05:01:07Z`) instead of rejecting it. Set it when several apps created from the same template may be installed in one CID. It doesn't change whether installing creates the workflow, which is still `provision_on_install`.

## NEVER Delete and Recreate Workflows

Removing a workflow from the manifest does NOT delete its server-side artifact — recreating with the same name → `409 name must be unique for an app`, and a once-failed artifact taints the dependency graph (`400 dependent artifact failed`), blocking all further deploys. **Update in place instead**: keep the manifest entry and its name, edit the YAML, and redeploy; to re-bind to a recreated function, update the `id: functions.{name}.{handler}` reference. Only delete a workflow if you truly won't recreate it with the same name. If an in-place structural edit hits a 409, use the sticky-409 recipe below. A `400 dependent artifact failed` is different: the failed artifact blocks every later deploy of the app, and recovery means a fresh app (see `ai-agents-development`'s `references/workflow-invocation.md`).

### Sticky-409 recovery (structural change re-provisions and 409s)

A structural edit that re-provisions a workflow (a new action, an edited `next`/edge, an added trigger parameter) can fail with `Duplicate workflow name (409)` / `system definition with id … already provisioned on cid …`. **Deleting the Falcon Fusion SOAR workflow does NOT free the name — a used name stays reserved**, so re-deploying the same name keeps 409ing. The reliable escape is to **rename to a brand-new unique name AND strip the `id`** (do both; either one alone still 409s) — the full step-by-step recovery is in [references/advanced-patterns.md](references/advanced-patterns.md#sticky-409-recovery).

## Error Handling

Foundry workflows handle errors through conditional routing and action-level flags — not `onError` blocks or retry middleware. Key mechanisms: action-level `continue_on_error: true`, `continue_on_partial_execution` (concurrent loops), and `conditions:`/`else:` on `Workflow.Execution.Errors`. No built-in retry or backoff exists. For the full table, examples, and pagination-polling pattern, see [references/advanced-patterns.md](references/advanced-patterns.md).

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
