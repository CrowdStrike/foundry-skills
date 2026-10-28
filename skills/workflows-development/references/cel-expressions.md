# CEL Expressions Reference

> Parent skill: [workflows-development](../SKILL.md)

Falcon Fusion SOAR uses [Common Expression Language (CEL)](https://github.com/google/cel-spec/blob/master/doc/langdef.md) for data transformations, conditions, and field access. All variable references use `${data['...']}` expression syntax.

## Common Patterns

```yaml
# Check that results exist before accessing them (null-check before size())
"${data['eventQuery.results'] != null && size(data['eventQuery.results']) > 0 ? data['eventQuery.results'][0].field : \"N/A\"}"

# Null-safe field access
"${data['action.field'] != null ? data['action.field'] : \"default\"}"

# Array element access (index goes INSIDE the ${...}, not after it)
"${data['action.API_Integration.Custom_Name.op.body'][0]}"

# Lookup table (map literal needs its own braces inside ${...})
"${ {'1': 'Low', '2': 'Medium', '3': 'High', '4': 'Critical'}[string(data['severity'])] }"
```

## `has()` vs `!= null` — know the difference

- `data['key'] != null` — checks if a **data store key** has a value. Use for trigger parameters and action outputs.
- `has(obj.field)` — checks if a **field exists on a retrieved object**. Only works *after* you've retrieved an object from the data store (e.g., `has(data['WorkflowCustomVariable'].offset)` works because CEL first retrieves `WorkflowCustomVariable` then checks `.offset`). Do NOT use `has(data['key'])` directly on the data store — this fails with `Q0910: invalid argument to has() macro`.

## CrowdStrike CEL Extensions

CrowdStrike provides [custom CEL extensions](https://docs.crowdstrike.com/r/k223d842) including `cs.json.valid()`, `cs.json.decode()`, `cs.ip.valid()`, `cs.timestamp.now()`, and `cs.timestamp.parse()`. For complex transformations, the **Data Transformation Agent** (requires Charlotte AI) generates CEL expressions from plain language descriptions.

For schemaless event queries and dynamic data handling patterns, see [Falcon Fusion SOAR Event Queries: When and How to Go Schemaless](https://www.crowdstrike.com/tech-hub/ng-siem/falcon-fusion-soar-event-queries-when-and-how-to-go-schemaless/).

## Variable reference forms

All references use `${data['...']}` syntax. The `action_key` is the YAML key of the action (e.g. `list_users`), NOT its `id`.

| Syntax | Description |
|--------|-------------|
| `${data['action_key.API_Integration.Custom_Name.Workflow_name.body']}` | Response body from an API integration action |
| `${data['action_key.API_Integration.Custom_Name.Workflow_name.body'][0].field}` | A field in the first element of an array response (index inside the `${...}`) |
| `${data['action_key.Device.GetDetails.Platform']}` | Platform action output, namespaced by action type (Put and run file: `action_key.RTR.PutAndRun.stdout`) |
| `${data['action_key.response']}` | Reply from an app's own AI agent (`ai_agents.<agent name>`); no `.output` segment. A `json_with_schema` agent has no `response`: use `${data['action_key.<schema field>']}` |
| `${data['action_key.FaaS.<function>.<handler>.<field>']}` | Function action output; a loop item's field is `...<field>.#.<item field>` |
| `${data['param_name']}` | On-demand trigger parameter value (name directly, no prefix) |

The integration name in the path is `Custom_{name}` where `{name}` is the `api_integrations` manifest `name` (spaces become underscores). The segment after it is not the `operationId`: it's the operation's `x-cs-operation-config.workflow.name`, spaces become underscores (`Workday get leavers data` → `Workday_get_leavers_data`). Copy exact paths from the editor's **Workflow data** panel.

### Null-safe and array access

```yaml
# Null check
"${data['action.field'] != null ? data['action.field'] : \"default\"}"

# Array element access (index goes INSIDE the ${...}, not after it)
"${data['action.API_Integration.Custom_Name.op.body'][0]}"
```

## Null-guard trigger parameters

When run from the Falcon console the UI prompts for parameters, but via API or from another workflow they may be empty. Guard with a `conditions:` branch:

```yaml
conditions:
    check_param:
        cel_expression: "data['param_name'] != null && data['param_name'] != ''"
        next:
            - use_param
        display:
            - param_name was provided
        else:
            - handle_missing
```

Or inline in CEL with a ternary: `${data['param'] != null ? data['param'] : "default"}`.
