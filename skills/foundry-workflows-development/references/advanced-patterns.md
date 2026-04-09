# Advanced Patterns Reference

> Parent skill: [foundry-workflows-development](../SKILL.md)

## Parameterized Fields Versioning Impact

Workflow templates support parameterized fields — values that users configure when provisioning a workflow from the template. Check the "Parameterized" checkbox in the App Builder to mark fields as configurable.

| Change | Release Type |
|--------|-------------|
| Parameterized → Non-parameterized | Minor release |
| Non-parameterized → Parameterized | **Major release** (breaking change) |

## HTTP Request Action Patterns

Workflows can make HTTP requests to external APIs using three action types:

| Type | Target | Auth |
|------|--------|------|
| **Cloud** | External APIs (VirusTotal, Slack, etc.) | API Key or OAuth 2.0 |
| **CrowdStrike** | CrowdStrike APIs | Automatic (uses app's OAuth) |
| **On-Premises** | Internal/on-prem APIs via RTR relay | API Key or OAuth 2.0 |

**Key constraints:**
- 30-second timeout per HTTP action
- 10 MB maximum response size
- Response must be a JSON object (not array or primitive)
- Authentication configuration is **immutable after creation** (delete and recreate to change)

```yaml
- name: enrich_ip
  activity: httpRequest
  config:
    type: cloud
    method: GET
    url: "https://api.greynoise.io/v3/community/${inputs.ip_address}"
    headers:
      key: "GREYNOISE-API-KEY"
      Accept: "application/json"
    auth:
      type: api_key
      header_name: "key"
      value: "${secrets.greynoise_key}"
```

## Step-Level Testing

Test individual Functions independently before workflow integration (requires Docker):

```bash
# Test the aggregation function
foundry functions run

# Test a specific function by name
foundry functions run --name aggregate-rtr-results
```

## Workflow Validation (without execution)

```bash
# Validate a workflow definition with mock data
foundry workflows executions validate --definition my-workflow --mocks mocks.json
```

## End-to-End Testing

```bash
# Start a workflow execution with mock data and wait for completion
foundry workflows executions start --definition my-workflow --mocks mocks.json --wait-for 30

# Check execution status
foundry workflows executions view
```

> **Note:** There is no CLI command to query collections directly. Collection data can be verified through the Falcon console or via function code that reads the collection.

## YAML Validation

```bash
# Validate OpenAPI specs referenced by workflows
npx @redocly/cli lint api-integrations/MyApi.yaml
```

> **Note:** There is no local validator for manifest.yml or workflow YAML semantics — validation happens server-side on `foundry apps deploy`. Use `npx @redocly/cli lint` for OpenAPI spec validation. Do NOT use Python/Ruby YAML parsers — they only check syntax, not OpenAPI structure.

## Timeout Configuration

```yaml
- name: long_running_step
  activity: invokeFunction
  config:
    functionName: heavy-processor
  timeout: 300  # 5 minutes per step
```

## Platform Action Fallback Strategy

If you don't know the exact action name:
1. Try common names with `--name` (e.g., `"send email"`, `"log"`, `"create detection"`)
2. Query the API directly with a fuzzy search (see [action-discovery.md](action-discovery.md))
3. If that fails, set `provision_on_install: false` and add a YAML comment for the user to configure in the Falcon console's App Builder
4. Only use `provision_on_install: true` when ALL action IDs in the workflow are valid

```yaml
# workflows/List_okta_users.yml
name: List Okta Users
description: On-demand workflow that lists Okta users
# Set to false because some actions need platform docIDs configured in App Builder
provision_on_install: false

trigger:
    next:
        - list_users_action

actions:
    list_users_action:
        id: api_integrations.Okta.listUsers    # This works — built from manifest
        properties: {}
        version_constraint: ~0

    # TODO: Configure this action in Falcon App Builder — use
    # foundry workflows actions view --name "send email" to discover the action ID
    # send_notification:
    #     id: <find via foundry workflows actions view --name "..." or App Builder>
    #     properties: {}
```

> **Common mistake:** Guessing platform action IDs (e.g., `send_email`, `log`). These are not valid. Use `foundry workflows actions view --name "..."` to discover valid IDs, use the `api_integrations.{name}.{operationId}` pattern for API integration actions, or set `provision_on_install: false` and configure platform actions in the Falcon console.

## Counter-Rationalizations Table

| Your Excuse | Reality |
|-------------|---------|
| "YAML is simple, I don't need patterns" | Fusion YAML has execution semantics that standard YAML doesn't |
| "I can chain API calls directly in code" | Workflows handle retries, state persistence, and parallelism automatically |
| "I'll add error handling later" | Workflow failures without onError blocks corrupt state and lose context |
| "RTR is just like SSH" | RTR has session management, host targeting, and result aggregation built-in |
| "forEach is overkill for small lists" | forEach with maxConcurrency prevents API rate limiting and resource exhaustion |
| "Conditional logic belongs in Functions" | Workflow-level conditionals skip steps entirely, saving execution time |

## Red Flags - STOP Immediately

If you catch yourself:
- Writing raw API call chains in Functions instead of workflow steps
- Creating multi-step workflows without onError blocks
- Hardcoding host IDs instead of using host groups or dynamic queries
- Using unbounded parallel execution without maxConcurrency
- Storing secrets in workflow YAML instead of environment variables

**STOP. Follow the patterns above. No shortcuts.**

## Integration with Other Skills

- **foundry-development-workflow:** Workflows are delegated from the orchestrator
- **foundry-functions-development:** Workflows invoke Functions via `invokeFunction` activity
- **foundry-collections-development:** Workflows read/write Collections via `readCollection`/`writeCollection`
- **foundry-api-integrations:** Workflows call external APIs via registered integrations
- **foundry-functions-falcon-api:** Functions called by workflows use Falcon APIs
- **foundry-security-patterns:** Apply permission scoping to workflow activities; validate inputs

## External References

- [API Pagination Strategies for Falcon Foundry Functions and Workflows](https://www.crowdstrike.com/tech-hub/ng-siem/api-pagination-strategies-for-falcon-foundry-functions-and-workflows/)
- [Build API Integrations with Falcon Fusion SOAR HTTP Actions](https://www.crowdstrike.com/tech-hub/ng-siem/build-api-integrations-with-falcon-fusion-soar-http-actions/)
