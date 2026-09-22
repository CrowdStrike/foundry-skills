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

## Charlotte AI AgentWorks (`/agentic-studio/*`): App Tokens Currently Rejected

> **As of 2026-09-22, the agent definition endpoints under `/agentic-studio/` return `HTTP 500 Internal Server Error` for Foundry app tokens**, even when the app is installed with `charlotte-ai-agent-definition:read` and `:write` granted and every other API family (collections, alerts, hosts) works with the same token and the same context auth. This is the platform rejecting app-issued tokens for this API family, not a scope or base-URL problem — do not spend the debugging budget on `auth.scopes`.

Workaround that works today: register the AgentWorks API as an **API integration** whose spec declares `oauth2` with the `clientCredentials` flow against the Falcon `/oauth2/token` endpoint, and call it from the function through `APIIntegrations().execute_command()`. The installer supplies a Falcon API client (with the Charlotte AI agent definition scope) on the app's install form, and the platform manages that token — nothing personal, nothing in env vars. The Falcon swagger is not downloadable without console auth, so a minimal hand-written spec covering only the operations you need is acceptable in this case; see the `api-integrations` decision tree. If app tokens are accepted later, drop the integration and the handler goes back to zero-arg FalconPy.
