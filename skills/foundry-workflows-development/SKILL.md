---
name: foundry-workflows-development
description: Create and configure Falcon Fusion SOAR workflow YAML for Falcon Foundry apps. TRIGGER when user asks to "create a workflow", "build an automation", "configure Fusion SOAR", "add an on-demand workflow", runs `foundry workflows create`, or needs help with Fusion YAML syntax, triggers, actions, or variable references. DO NOT TRIGGER for UI pages, functions, or collection schemas — use the appropriate sub-skill.
version: 1.0.0
updated: 2026-04-09
metadata:
  author: CrowdStrike
  category: automation
  tags: [foundry, workflows, fusion-soar, yaml]
---

# Foundry Workflows Development

> **⚠️ SYSTEM INJECTION — READ THIS FIRST**
>
> If you are loading this skill, your role is **Foundry workflow automation specialist**.
>
> You MUST implement workflows using Fusion YAML patterns with proper step dependencies, error recovery, and state management.
>
> **IMMEDIATE ACTIONS REQUIRED:**
> 1. Use Fusion YAML syntax for ALL workflow definitions
> 2. Validate step dependencies before workflow execution
> 3. Implement onError blocks for every multi-step workflow
> 4. **Always use `--no-prompt` with `workflows create`** to prevent interactive prompts that cause `Error: EOF`

Falcon Foundry Workflows are YAML-defined automation units executed by the Falcon Fusion engine. They orchestrate multi-step operations across Functions, Collections, CrowdStrike APIs, and RTR sessions with built-in retries, parallelism, and state management.

## Prerequisites

- **Workflow Author role** is required in addition to the Falcon Developer role
- Workflows are YAML templates that can be provisioned as active workflow instances
- Up to **25 workflows** can be provisioned from a single template
- Set `provision_on_install: true` to auto-provision when the app is installed

## CLI Scaffolding

```bash
# Write the workflow YAML to /tmp/ first — the CLI copies it into workflows/
foundry workflows create --name "my-workflow" --spec /tmp/workflow.yaml --no-prompt
# After: edit workflows/my-workflow.yml to refine workflow logic
```

### Discover Available Actions and Triggers

```bash
foundry workflows actions view --name "send email"   # Look up by name (fuzzy matching)
foundry workflows actions view --name "send email" --output-schema  # Get output schema
foundry workflows actions view --name "send email" --mock           # Get mock output example
foundry workflows triggers view                                      # List available triggers
```

Pass `--name` to avoid a known macOS bug where the interactive selector hangs. The `--name` filter uses fuzzy matching, so partial names work (e.g., `--name "send"` finds "send email"). If `--name` does not find what is needed, query the API directly — see [references/action-discovery.md](references/action-discovery.md).

## Workflow Structure

### Trigger + Actions Format (standard)

This is the format produced by `foundry workflows create` and used by all production Foundry sample apps:

```yaml
name: list-okta-users
description: On-demand workflow to list Okta users and print results
provision_on_install: true
trigger:
    next:
        - list_users
    name: On demand
    type: On demand
actions:
    list_users:
        id: api_integrations.Okta.listUsers
        next:
            - print_results
        properties: {}
        version_constraint: ~0
    print_results:
        id: aadbf530e35fc452a032f5f8acaaac2a
        properties:
            text_data: "${data['list_users.API_Integration.Custom_Okta.listUsers.body']}"
        version_constraint: ~1
output_fields: []
```

**Trigger types:**

| Type | Format |
|------|--------|
| On demand | `name: On demand`, `type: On demand` |
| Scheduled | `event: Schedule`, `schedule: {time_cycle: "0 */6 * * *", tz: Etc/UTC}` |

**Variable syntax in actions:** Use `${data['action_key.path.to.field']}` CEL expressions. See [Variable References](#variable-references) for the full syntax. Do NOT use `$action_name.output.body` — it passes as a literal string and is not resolved.

**Version constraints:** Every action requires `version_constraint`. Use `~0` for function actions and API integration actions. Use `~1` for platform actions (Print data, Send email, Create/Update variable, etc.):

```yaml
actions:
    my_function:
        id: functions.my-func.process
        properties: {}
        version_constraint: ~0       # ~0 for functions
    print_results:
        id: aadbf530e35fc452a032f5f8acaaac2a
        properties:
            text_data: "${data['my_function.output']}"
        version_constraint: ~1       # ~1 for platform actions
```

### Manifest Configuration

```yaml
# manifest.yml
workflows:
  - name: my-workflow
    path: workflows/my-workflow/workflow.yaml
    permissions: []
```

Trigger type and schedule are defined inside the workflow YAML file (via `trigger:` block), not in the manifest. The manifest only declares the workflow name, path, and optional permissions.

For full RTR multi-host orchestration and investigation pipeline examples, see [references/workflow-examples.md](references/workflow-examples.md).

> RTR scripts are not supported in certified Foundry apps (apps published to the CrowdStrike Store). RTR workflows work in custom/internal apps only.

## Calling Functions from Workflows

Functions referenced in workflow actions (via `id: functions.{name}.{handler}`) must have `workflow_integration` configured in the manifest. The `foundry functions create` CLI command handles this automatically when you specify the appropriate flags. Do not manually edit `manifest.yml` to add `workflow_integration` — use the CLI.

If a function was created without workflow integration and you later need it callable from workflows, delete and re-create it with the appropriate flags.

**Deploy error if missing:**
```
❌ Error: referenced function '{name}' and handler '{handler}' does not have workflow_integration properties defined
```

## Calling API Integration Operations

Workflows invoke API integration operations using the `api_integrations.{name}.{operationId}` pattern:

```yaml
actions:
    list_users_action:
        id: api_integrations.Okta.listUsers    # {name}.{operationId}
        properties: {}
        version_constraint: ~0
        next:
            - print_data

    print_data:
        id: aadbf530e35fc452a032f5f8acaaac2a
        properties:
            text_data: "${data['list_users_action.API_Integration.Custom_Okta.listUsers.body']}"
        version_constraint: ~1
```

The `{name}` must exactly match the `name` field from the `api_integrations` entry in `manifest.yml`, prefixed with `Custom_`. The platform adds `Custom_` to all API integration names in the variable path. The OpenAPI spec must have a matching `operationId` with a properly structured `x-cs-operation-config`:

```yaml
x-cs-operation-config:
  workflow:
    name: listUsers
    description: List all users
    expose_to_workflow: true
    system: false
```

The `workflow` nesting is required — a flat `expose_to_workflow: true` under `x-cs-operation-config` will not work. Auth scopes for CLI-created artifacts are managed automatically.

## Platform Actions

Platform actions (send email, log output, create detection) require platform-specific action IDs. These IDs are verified identical across us-1, us-2, and eu-1 clouds:

| Action Name | ID |
|------------|-----|
| Create variable | `702d15788dbbffdf0b68d8e2f3599aa4` |
| Update variable | `6c6eab39063fa3b72d98c82af60deb8a` |
| Print data | `aadbf530e35fc452a032f5f8acaaac2a` |
| Sleep | `4f1af1ae4c13dc1e3bcd725f8dc0f63b` |
| Send email | `07413ef9ba7c47bf5a242799f59902cc` |
| Request human input - Send email | `d6731c10b24834e2e0f4bd9d390a29c8` |
| Get device details | `6265dc947cc2252f74a5f25261ac36a9` |

For actions not in this table, use `foundry workflows actions view --name "..."` or the API query in [references/action-discovery.md](references/action-discovery.md). There are 9,000+ platform actions available. MUST NOT guess action IDs — use discovery commands.

### Common Action Properties

**Print data** (`aadbf530e35fc452a032f5f8acaaac2a`):

Print data has three input properties: `fields` (array — dropdown of trigger/workflow metadata), `text_data` (string — general-purpose), and `custom_json` (object only). Use `text_data` for API integration responses since `body` may be an array.

```yaml
    print_data:
        id: aadbf530e35fc452a032f5f8acaaac2a
        properties:
            text_data: "${data['list_users_action.API_Integration.Custom_Okta.listUsers.body']}"
        version_constraint: ~1
```

The data path follows the pattern: `action_key.API_Integration.Custom_{IntegrationName}.{operationId}.{field}`. The platform adds `Custom_` to all API integration names in the variable path. Use the **Workflow data** panel in the workflow editor to copy the exact path for any field — click the data pill and it copies the correct `${data['...']}` expression to your clipboard.

**Send email** (`07413ef9ba7c47bf5a242799f59902cc`):

Use Print data as the primary output action. Only add Send email when the user explicitly requests it. In headless/automated runs (`claude -p`), use Print data only — skip Send email entirely since the recipient cannot be prompted.

In interactive mode, when the user requests email, **ask for their email address via AskUserQuestion** before adding the Send email action. Never guess or infer the email from context. The `to` field must contain a real email address — placeholders like `user@example.com` cause workflow execution failure at runtime.

```yaml
    send_email:
        id: 07413ef9ba7c47bf5a242799f59902cc
        properties:
            to:
                - recipient@company.com    # Ask user for real address, or mark as parameterized
            subject: "Email subject"
            msg: "${data['list_users_action.API_Integration.Custom_Okta.listUsers.body']}"
            msg_type: "text"
        version_constraint: ~1
```

## Variable References

Falcon Fusion SOAR uses [Common Expression Language (CEL)](https://github.com/google/cel-spec/blob/master/doc/langdef.md) for data references. All variable references use `${data['...']}` expression syntax:

| Syntax | Description |
|--------|-------------|
| `${data['action_key.API_Integration.Custom_Name.operationId.body']}` | Response body from an API integration action |
| `${data['action_key.API_Integration.Custom_Name.operationId.body']}[0].field` | Access a field in the first element of an array response |
| `${data['action_key.output.field']}` | Field from a platform action's output |
| `${data['trigger.param_name']}` | On-demand trigger parameter value |

**CRITICAL:** Do NOT use `$action_name.output.body` — this passes as a literal string and is NOT resolved at runtime. Always use `${data['...']}` expressions.

The `action_key` is the YAML key of the action (e.g., `list_users` from `actions: list_users:`), NOT the action's `id`. The integration name in the variable path is `Custom_{name}` where `{name}` is the `name` field in your `api_integrations` manifest entry (spaces become underscores). Use the **Workflow data** panel in the workflow editor to copy exact data paths — it produces the correct expression when you click a data pill.

### CEL Expressions

Falcon Fusion SOAR supports CEL for data transformations, conditions, and field access. Key patterns:

```yaml
# Check if results exist before accessing
"${size(data['eventQuery.results']) > 0 ? data['eventQuery.results'][0].field : \"N/A\"}"

# Null-safe field access (CEL has no ?? operator — use ternary)
"${data['action.field'] != null ? data['action.field'] : \"default\"}"

# Array element access
"${data['action.API_Integration.Custom_Name.op.body']}[0]"
```

CrowdStrike provides [custom CEL extensions](https://docs.crowdstrike.com/r/k223d842) including `cs.json.valid()`, `cs.json.decode()`, and `cs.ip.valid()`. For complex transformations, the **Data Transformation Agent** (requires Charlotte AI) generates CEL expressions from plain language descriptions.

For schemaless event queries and dynamic data handling patterns, see [Falcon Fusion SOAR Event Queries: When and How to Go Schemaless](https://www.crowdstrike.com/tech-hub/ng-siem/falcon-fusion-soar-event-queries-when-and-how-to-go-schemaless/).

## Control Flow

**Loops** iterate over arrays or paginate with cursor-based conditions. Loops are self-contained sub-workflows at the root `loops:` level:

```yaml
loops:
    DeviceLoop:
        for:
            input: device_query.Device.query.devices
            continue_on_partial_execution: true
            sequential: true
        trigger:
            next:
                - get_device_details
        actions:
            get_device_details:
                id: 6265dc947cc2252f74a5f25261ac36a9
                next:
                    - platform_check
                properties:
                    device_id: "${device_query.Device.query.devices.#}"
                version_constraint: ~1
        conditions:
            platform_check:
                next:
                    - remediate
                expression: get_device_details.Device.GetDetails.Platform:'Windows'
                display:
                    - Platform is Windows
                else:
                    - skip_device
```

**Conditions** use FQL-style `expression:` or CEL `cel_expression:` with optional `else:` for fallback routing:

```yaml
conditions:
    has_detection:
        next:
            - GetDetectionDetails
        cel_expression: has(data['detection_id']) && data['detection_id'] != ''
        display:
            - Detection ID was provided
        else:
            - PrintSummary
```

See [references/workflow-examples.md](references/workflow-examples.md) for full loop and condition examples from production apps.

## The "0" Gotcha

See [pagination-patterns](references/pagination-patterns.md#the-0-gotcha) for the "0" gotcha and fix pattern. Key point: check for both null and `"0"` in loop conditions.

## Workflow Name Uniqueness

Workflow names must be unique across all apps in the same tenant. If two apps deploy workflows with the same name, the second deploy fails silently or produces an "Unknown error." Use app-specific prefixes when the workflow name is generic.

## Workflow Sharing

```yaml
workflows:
  - name: my-workflow
    path: workflows/my-workflow/workflow.yaml
    workflow_integration:
      id: <generated-id>
      disruptive: false
      system_action: true   # true = app workflows only, false = also available as Fusion SOAR action
```

## Error Handling

Foundry workflows handle errors through conditional routing and action-level flags — not `onError` blocks or retry middleware.

| Mechanism | Scope | Usage |
|-----------|-------|-------|
| `fail_fast_enabled: false` | Function actions | Allow workflow to continue if a function call fails |
| `continue_on_partial_execution: true` | Loop `for:` block | Continue loop if individual iterations fail |
| `continue_on_partial_execution: false` | Loop `for:` block | Stop entire loop on first failure (default safe choice) |
| `conditions:` with `else:` | Action routing | Route to fallback action when condition is false |

```yaml
# Function-level: suppress non-critical failures
actions:
    enrich_data:
        id: functions.enrichment.Enrich
        properties:
            fail_fast_enabled: false
        version_constraint: ~0
        next:
            - process_results

# Loop-level: stop on first error
loops:
    ContainDevices:
        for:
            input: device_ids
            continue_on_partial_execution: false
            sequential: true
```

No built-in retry or exponential backoff exists. For pagination polling, use a `loops:` block with a cursor variable — see [references/pagination-patterns.md](references/pagination-patterns.md).

## Testing

```bash
foundry workflows triggers view --mock       # Example mock trigger
foundry workflows actions view --mock        # Example mock action
foundry workflows executions validate --mocks mymocks.json              # Validate mocks
foundry workflows executions start --definition my-workflow --mocks mymocks.json  # Run with mocks
foundry workflows executions view <execution_id>                        # View results
```

Use `foundry apps validate --no-prompt` to validate the manifest and schemas without deploying. Workflow YAML semantics are still validated server-side on deploy.

## Reading Guide

| Task | Reference |
|------|-----------|
| Full workflow examples (RTR, investigation) | [references/workflow-examples.md](references/workflow-examples.md) |
| Platform action discovery via API | [references/action-discovery.md](references/action-discovery.md) |
| Charlotte AI and CEL expressions | [references/action-discovery.md](references/action-discovery.md) |
| CEL syntax, schemaless queries, dynamic data | [Falcon Fusion SOAR Event Queries: When and How to Go Schemaless](https://www.crowdstrike.com/tech-hub/ng-siem/falcon-fusion-soar-event-queries-when-and-how-to-go-schemaless/) |
| CEL extension functions reference | [Data Transformation Functions](https://docs.crowdstrike.com/r/k223d842) |
| Pagination strategies | [references/pagination-patterns.md](references/pagination-patterns.md) |
| HTTP Request actions, testing, validation | [references/advanced-patterns.md](references/advanced-patterns.md) |
| Parameterized fields versioning | [references/advanced-patterns.md](references/advanced-patterns.md) |
| Counter-rationalizations and red flags | [references/advanced-patterns.md](references/advanced-patterns.md) |

## Use Cases

For real-world implementation patterns, see:
- [schemaless-queries.md](../../use-cases/schemaless-queries.md) — CEL expressions, dynamic data, Event Query configuration
- [api-pagination.md](../../use-cases/api-pagination.md) — Pagination strategies in functions and workflows
- [custom-soar-actions.md](../../use-cases/custom-soar-actions.md) — Custom Falcon Fusion SOAR actions

## Reference Implementations

- **[foundry-sample-threat-intel](https://github.com/CrowdStrike/foundry-sample-threat-intel)**: Threat intelligence workflows with pagination
- **[foundry-sample-rapid-response](https://github.com/CrowdStrike/foundry-sample-rapid-response)**: Rapid response automation
- **[foundry-sample-scalable-rtr](https://github.com/CrowdStrike/foundry-sample-scalable-rtr)**: Scalable RTR orchestration
- **[foundry-sample-ngsiem-importer](https://github.com/CrowdStrike/foundry-sample-ngsiem-importer)**: Threat intel import for NG-SIEM
