# Advanced Patterns Reference

> Parent skill: [workflows-development](../SKILL.md)

## Testing Workflows

```bash
foundry workflows triggers view --mock --no-prompt       # Example mock trigger
foundry workflows actions view --mock --no-prompt        # Example mock action
foundry workflows executions validate --mocks mymocks.json              # Validate mocks
foundry workflows executions start --definition my-workflow --mocks mymocks.json  # Run with mocks
foundry workflows executions view <execution_id>                        # View results
```

Use `foundry apps validate --no-prompt` to validate the manifest and schemas without deploying. Workflow YAML semantics are still validated server-side on deploy.

`executions start` always runs a mock execution of the workflow YAML (`--mocks` is required with `--no-prompt`; an empty `{}` file mocks nothing). It doesn't resolve an app's own references, so an unmocked `functions.<name>.<handler>` action fails with `error code 1202: action not found` even when the deployed app works. Test those workflows through the installed app instead: an on-demand trigger can be run from the workflow in Falcon Fusion, while a scheduled one can't be started by hand, so give it a near-term `time_cycle` for the test and restore the real schedule afterward.

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
| **On-Premises** | Internal/on-prem APIs via host group | API Key or OAuth 2.0 |

**Key constraints:**
- 30-second timeout per HTTP action
- 10 MB maximum response size
- Response must be a JSON object (not array or primitive)
- Authentication configuration is **immutable after creation** (delete and recreate to change)

The action class is `Inline.HTTPRequest`. It references a credential configuration created in the Falcon console (via `config_id`/`definition_id`), not inline secrets. For the verified YAML schema, both auth patterns (API key header and OAuth 2.0), and status-code conditional routing, see [http-actions.md](http-actions.md).

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

> **Note:** Use `foundry apps validate --no-prompt` to validate the manifest and schemas without deploying. Workflow YAML semantics are still validated server-side on deploy. Use `npx @redocly/cli lint` for OpenAPI spec validation. Do NOT use Python/Ruby YAML parsers — they only check syntax, not OpenAPI structure.

## Timeout Configuration

```yaml
- name: long_running_step
  activity: invokeFunction
  config:
    functionName: heavy-processor
  timeout: 300  # 5 minutes per step
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

No built-in retry or exponential backoff exists. For pagination polling, use a `loops:` block with a cursor variable — see [pagination-patterns.md](pagination-patterns.md).

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
    # foundry workflows actions view --name "send email" --no-prompt to discover the action ID
    # send_notification:
    #     id: <find via foundry workflows actions view --name "..." --no-prompt or App Builder>
    #     properties: {}
```

> **Common mistake:** Guessing platform action IDs (e.g., `send_email`, `log`). These are not valid. Use `foundry workflows actions view --name "..." --no-prompt` to discover valid IDs, use the `api_integrations.{name}.{operationId}` pattern for API integration actions, or set `provision_on_install: false` and configure platform actions in the Falcon console.

## Diamond joins & the 2001 cyclic reference

Fusion builds a DAG. A node inside a parallel branch must not reach a downstream join **both directly and through a child** — Fusion treats that as a cycle and fails the deploy with `2001 cyclic reference to previously seen node`. This bites whenever one parallel sibling also feeds another sibling that converges on the same join.

**❌ Fails — `Services` fans to the `ELP` join both directly and via `Partner`:**

```yaml
actions:
    ExecSummary:
        next: [Services, ModuleGap]
    Services:
        next: [ELP, Partner]      # direct edge to the join …
    Partner:
        next: [ELP]               # … AND via a child → cycle
    ModuleGap:
        next: [ELP]
    ELP:
        next: [StoreResults]
# → 2001 cyclic reference to previously seen node … FROM_Partner_TO_parallel_Services
```

**✅ Fixed — linearize the `Services → Partner` leg so each node is a single-path ancestor of the join:**

```yaml
actions:
    ExecSummary:
        next: [Services, ModuleGap]
    Services:
        next: [Partner]           # linear chain, no direct ELP edge
    Partner:
        next: [ELP]
    ModuleGap:
        next: [ELP]
    ELP:
        next: [StoreResults]
```

`Services`' data pill still reaches `ELP` because `Services` remains an ancestor via `Partner` — you do **not** need the direct edge, and adding it is exactly what creates the cycle.

**Silent variant — the empty pill.** The same shape fails *without any error* when a store/aggregator reads `${data['X.response']}` off a node `X` that sits on a diamond fork: at the join the pill resolves to an **empty string**, not an error, so the workflow "succeeds" with blank data. The fix is identical — make any node whose `.response` you read a single-path ancestor of the reader (linearize the fork), never a shared fork feeding the join two ways.

## Counter-Rationalizations Table

| Your Excuse | Reality |
|-------------|---------|
| "YAML is simple, I don't need patterns" | Fusion YAML has execution semantics that standard YAML doesn't |
| "I can chain API calls directly in code" | Workflows handle state persistence and parallelism automatically |
| "I'll add error handling later" | Without conditional routing on `Workflow.Execution.Errors` and loop `continue_on_partial_execution`, failures abort the workflow and lose context |
| "RTR is just like SSH" | RTR has session management, host targeting, and result aggregation built-in |
| "A loop is overkill for small lists" | Sequential loops keep stateful and rate-limited actions from racing each other |
| "Conditional logic belongs in Functions" | Workflow-level conditionals skip steps entirely, saving execution time |

## Red Flags - STOP Immediately

If you catch yourself:
- Writing raw API call chains in Functions instead of workflow steps
- Creating multi-step workflows without error routing (conditional branches on `Workflow.Execution.Errors`)
- Hardcoding host IDs instead of using host groups or dynamic queries
- Using concurrent loops (`sequential: false`) for stateful or rate-limited actions that should run sequentially
- Storing secrets in workflow YAML instead of environment variables

**STOP. Follow the patterns above. No shortcuts.**

## Integration with Other Skills

- **development-workflow:** Workflows are delegated from the orchestrator
- **functions-development:** Workflows invoke Functions via `invokeFunction` activity
- **collections-development:** Workflows read/write Collections via `readCollection`/`writeCollection`
- **api-integrations:** Workflows call external APIs via registered integrations
- **functions-falcon-api:** Functions called by workflows use Falcon APIs
- **security-patterns:** Apply permission scoping to workflow activities; validate inputs

## External References

- [API Pagination Strategies for Falcon Foundry Functions and Workflows](https://www.crowdstrike.com/tech-hub/ng-siem/api-pagination-strategies-for-falcon-foundry-functions-and-workflows/)
- [Build API Integrations with Falcon Fusion SOAR HTTP Actions](https://www.crowdstrike.com/tech-hub/ng-siem/build-api-integrations-with-falcon-fusion-soar-http-actions/)

## Sticky-409 recovery

Any structural edit that re-provisions a workflow (new action, edited `next`/edge, added trigger parameter, rename) can 409 with `Duplicate workflow name` / `system definition with id … already provisioned on cid …`. Deleting the Fusion workflow does NOT free the name — a used name stays reserved. Reliable escape — rename to a brand-new unique name AND strip the id:

1. In `workflows/*.yaml`, change `name:` to a new, never-used value.
2. In `manifest.yml`, change the matching `workflows: - name:` to that same new value AND delete the entry's `id:`.
3. Deploy. Foundry provisions a fresh workflow and writes a new `id` back into the manifest (commit it). The old workflow is a harmless orphan.
4. If the UI triggers the workflow by name, update the `WORKFLOW_NAME` constant(s) — a stale name is a silent 404 at run time.

Stripping the `id` alone is not enough; the name is what's reserved. Rename + id-strip together forces a clean re-provision — no fresh app needed.
