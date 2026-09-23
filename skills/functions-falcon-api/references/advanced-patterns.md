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

Reading an agent's executions/traces is not as simple as filtering by agent id, because the span data does not carry one. Verified against a live CID:

- `/agentic-studio/queries/spans/v1` filters on `span_type`, `trace_id`, `status`, `name`, `duration_ms`, and `start_time` only — there is **no agent-id or version-id filter**.
- On an `aw_agent` span, the agent lives in `attributes` under dotted keys: `aw_agent.definition.name`, `aw_agent.definition.model`, `aw_agent.definition.tools`, `aw_agent.definition.system_prompt`, `aw_agent.definition.knowledge_base_ids`, plus `aw_agent.invocation_id`. There is **no `aw_agent.agent_id` and no version id** on the span. (A filter like `attributes.aw_agent.agent_id:'...'` matches nothing — it silently returns zero results, not an error.)
- So to attribute executions to an agent, list recent root spans (`span_type:'aw_agent'`, sort `start_time|desc`) and match `attributes.aw_agent.definition.name` against the agent's name. **Agent names are not unique per CID** — unlike Foundry apps and workflows, AgentWorks does not enforce uniqueness (a real CID had two distinct agents both named "SOC Daily Briefing Agent"), so a name match can be ambiguous and nothing on the span disambiguates it.
- **Counting executions per agent *version* is not possible from spans** — there is no version id on the span.
- There is **no endpoint to list invocations by agent**. Invoke (`POST /agentic-studio/entities/agent-invocations/v1`) returns an id and an `ai_trace_id`; poll the id via `.../agent-invocations/v3?id=`. To observe a run's spans, query `trace_id:'<ai_trace_id>'`. The console's Traces page works exactly this way: it lists spans by `span_type` (not by agent) and filters by name.

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
