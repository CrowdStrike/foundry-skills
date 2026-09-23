# Advanced Falcon API Patterns Reference

> Parent skill: [functions-falcon-api](../SKILL.md)

## Retry with Exponential Backoff

Reusable retry decorator for Falcon API calls that handles transient failures:

```python
# functions/common/retry.py
import time
from functools import wraps
from typing import TypeVar, Callable

T = TypeVar('T')

def with_retry(
    max_retries: int = 3,
    backoff_factor: float = 1.0,
    retry_on_status: tuple = (429, 500, 502, 503, 504)
):
    """Decorator for API calls with exponential backoff retry."""
    def decorator(func: Callable[..., T]) -> Callable[..., T]:
        @wraps(func)
        def wrapper(*args, **kwargs) -> T:
            last_response = None

            for attempt in range(max_retries + 1):
                response = func(*args, **kwargs)
                status_code = response.get("status_code", 500)

                if status_code not in retry_on_status:
                    return response

                last_response = response

                if attempt < max_retries:
                    sleep_time = backoff_factor * (2 ** attempt)
                    time.sleep(sleep_time)

            return last_response

        return wrapper
    return decorator

# functions/alerts/main.py
from crowdstrike.foundry.function import Function, Request, Response
from falconpy import Alerts
from common.retry import with_retry

func = Function.instance()

@func.handler(method='GET', path='/api/alerts')
def get_alerts(request: Request, config, logger) -> Response:
    falcon = Alerts()

    @with_retry(max_retries=3)
    def query_with_retry():
        return falcon.query_alerts_v2(limit=50, sort="created_timestamp|desc")

    response = query_with_retry()

    if response["status_code"] != 200:
        return Response(body={"error": "Failed after retries"}, code=500)

    alert_ids = response.get("body", {}).get("resources", [])
    return Response(body={"alert_ids": alert_ids}, code=200)

if __name__ == '__main__':
    func.run()
```

## AgentWorks spans: attributing executions to an agent

Every `aw_agent` root span carries the agent's ID in the `aw_agent.id` attribute, and FQL filters on it. Verified against a live CID (2026-09-23) by looking up the `aw_agent.id` of a span and getting back the agent the span names:

```python
flt = f"attributes.aw_agent.id:'{agent_id}'+span_type:'aw_agent'"
body = falcon.command("Manual", override="GET,/agentic-studio/queries/spans/v1",
                      parameters={"filter": flt, "sort": "start_time|desc", "limit": 3})
# body["meta"]["pagination"]["total"] is the agent's execution count
```

- **The key is `aw_agent.id`, not `aw_agent.agent_id`.** A filter on the wrong key (`attributes.aw_agent.agent_id:'...'`) silently returns zero results, not an error, which reads as "this agent never ran".
- Other attributes on the root span: `aw_agent.invocation_id`, `aw_agent.definition.name`, `.model`, `.tools`, `.system_prompt`, `.knowledge_base_ids`, `aw_agent.input`, `aw_agent.submitted_from.*`, and `cost.reserved_credit_cents`. The span's own `name` is always `Agent request`, so filtering on `name` does not find an agent.
- **There is no version ID on the span**, so executions cannot be counted per agent *version*.
- **Run status is on a child span.** `aw_agent.invocation_status` lives on the `aw_agent_response` span of the same trace, not on the root; look it up with `trace_id:'<trace_id>'+span_type:'aw_agent_response'`. A root span without one is still running.
- **Don't match on `aw_agent.definition.name`.** Agent names are not unique per CID (unlike Foundry apps and workflows; a real CID had two distinct agents both named "SOC Daily Briefing Agent"), so a name match can merge two agents' runs.
- There is **no endpoint to list invocations by agent**. Invoke (`POST /agentic-studio/entities/agent-invocations/v1`) returns an id and an `ai_trace_id`; poll the id via `.../agent-invocations/v3?id=`. To observe a run's spans, query `trace_id:'<ai_trace_id>'`.

## AgentWorks: finding your app's own agents by name

A function that invokes agents its app ships (a judge, a classifier) usually has to resolve them by name, since the manifest's `ai.agents[].id` is the Foundry artifact ID, not the AgentWorks agent ID. Two things make a plain name lookup wrong, both verified in a live CID (2026-09-23):

- **The versions query returns deleted agents.** `/agentic-studio/queries/agent-versions/v1` with `name:'<name>'+is_published:true` still returns the published versions of agents that were deleted, including the ones an earlier install of the same app left behind. Resolving by name then finds two agents per name, or picks a dead one.
- **The agent record says who owns it.** `/agentic-studio/entities/agents/v2` returns `is_deleted` and `attribution`, for example `{"origin": "foundry", "data": {"foundry_app_id": "<app id>"}}` on an agent a Falcon Foundry app deployed. The deleted leftovers carried the previous app's ID.

So hydrate each candidate's agent record and keep only `not is_deleted` and `attribution.origin == "foundry"`; refuse, rather than guess, if more than one survives. Matching `attribution.data.foundry_app_id` against your own app would be stricter still, but the Python FDK does not expose the function's app ID.

## Counter-Rationalizations Table

| Your Excuse | Reality |
|-------------|---------|
| "I need to set up OAuth manually" | Auth is completely automatic inside FDK handlers |
| "I should write a credential wrapper" | Wrappers break context auth and add no value |
| "I can use requests directly" | SDKs handle auth, retries, pagination, and region discovery |
| "Region configuration is required" | SDKs auto-discover the correct region from platform context |
| "I'll handle errors generically" | Specific error handling enables proper user feedback |
| "Mocking is extra work" | Real API calls in tests are slow, flaky, and quota-consuming |
| "I can skip the FDK handler pattern" | Handler pattern is required for automatic auth injection |
| "I'll use the Detects class for detection queries" | The Detects API is deprecated (405 errors). Use `Alerts()` with `query_alerts_v2` — filter by `product:'detections'` to scope to detections only |

## Multi-API Enrichment

Combine `Hosts` and `Alerts` in a single handler to build host context. Each API follows the same query-then-get-details shape:

```python
@func.handler(method='POST', path='/api/enrich')
def enrich_host_context(request: Request, config, logger) -> Response:
    hosts_api = Hosts()
    alerts_api = Alerts()

    hostname = request.body.get("hostname")
    if not hostname:
        return Response(body={"error": "Hostname required"}, code=400)

    # Get host
    host_query = hosts_api.query_devices_by_filter(filter=f"hostname:'{hostname}'")
    host_ids = host_query.get("body", {}).get("resources", [])
    if not host_ids:
        return Response(body={"error": "Host not found"}, code=404)

    host = hosts_api.get_device_details(ids=host_ids).get("body", {}).get("resources", [{}])[0]

    # Get detections (via Alerts API with product filter)
    detection_ids = alerts_api.query_alerts_v2(filter=f"device.hostname:'{hostname}'+product:'detections'", limit=10).get("body", {}).get("resources", [])
    detections = alerts_api.get_alerts_v2(ids=detection_ids).get("body", {}).get("resources", []) if detection_ids else []

    # Get all alerts (includes detections + cases)
    alert_ids = alerts_api.query_alerts_v2(filter=f"device.hostname:'{hostname}'", limit=10).get("body", {}).get("resources", [])
    alerts = alerts_api.get_alerts_v2(ids=alert_ids).get("body", {}).get("resources", []) if alert_ids else []

    return Response(body={"host": host, "detections": detections, "alerts": alerts}, code=200)
```
