# Calling an app's agent from its own workflow

Reference the agent in the workflow template as `ai_agents.<agent name>`, where the name is the agent's `name` in `manifest.yml`. The Foundry API resolves the alias at deploy the same way it resolves `functions.<name>.<handler>`, and publishes the agent on deploy so the action exists when the workflow is created:

```yaml
trigger:
  name: On demand
  next:
    - run_triage_agent
  parameters:
    type: object
    properties:
      alert_summary:
        type: string
actions:
  run_triage_agent:
    id: ai_agents.Triage Agent
    properties:
      prompt: ${alert_summary}
```

- **The agent needs `exposure.workflows.system_action: true`** (`--expose-workflow-system-action`). Pass that flag alone for an agent used only by this app's automations; it stays out of Charlotte chat.
- **The name match is case-insensitive** and may contain spaces or dots. Use the manifest `name`, not the `path`, the artifact `id`, or an `agents.` prefix.
- **The alias is portable.** It resolves to `<agent UUID without dashes>_<CID>`, which differs in every CID and on every reinstall, so never hardcode that ID. Exported apps and workflows saved in App Builder carry the alias, not the resolved ID.
- **`foundry apps validate` doesn't resolve action IDs**, so check the deploy output:

| Deploy error | Fix |
|---|---|
| `referenced AI agent "X" is not exposed to workflows; set exposure.workflows.system_action to true` | Set the exposure flag and redeploy |
| `referenced AI agent 'X' could not be found` | Use the agent's manifest `name` |
| `action with <id> does not exist` (code 2015) for an `ai_agents.` alias | This cloud's Foundry API predates alias support; use the function fallback below |

**Don't substitute `Charlotte AI - LLM Completion`** (`bdfecafafdb44919a458fcf51d6b93a7_98dec86072334d24b37dd798098cfd63`) with the agent's prompt copied into it. That drops the agent's knowledge bases, tools, model, and output schema, and leaves the agent unused.

## Fallback: go through a function

Where the alias isn't supported yet, or the agent's output needs post-processing in code, have the workflow call a function action and let the function invoke the agent:

1. Create the agent with `--expose-workflow-system-action`.
2. Create a function with `--wf-expose` plus input and output schemas, so the workflow can call it as `functions.<name>.<handler>` (see `workflows-development`).
3. In the handler, resolve the agent by name and invoke it with FalconPy. The app needs the `charlotte-ai-agent-definition` read and write scopes.

```python
import time
from falconpy import AgentInvocation

def assess(agent_id: str, prompt: str) -> str:
    inv = AgentInvocation()  # create inside the handler, not at module scope
    body = {"id": agent_id, "messages": [{"role": "user", "content": prompt}], "deadline_seconds": 90}
    run = inv.invoke_published_agent_external_v1(body=body)["body"]["resources"][0]
    while run.get("status") not in ("completed", "failed", "cancelled"):
        time.sleep(3)
        run = inv.get_agent_invocation_v3(id=run["id"])["body"]["resources"][0]
    if run["status"] != "completed":
        raise RuntimeError(f"agent invocation {run['id']} ended {run['status']}")
    return [m for m in run.get("conversation") or [] if m.get("role") == "assistant"][-1]["content"]
```

Resolve `agent_id` at runtime, never hardcode it. A lookup by name also returns deleted agents, including ones an earlier install left behind, so one name can match more than one agent; follow **AgentWorks: finding your app's own agents by name** in `functions-falcon-api` [advanced-patterns](../../functions-falcon-api/references/advanced-patterns.md). Keep the poll under the function's `max_exec_duration_seconds`.
