# Workflow Examples Reference

> Parent skill: [workflows-development](../SKILL.md)

Real examples from the foundry-sample repos. All examples use the actual Fusion YAML schema: `trigger` + `actions` + optional `loops`/`conditions`.

## Simple On-Demand Workflow

From [foundry-sample-foundryjs-demo](https://github.com/CrowdStrike/foundry-sample-foundryjs-demo). On-demand trigger with parameter, CreateVariable/UpdateVariable state management, and Print data output.

```yaml
name: Simple Greeting Workflow
description: A simple workflow that accepts a name parameter and returns a personalized greeting
provision_on_install: true
trigger:
    next:
        - CreateVariable
    name: On demand
    parameters:
        properties:
            user_name:
                type: string
        type: object
    type: On demand
actions:
    CreateVariable:
        next:
            - UpdateVariable
        id: 702d15788dbbffdf0b68d8e2f3599aa4
        class: CreateVariable
        properties:
            variable_schema:
                properties:
                    result:
                        type: string
                type: object
        version_constraint: ~1
    UpdateVariable:
        id: 6c6eab39063fa3b72d98c82af60deb8a
        class: UpdateVariable
        next:
            - PrintData
        properties:
            WorkflowCustomVariable:
                result: Hello, ${data['user_name']}! Welcome to the Foundry workflow demo.
        version_constraint: ~1
    PrintData:
        id: aadbf530e35fc452a032f5f8acaaac2a
        properties:
            fields:
                - ${WorkflowCustomVariable.result}
        version_constraint: ~1
```

**Patterns demonstrated:**
- `provision_on_install: true` for auto-provisioning on app install
- `parameters:` on trigger for user inputs, referenced as `${data['user_name']}`
- `CreateVariable` → `UpdateVariable` → `PrintData` state management chain
- `class` + `version_constraint: ~1` required on class-based actions

## API Integration Workflow

Pattern for calling an API integration operation from a workflow. The `id` uses `api_integrations.{name}.{operationId}` where `{name}` matches the manifest entry.

```yaml
name: list-okta-users
description: On-demand workflow to list Okta users
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

**Patterns demonstrated:**
- API integration action ID format: `api_integrations.{name}.{operationId}`
- `${data['action_key.API_Integration.Custom_Name.Workflow_name.body']}` to access the API response body, where `Workflow_name` is the operation's `x-cs-operation-config.workflow.name` with spaces turned into underscores (here it's `listUsers`, the same as the `operationId`, but the two often differ). Copy the path from the editor's **Workflow data** panel
- `output_fields: []` when no fields need to be surfaced

## Response Action Workflow (Contain Host)

Platform response actions (contain device, lift containment, create IOC) use discovered action IDs. To find the ID, run:

```bash
foundry workflows actions view --name "contain" --no-prompt
```

This example demonstrates an on-demand workflow that contains a host by device ID, with a null-guard condition to prevent runtime errors when the parameter is empty.

```yaml
name: Contain Malicious Host
description: On-demand workflow to network-contain a host by device ID
provision_on_install: true
trigger:
    next:
        - validate_device_id
    name: On demand
    parameters:
        properties:
            device_id:
                type: string
        type: object
    type: On demand
actions:
    contain_host:
        id: bec9fbeb4999d207937854fd56088107
        next:
            - print_result
        properties:
            device_id: "${data['device_id']}"
        version_constraint: ~0
    print_result:
        id: aadbf530e35fc452a032f5f8acaaac2a
        properties:
            text_data: "Containment initiated for device ${data['device_id']}"
        version_constraint: ~1
conditions:
    validate_device_id:
        cel_expression: "data['device_id'] != null && data['device_id'] != ''"
        next:
            - contain_host
        display:
            - device_id was provided
        else:
            - print_result
```

**Patterns demonstrated:**
- Discovering platform actions via `foundry workflows actions view --name "..." --no-prompt`
- `conditions:` with `cel_expression:` for null-guarding trigger parameters
- `else:` routing to a fallback action when the parameter is missing
- Response action pattern with a real platform action ID (`bec9fbeb4999d207937854fd56088107` = Contain device)
- CEL null-guard: `data['field'] != null && data['field'] != ''`

> **⚠️ Always discover action IDs** — do NOT guess or hardcode IDs from this example for other actions. Use `foundry workflows actions view --name "..." --no-prompt` or the API query in [action-discovery.md](action-discovery.md) to find the correct ID for your specific use case.

## Scheduled Workflow with Pagination Loop

Adapted from the original single-loop version of [foundry-sample-anomali-threatstream](https://github.com/CrowdStrike/foundry-sample-anomali-threatstream)'s `Anomali_Threat_Intelligence_Ingest.yml` (the current sample runs one branch per IOC type). Scheduled trigger with loop-based pagination using a custom variable to track the cursor.

```yaml
name: Anomali Threat Intelligence Ingest
description: Anomali ThreatStream IOC ingestion on schedule every hour
parameters: {}
provision_on_install: true
trigger:
    next:
        - CreateVariable
    event: Schedule
    schedule:
        time_cycle: 0 0/1 * * *
        start_date: ""
        end_date: ""
        tz: Etc/UTC
        skip_concurrent: true
actions:
    AnomaliIngest:
        next:
            - UpdateVariable
        id: functions.anomali-ioc-ingest.Anomali Ingest
        properties:
            limit: 1000
            repository: search-all
            status: active
        version_constraint: ~0
    CreateVariable:
        next:
            - AnomaliIngest
        id: 702d15788dbbffdf0b68d8e2f3599aa4
        class: CreateVariable
        properties:
            variable_schema:
                properties:
                    next:
                        type: string
                type: object
        version_constraint: ~1
    UpdateVariable:
        next:
            - Loop
        id: 6c6eab39063fa3b72d98c82af60deb8a
        class: UpdateVariable
        properties:
            WorkflowCustomVariable:
                next: ${data['AnomaliIngest.FaaS.anomali-ioc-ingest.AnomaliIngest.next']}
        version_constraint: ~1
loops:
    Loop:
        display: While next exists And next is not equal to 0; 500 iterations; 2 hour limit
        for:
            input: ""
            condition: WorkflowCustomVariable.next:!null+WorkflowCustomVariable.next:!'0'
            condition_display:
                - next exists
                - next is not equal to 0
            continue_on_partial_execution: false
            max_execution_seconds: 7200
            max_iteration_count: 500
            sequential: true
        trigger:
            next:
                - AnomaliIngest2
        actions:
            AnomaliIngest2:
                next:
                    - UpdateVariable2
                id: functions.anomali-ioc-ingest.Anomali Ingest
                properties:
                    limit: 1000
                    next: ${data['WorkflowCustomVariable.next']}
                    repository: search-all
                    status: active
                version_constraint: ~0
            UpdateVariable2:
                id: 6c6eab39063fa3b72d98c82af60deb8a
                class: UpdateVariable
                properties:
                    WorkflowCustomVariable:
                        next: ${data['AnomaliIngest2.FaaS.anomali-ioc-ingest.AnomaliIngest.next']}
                version_constraint: ~1
```

**Patterns demonstrated:**
- `event: Schedule` with `schedule:` block for cron-based triggers
- `skip_concurrent: true` prevents overlapping executions
- Pagination loop: `condition:` checks `WorkflowCustomVariable.next:!null` (FQL-style)
- The "0" gotcha: also check `WorkflowCustomVariable.next:!'0'` (see [pagination-patterns.md](pagination-patterns.md))
- Loop has its own `trigger:`, `actions:` — a self-contained sub-workflow
- Function action ID format: `functions.{function-name}.{display-name}`
- `max_iteration_count` / `max_execution_seconds` raise the While-loop limits; without them a sequential loop stops at the default 50 iterations or 60 minutes, whichever comes first

## Conditions with Loops

From [foundry-sample-rapid-response](https://github.com/CrowdStrike/foundry-sample-rapid-response). Loop over devices with platform-based conditional branching inside the loop.

```yaml
# Simplified from Install_software_Job_Template.yml
loops:
    DeviceLoop:
        for:
            input: device_query.Device.query.devices
            continue_on_partial_execution: true
        trigger:
            next:
                - get_device_details
        actions:
            get_device_details:
                next:
                    - platform_is_windows
                id: 6265dc947cc2252f74a5f25261ac36a9
                properties:
                    device_id: "${device_query.Device.query.devices.#}"
                version_constraint: ~1
            put_and_run_file:
                id: a29b38809708ffc5fb18a03676520b1a
                properties:
                    device_id: "${device_query.Device.query.devices.#}"
                    file_name: installer.exe
                version_constraint: ~1
        conditions:
            platform_is_windows:
                next:
                    - put_and_run_file
                expression: get_device_details.Device.GetDetails.Platform:'Windows'
                display:
                    - Platform is equal to Windows
```

**Patterns demonstrated:**
- `conditions:` block inside a loop, alongside `actions:`
- `expression:` uses FQL-style syntax for field matching
- `display:` provides human-readable description shown in Falcon console
- `${array.#}` references the current loop iteration item
- `continue_on_partial_execution: true` on a concurrent loop (no `sequential: true`) — nodes after the loop still run if some iterations fail, though the execution still shows as failed

## Workflow with Collection Config Lookup

Pattern for workflows that read user-configured settings from a collection before performing an action. Use when the app has a settings UI page where users configure values (channels, thresholds, emails) that the workflow needs at runtime.

```yaml
name: Send Alert to Configured Channel
description: On-demand workflow that reads channel config from collection then sends alert
provision_on_install: true
trigger:
    next:
        - get_config
    name: On demand
    parameters:
        properties:
            alert_name:
                type: string
            severity:
                type: string
            description:
                type: string
        type: object
    type: On demand
actions:
    get_config:
        id: functions.get-channel-config.get_config
        next:
            - send_alert
        properties: {}
        version_constraint: ~0
    send_alert:
        id: api_integrations.SlackAPI.chatPostMessage
        next:
            - print_result
        properties:
            channel: "${data['get_config.FaaS.get-channel-config.get_config.channel_id']}"
            text: "Alert: ${data['alert_name']} (${data['severity']})"
        version_constraint: ~0
    print_result:
        id: aadbf530e35fc452a032f5f8acaaac2a
        properties:
            text_data: "Alert sent to configured channel"
        version_constraint: ~1
```

**Patterns demonstrated:**
- Function reads config from collection, returns it as output for downstream actions
- Workflow uses function output (`data['get_config.FaaS...']`) rather than requiring the value as a trigger parameter
- Settings UI page writes to collection; workflow reads from it at runtime via a function
- User doesn't need to pass the channel every time -- it's pre-configured

The `get-channel-config` function reads from the collection using the `CustomStorage` service class — see the Collection CRUD pattern in [functions-development](../../functions-development/references/python-patterns.md).

> **When to use this pattern:** If the app has a settings/config UI page AND a workflow that needs those settings, the workflow should call a function that reads from the collection rather than requiring the user to pass config values as trigger parameters every time.

## Data Reference Quick Reference

| Syntax | Description |
|--------|-------------|
| `${data['param_name']}` | On-demand trigger parameter |
| `${data['array_param.#']}` | Current loop item (simple array) |
| `${data['array_param.#.field']}` | Field of current loop item |
| `${data['ActionLabel.OutputField']}` | Output from a prior action |
| `${data['WorkflowCustomVariable.field']}` | Custom variable value |
| `${data['action_key.API_Integration.Custom_Name.Workflow_name.body']}` | API integration response body (`Workflow_name` from `x-cs-operation-config.workflow.name`, spaces → underscores) |
| `${Workflow.Execution.ID}` | Current execution ID |
| `${Workflow.Execution.Time.Date}` | Execution date |

> **Note:** Always use `${data['...']}` CEL expression syntax. The older `$action.output.field` syntax passes as a literal string and is not resolved at runtime. See the parent SKILL.md [Variable References](#variable-references) section for full details.

## Standard trigger actions format

The format produced by `foundry workflows create`, used by many Foundry sample apps:

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

## Version constraint example

`~N` is the major version of the activity's `semantic_version`: `~0` when it has none (functions, API integrations) or a `0.x` one (Contain device), `~1` for `1.x` (most platform actions):

```yaml
actions:
    my_function:
        id: functions.my-func.process
        properties: {}
        version_constraint: ~0       # no semantic_version defined
    contain_host:
        id: bec9fbeb4999d207937854fd56088107    # Contain device
        properties:
            device_id: "${data['device_id']}"
        version_constraint: ~0       # semantic_version 0.0.x
    print_results:
        id: aadbf530e35fc452a032f5f8acaaac2a
        properties:
            text_data: "${data['my_function.FaaS.my-func.process.result']}"
        version_constraint: ~1       # semantic_version 1.x
```

## API integration operation call

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

The matching OpenAPI `operationId` needs an `x-cs-operation-config` with the workflow config nested under a `workflow:` key (a flat `expose_to_workflow: true` will not work):

```yaml
x-cs-operation-config:
  workflow:
    name: listUsers
    description: List all users
    expose_to_workflow: true
    system: false
```

## Send email action

Use Print data as the primary output; add Send email only when explicitly requested (skip entirely in headless runs). The `to` field must be a real address — placeholders like `user@example.com` fail at runtime:

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

## Control flow: loop and condition examples

**Loop** — a self-contained sub-workflow at the root `loops:` level; the action before it must name it in `next:` or it never runs:

```yaml
loops:
    DeviceLoop:
        for:
            input: device_query.Device.query.devices
            continue_on_partial_execution: true
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
            put_and_run_file:
                id: a29b38809708ffc5fb18a03676520b1a
                properties:
                    device_id: "${device_query.Device.query.devices.#}"
                    file_name: installer.exe
                version_constraint: ~1
        conditions:
            platform_check:
                next:
                    - put_and_run_file
                expression: get_device_details.Device.GetDetails.Platform:'Windows'
                display:
                    - Platform is Windows
```

The condition has no `else:`, so nothing runs for a device that isn't Windows. An `else:` must name an action, condition, or loop defined in the same block.

**Condition** — FQL-style `expression:` or CEL `cel_expression:` with an optional `else:` fallback:

```yaml
conditions:
    has_detection:
        next:
            - GetDetectionDetails
        cel_expression: data['detection_id'] != null && data['detection_id'] != ''
        display:
            - Detection ID was provided
        else:
            - PrintSummary
```
