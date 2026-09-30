# Calling an app's agent from its own workflow

Reference the agent in the workflow template as `ai_agents.<agent name>`, where the name is the agent's `name` in `manifest.yml`. The Foundry API resolves the alias at deploy the same way it resolves `functions.<name>.<handler>`, and publishes the agent on deploy so the action exists when the workflow is created:

```yaml
name: Triage alert with agent
description: On-demand workflow that sends an alert summary to the app's triage agent
provision_on_install: true
trigger:
    next:
        - run_triage_agent
    name: On demand
    parameters:
        properties:
            alert_summary:
                type: string
        type: object
    type: On demand
actions:
    run_triage_agent:
        id: ai_agents.Triage Agent
        next:
            - print_triage
        properties:
            input: ${data['alert_summary']}
        version_constraint: ~1
    print_triage:
        id: aadbf530e35fc452a032f5f8acaaac2a
        properties:
            text_data: ${data['run_triage_agent.response']}
        version_constraint: ~1
output_fields: []
```

- **The agent needs `exposure.workflows.system_action: true`** (`--expose-workflow-system-action`). Pass that flag alone for an agent used only by this app's automations; it stays out of Charlotte chat.
- **Pass the prompt as `input`.** The published agent action takes `input` (string) and an optional `credit_limit` (int32, the most Charlotte AI credits the invocation may use), not `prompt`. Check with `foundry workflows actions view --name "<agent name>" --no-prompt` once the agent has been deployed.
- **Read the reply as `${data['<action key>.response']}`.** The action's output is a required `response` string plus `_reference_links` (an array of `display`/`url` objects). There is no `.output` segment, unlike most platform actions. `foundry workflows actions view --name "<agent name>" --no-prompt --output-schema` shows the output once the agent has been deployed, so deploying the agent before writing the workflow avoids guessing.
- **Use `version_constraint: ~1`, not `~0`.** Unlike `functions.` and `api_integrations.` actions, the published agent action carries a version (`"version": 1` in `actions view`), so it follows the `workflows-development` rule for versioned actions. `~0` matches no published version and deploy fails with `(2018) Action was not found`.
- **The name match is case-insensitive** and may contain spaces or dots. Use the manifest `name`, not the `path`, the artifact `id`, or an `agents.` prefix.
- **The alias is portable.** It resolves to `<agent UUID without dashes>_<CID>`, which differs in every CID and on every reinstall, so never hardcode that ID. Exported apps and workflows saved in App Builder carry the alias, not the resolved ID.
- **`foundry apps validate` doesn't resolve action IDs**, so check the deploy output:

| Deploy error | Fix |
|---|---|
| `referenced AI agent "X" is not exposed to workflows; set exposure.workflows.system_action to true` | Set the exposure flag and redeploy |
| `referenced AI agent 'X' could not be found` | Use the agent's manifest `name` |
| `action with <id> does not exist` (code 2015) for an `ai_agents.` alias | This cloud's Foundry API predates alias support; use the function fallback below |
| `(2018) Action was not found, please select a new action.` | `version_constraint` is `~0`; set it to `~1`. If that deploy still fails, see the next row |
| `Dependent artifact failed (400)` naming a workflow version that already failed | An earlier failed workflow artifact blocks every later deploy of this app, even after the YAML is fixed. Recreate the app; see **NEVER Delete and Recreate Workflows** in `workflows-development` |

**Don't substitute `Charlotte AI - LLM Completion`** (`bdfecafafdb44919a458fcf51d6b93a7_98dec86072334d24b37dd798098cfd63`) with the agent's prompt copied into it. That drops the agent's knowledge bases, tools, model, and output schema, and leaves the agent unused.

## Fallback: go through a function

Where the alias isn't supported yet, or the agent's output needs post-processing in code, have the workflow call a function action and let the function invoke the agent:

1. Create the agent with `--expose-workflow-system-action`.
2. Create a function with `--wf-expose` plus input and output schemas, so the workflow can call it as `functions.<name>.<handler>` (see `workflows-development`), and `--max-exec-duration-seconds 120` so it outlives the agent's deadline.
3. In the handler, resolve the agent by name and invoke it with FalconPy. The app needs the `charlotte-ai-agent-definition` read and write scopes.

```python
import time
from falconpy import AgentInvocation

DEADLINE = 90  # the API rejects deadline_seconds below 90

def assess(agent_id: str, prompt: str) -> str:
    inv = AgentInvocation()  # create inside the handler, not at module scope
    body = {"id": agent_id, "messages": [{"role": "user", "content": prompt}], "deadline_seconds": DEADLINE}
    resp = inv.invoke_published_agent_external_v1(body=body)
    if resp["status_code"] not in (200, 201):
        raise RuntimeError(f"invoke failed: {resp['status_code']} {resp['body'].get('errors')}")
    run = resp["body"]["resources"][0]
    give_up = time.monotonic() + DEADLINE + 15
    while run.get("status") != "completed":
        if run.get("status") in ("failed", "cancelled"):
            raise RuntimeError(f"agent invocation {run.get('id')} ended {run['status']}")
        if time.monotonic() > give_up:
            raise TimeoutError(f"agent invocation {run.get('id')} still {run.get('status')!r}")
        time.sleep(3)
        resp = inv.get_agent_invocation_v3(id=run["id"])
        if resp["status_code"] != 200:
            raise RuntimeError(f"poll failed: {resp['status_code']} {resp['body'].get('errors')}")
        run = resp["body"]["resources"][0]
    replies = [m for m in run.get("conversation") or [] if m.get("role") == "assistant" and m.get("content")]
    if not replies:
        raise RuntimeError(f"agent invocation {run.get('id')} completed with no assistant reply")
    return replies[-1]["content"]
```

Resolve `agent_id` at runtime, never hardcode it. A lookup by name also returns deleted agents, including ones an earlier install left behind, so one name can match more than one agent; follow **AgentWorks: finding your app's own agents by name** in `functions-falcon-api` [advanced-patterns](../../functions-falcon-api/references/advanced-patterns.md). The poll gives up shortly after the agent's own deadline, which is why the function needs a `--max-exec-duration-seconds` above it (the default is 15 and the maximum 900). Any status it doesn't recognize is left to that timeout rather than looping forever.
