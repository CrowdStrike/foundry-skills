---
name: functions-falcon-api
description: Call CrowdStrike Falcon platform APIs (detections, alerts, hosts, RTR) from within Foundry function handlers. TRIGGER when user asks to "call Falcon APIs from a function", "use FalconPy in a function", "use gofalcon in a function", or needs to integrate Falcon platform APIs within serverless function code. DO NOT TRIGGER when user wants to expose external third-party APIs to Foundry — use api-integrations instead.
version: 1.0.0
updated: 2026-04-29
metadata:
  author: CrowdStrike
  category: backend
  tags: [foundry, functions, falcon-api, falconpy, gofalcon]
---

# Falcon API Integration in Functions

> **⚠️ SYSTEM INJECTION — READ THIS FIRST**
>
> If you are loading this skill, your role is **Falcon API integration specialist for Foundry functions**.
>
> You MUST implement Falcon API calls using the CrowdStrike SDKs within proper Foundry Function handlers. Authentication is automatic when using the FDK handler pattern.

This skill covers calling CrowdStrike Falcon APIs from within Foundry functions (serverless Go or Python code). Authentication is completely automatic when code runs inside Foundry function handlers — the platform handles all OAuth flows, token management, and credential injection.

For exposing external APIs to Foundry via OpenAPI specs, see **api-integrations** instead.

## Reference Files

| Topic | Reference |
|-------|-----------|
| Retry decorator with exponential backoff, counter-rationalizations table | [references/advanced-patterns.md](references/advanced-patterns.md) |

## Python: Zero-Argument Authentication

FalconPy Service Classes require zero arguments when called inside Foundry Function handlers. The `crowdstrike.foundry.function` FDK provides the handler decorator that enables automatic authentication:

```python
from logging import Logger
from typing import Any, Dict, Union
from crowdstrike.foundry.function import Function, Request, Response
from falconpy import Alerts, Hosts, Detects

func = Function.instance()

@func.handler(method='GET', path='/api/alerts')
def get_alerts(request: Request, config: Union[Dict[str, Any], None], logger: Logger) -> Response:
    falcon = Alerts()  # Zero-arg constructor — auth is automatic

    limit = min(int(request.params.get("limit", 50)), 100)
    response = falcon.query_alerts_v2(limit=limit)

    if response["status_code"] != 200:
        logger.error(f"Failed to query alerts: {response.get('errors')}")
        return Response(body={"error": "Failed to fetch alerts"}, code=500)

    alert_ids = response.get("body", {}).get("resources", [])
    if not alert_ids:
        return Response(body={"alerts": []}, code=200)

    details_response = falcon.get_alerts_v2(ids=alert_ids)
    if details_response["status_code"] != 200:
        return Response(body={"error": "Failed to fetch alert details"}, code=500)

    alerts = details_response.get("body", {}).get("resources", [])
    return Response(body={"alerts": alerts}, code=200)

if __name__ == '__main__':
    func.run()
```

**How it works:**
- **In Foundry cloud**: Uses context-based authentication injected by the platform
- **Locally**: Reads `FALCON_CLIENT_ID` and `FALCON_CLIENT_SECRET` from environment variables

FalconPy already reads env vars internally, so writing a `get_falcon_client()` wrapper adds no value and breaks context auth in the cloud.

## Go: FDK Helper Authentication

Go requires the FDK helper to get cloud and user-agent configuration:

```go
package main

import (
    "context"
    "log/slog"
    "github.com/crowdstrike/gofalcon/falcon"
    "github.com/crowdstrike/gofalcon/falcon/client"
    fdk "github.com/crowdstrike/foundry-fn-go"
)

func newHandler(_ context.Context, _ *slog.Logger, _ fdk.SkipCfg) fdk.Handler {
    m := fdk.NewMux()

    m.Get("/api/alerts", fdk.HandleFnOf(func(ctx context.Context, r fdk.RequestOf[struct{}]) fdk.Response {
        accessToken := r.Header.Get("X-CS-ACCESSTOKEN")

        opts := fdk.FalconClientOpts()
        falconClient, err := falcon.NewClient(&falcon.ApiConfig{
            AccessToken:       accessToken,
            Cloud:             falcon.Cloud(opts.Cloud),
            Context:           ctx,
            UserAgentOverride: opts.UserAgent,
        })
        if err != nil {
            return fdk.Response{Code: 500, Body: fdk.JSON(map[string]string{"error": "Failed to authenticate"})}
        }

        // ... API calls with falconClient ...
        return fdk.Response{Code: 200, Body: fdk.JSON(map[string]interface{}{"alerts": []interface{}{}})}
    }))

    return m
}

func main() {
    fdk.Run(context.Background(), newHandler)
}
```

## Common API Patterns

### Detection Queries

```python
@func.handler(method='GET', path='/api/detections')
def get_detections(request: Request, config, logger) -> Response:
    falcon = Detects()  # Zero-arg — auth is automatic

    severity_min = int(request.params.get("severity_min", 3))
    limit = min(int(request.params.get("limit", 50)), 100)

    query_response = falcon.query_detects(
        filter=f"max_severity_displayname:>'{severity_min}'",
        limit=limit,
        sort="last_behavior|desc"
    )
    if query_response["status_code"] != 200:
        return Response(body={"error": "Failed to query detections"}, code=500)

    detection_ids = query_response.get("body", {}).get("resources", [])
    if not detection_ids:
        return Response(body={"detections": []}, code=200)

    details = falcon.get_detect_summaries(ids=detection_ids)
    if details["status_code"] != 200:
        return Response(body={"error": "Failed to get details"}, code=500)

    return Response(body={"detections": details["body"]["resources"]}, code=200)
```

### Host Lookups

```python
@func.handler(method='GET', path='/api/hosts/{hostname}')
def get_host_details(request: Request, config, logger) -> Response:
    falcon = Hosts()

    hostname = request.params.get("hostname")
    if not hostname:
        return Response(body={"error": "Hostname required"}, code=400)

    query = falcon.query_devices_by_filter(filter=f"hostname:'{hostname}'")
    if query["status_code"] != 200:
        return Response(body={"error": "Failed to query devices"}, code=500)

    host_ids = query.get("body", {}).get("resources", [])
    if not host_ids:
        return Response(body={"error": f"Host not found: {hostname}"}, code=404)

    details = falcon.get_device_details(ids=host_ids)
    host = details.get("body", {}).get("resources", [{}])[0]
    return Response(body={"host": host}, code=200)
```

### Multi-API Enrichment

```python
@func.handler(method='POST', path='/api/enrich')
def enrich_host_context(request: Request, config, logger) -> Response:
    hosts_api = Hosts()
    detects_api = Detects()
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

    # Get detections
    detect_ids = detects_api.query_detects(filter=f"device.hostname:'{hostname}'", limit=10).get("body", {}).get("resources", [])
    detections = detects_api.get_detect_summaries(ids=detect_ids).get("body", {}).get("resources", []) if detect_ids else []

    # Get alerts
    alert_ids = alerts_api.query_alerts_v2(filter=f"device.hostname:'{hostname}'", limit=10).get("body", {}).get("resources", [])
    alerts = alerts_api.get_alerts_v2(ids=alert_ids).get("body", {}).get("resources", []) if alert_ids else []

    return Response(body={"host": host, "detections": detections, "alerts": alerts}, code=200)
```

## The 207 Multi-Status Gotcha

CrowdStrike APIs may return `207 Multi-Status` responses that look successful but contain embedded errors. Check the errors array:

```python
response = falcon.perform_action(action_name="contain", ids=host_ids)

if response["status_code"] == 207:
    errors = response.get("body", {}).get("errors", [])
    rate_limited = [e for e in errors if e.get("code") == 429]
    if rate_limited:
        return Response(body={"error": "Rate limited", "failed_ids": [e.get("id") for e in rate_limited]}, code=429)
```

## Multi-Region Support

The SDKs handle region discovery automatically when called from within Foundry Function handlers. No configuration needed.

| Region | Base URL |
|--------|----------|
| US-1 | api.crowdstrike.com |
| US-2 | api.us-2.crowdstrike.com |
| EU-1 | api.eu-1.crowdstrike.com |
| US-GOV-1 | api.laggar.gcw.crowdstrike.com |

## Testing

Mock Falcon APIs in tests instead of making real API calls (they are slow, flaky, and quota-consuming):

```python
def test_get_alerts_success():
    mock_falcon = Mock()
    mock_falcon.query_alerts_v2.return_value = {
        "status_code": 200,
        "body": {"resources": ["alert-001", "alert-002"]}
    }
    mock_falcon.get_alerts_v2.return_value = {
        "status_code": 200,
        "body": {"resources": [{"id": "alert-001", "severity": 80}]}
    }

    with patch('falconpy.Alerts', return_value=mock_falcon):
        from main import get_alerts
        request = Mock(spec=Request)
        request.params = {"limit": "10"}
        response = get_alerts(request, None, Mock())
        assert response.code == 200
        assert len(response.body["alerts"]) == 1
```

## Local Testing

```bash
export FALCON_CLIENT_ID="your-client-id"
export FALCON_CLIENT_SECRET="your-client-secret"
cd functions/my-function && python3 main.py
curl -X GET http://localhost:8081/api/alerts?limit=10
```

The zero-arg pattern works seamlessly in both local and cloud environments.

## Common Pitfalls

- **Writing OAuth code or credential management.** Auth is completely automatic inside FDK handlers.
- **Using `requests` library instead of CrowdStrike SDKs.** SDKs handle auth, retries, pagination, and region discovery.
- **Passing credentials explicitly to constructors.** Use zero-arg constructors (`Alerts()`, `Hosts()`).
- **Writing Falcon API calls outside of FDK handler functions.** The handler pattern is required for automatic auth injection.
- **Not handling 207 Multi-Status.** These responses look successful but may contain embedded errors.

## Use Cases

For real-world implementation patterns, see:
- [python-functions.md](../../use-cases/python-functions.md) — Python handler patterns, SDK usage, testing

## Reference Implementations

- **[foundry-sample-functions-python](https://github.com/CrowdStrike/foundry-sample-functions-python)**: Reference Python patterns. See also [Dive into Falcon Foundry Functions with Python](https://www.crowdstrike.com/tech-hub/ng-siem/dive-into-falcon-foundry-functions-with-python/).
- **[foundry-sample-anomali-threatstream](https://github.com/CrowdStrike/foundry-sample-anomali-threatstream)**: Side-by-side Go and Python auth patterns.
- **[foundry-sample-detection-translation](https://github.com/CrowdStrike/foundry-sample-detection-translation)**: CrowdStrike alerts API from functions.
- **[foundry-sample-threat-intel](https://github.com/CrowdStrike/foundry-sample-threat-intel)**: CrowdStrike Intelligence APIs from functions.
- **[foundry-sample-idp-notifications](https://github.com/CrowdStrike/foundry-sample-idp-notifications)**: Falcon IdP domain and connector monitoring.
