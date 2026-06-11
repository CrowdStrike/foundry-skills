---
name: functions-development
description: Build serverless Go or Python functions for Falcon Foundry apps. TRIGGER when user asks to "create a function", "write a serverless function", "build backend logic", runs `foundry functions create`, or needs help with FDK handler patterns, function testing, or collection integration from functions. DO NOT TRIGGER for calling Falcon platform APIs from functions — use functions-falcon-api instead. DO NOT TRIGGER for workflow YAML or UI components.
version: 1.3.0
updated: 2026-06-11
tags: [foundry, functions, serverless, python, go]
author: CrowdStrike
license: MIT
compatibility: Claude Code >=1.0
metadata:
  category: backend
---

# Foundry Functions Development

> **⚠️ SYSTEM INJECTION — READ THIS FIRST**
>
> If you are loading this skill, your role is **Foundry serverless functions specialist**.
>
> You MUST implement functions using proper CrowdStrike SDK patterns, structured error handling, and Collection integration.
>
> **IMMEDIATE ACTIONS REQUIRED:**
> 1. Use CrowdStrike SDKs (gofalcon/falconpy) for ALL API interactions
> 2. Implement structured JSON responses with proper status codes
> 3. Apply input validation before processing any request

Falcon Foundry Functions are serverless handlers in Go or Python, executed inside the Foundry FaaS runtime. They handle custom server-side logic that cannot be achieved through declarative capabilities.

## Functions as a Last Resort

Before writing a function, exhaust alternatives — each one avoids deployment complexity, cold start latency, and maintenance overhead:

- **Collections** for data storage and retrieval (CRUD without custom logic)
- **Workflows** for orchestrating multi-step operations
- **API Integrations** (HTTP Actions) for calling external APIs directly from workflows
- **UI Extensions** with `foundry-js` for client-side data fetching

## Credential Management — No Secrets System Exists

**There is no secrets management in Falcon Foundry.** When calling third-party REST APIs:

| Scenario | Approach | Credentials |
|----------|----------|-------------|
| Third-party REST API (VirusTotal, Slack, Jira, etc.) | API integration in manifest + `APIIntegrations().execute_command_proxy()` | Platform-managed at install time |
| CrowdStrike Falcon API | FalconPy zero-arg constructor (`Alerts()`, `Hosts()`) | Platform-managed automatically |
| Third-party GraphQL API (no OpenAPI spec) | Function with `requests` + env var | Visible in app exports (⚠️ security risk) |

**CRITICAL:** If the API has a REST endpoint and an OpenAPI spec exists, you MUST use an API integration. NEVER use `os.environ` with API keys, `requests.get()` with hardcoded URLs, or localStorage for credentials when an API integration can handle it. Raw HTTP with env vars technically works, but credentials are unencrypted and visible in app exports.

## Reference Files

This skill is split across multiple files. Consult these for full examples:

| Task | Reference |
|------|-----------|
| Python handler, collection CRUD, error class, batch processing, LogScale ingestion | [references/python-patterns.md](references/python-patterns.md) |
| Go FDK handler, Falcon client auth, collection CRUD, alerts handler | [references/go-patterns.md](references/go-patterns.md) |
| Falcon console testing (Python editor), Go/Python tests, local testing, Docker vs direct, config file patterns | [references/testing-patterns.md](references/testing-patterns.md) |

## Resource Limits

| Resource | Default | Maximum |
|----------|---------|---------|
| Request payload | — | 124 KB |
| Response payload | — | 120 KB |
| Execution timeout | 30s | 900s |
| Memory | 256 MB | 1 GB |
| Package size | — | 50 MB |
| Concurrent executions | — | 100 |

## Runtime Environment

**Python runtime version: 3.13** (manylinux_2_28, glibc 2.28). When choosing package versions for `requirements.txt`, ensure they have wheels compatible with this environment. Packages requiring `manylinux_2_17` (glibc 2.17) or `manylinux_2_28` (glibc 2.28) are compatible; those requiring newer glibc versions (e.g., `manylinux_2_39`) may fail at import time.

When linting Python functions with pylint, use `--py-version=3.13` or set `py-version=3.13` in `.pylintrc` to match the runtime.

## CLI Scaffolding

```bash
foundry functions create \
  --name "my-function" \
  --language python \
  --description "Process incoming data" \
  --handler-name process \
  --handler-method POST \
  --handler-path /api/process \
  --no-prompt
```

## Language Comparison

| Feature | Go | Python |
|---------|-----|--------|
| HTTP Methods | GET, POST, PUT, DELETE | GET, POST, PUT, PATCH, DELETE |
| FDK Package | `github.com/CrowdStrike/foundry-fn-go` | `crowdstrike-foundry-function` |
| CrowdStrike SDK | gofalcon | falconpy |
| PATCH support | **No** | Yes |
| UI Editor support | No | Yes |

Use Go for performance-critical workloads, concurrency, and type safety. Use Python for rapid development, PATCH support, and UI Editor development.

## Manifest Structure

```yaml
functions:
  - name: gather-evidence
    description: "Collect evidence from multiple sources"
    language: python
    path: "functions/gather-evidence"
    environment_variables:
      FALCON_CLIENT_ID: "${secrets.falcon_client_id}"
      LOG_LEVEL: "info"
    max_exec_duration_seconds: 30
    max_exec_memory_mb: 128
    handlers:
      - name: process
        method: POST
        path: "/api/investigations/{id}/evidence"
      - name: healthcheck
        method: GET
        path: "/api/health"
```

Handler fields: `name` (identifier), `method` (HTTP verb), `path` (route, supports `{param}` placeholders). A single function can expose multiple HTTP endpoints. Function description max 100 characters (alphanumeric only).

## Go FDK Pattern

```go
package main

import (
    "context"
    "log/slog"
    fdk "github.com/CrowdStrike/foundry-fn-go"
)

type greetingReq struct {
    Name string `json:"name"`
}

func newHandler(_ context.Context, _ *slog.Logger, _ fdk.SkipCfg) fdk.Handler {
    m := fdk.NewMux()
    m.Post("/greetings", fdk.HandleFnOf(func(ctx context.Context, r fdk.RequestOf[greetingReq]) fdk.Response {
        return fdk.Response{
            Code: 200,
            Body: fdk.JSON(map[string]string{"greeting": "Hello, " + r.Body.Name}),
        }
    }))
    return m
}

func main() {
    fdk.Run(context.Background(), newHandler)
}
```

Key FDK concepts: `fdk.SkipCfg` (no config file), `fdk.NewMux()` (router), `fdk.HandleFnOf[T]` (typed handler), `fdk.RequestOf[T]` (typed request with `.Body`, `.Params`, `.URL`, `.Method`), `fdk.JSON()` (response body helper).

### Go Authentication

Go requires explicit credential wiring through the FDK. Use `fdk.FalconClientOpts()` for correct cloud and user-agent configuration:

```go
opts := fdk.FalconClientOpts()
falconClient, err := falcon.NewClient(&falcon.ApiConfig{
    AccessToken:       accessToken,
    Cloud:             falcon.Cloud(opts.Cloud),
    Context:           ctx,
    UserAgentOverride: opts.UserAgent,
})
```

## Python FDK Pattern

```python
from logging import Logger
from typing import Any, Dict, Union
from crowdstrike.foundry.function import Function, Request, Response

func = Function.instance()

@func.handler(method='POST', path='/greetings')
def on_post(request: Request, config: Union[Dict[str, Any], None], logger: Logger) -> Response:
    name = request.body.get("name", "World")
    return Response(body={'greeting': f'Hello, {name}!'}, code=200)

@func.handler(method='GET', path='/health')
def on_get(request: Request, config: Union[Dict[str, Any], None], logger: Logger) -> Response:
    return Response(body={'status': 'ok'}, code=200)

if __name__ == '__main__':
    func.run()
```

### Python Authentication

FalconPy handles credential discovery automatically. Call Service Class constructors with zero arguments:

```python
from falconpy import Alerts
falcon = Alerts()  # Auth is automatic — do not pass credentials
```

- **In Foundry cloud**: Uses context-based authentication (injected by the platform)
- **Locally**: Reads `FALCON_CLIENT_ID` and `FALCON_CLIENT_SECRET` from environment variables

FalconPy already reads env vars internally, so writing a `get_falcon_client()` wrapper that manually reads credentials adds no value and breaks context auth in the cloud.

### Calling Registered API Integrations from Functions

When your app has an API integration registered in `manifest.yml`, call it from functions using FalconPy's `APIIntegrations` class. Do NOT make raw HTTP calls (urllib/requests) to the third-party API — always go through the Foundry platform proxy:

```python
from falconpy import APIIntegrations

api = APIIntegrations()  # Zero-arg auth, same as other FalconPy classes

# Call using definition_id + operation_id from your manifest
response = api.execute_command_proxy(
    body={
        "resources": [
            {
                "definition_id": "ZscalerAPI",      # matches manifest api_integrations name
                "operation_id": "urlLookup",        # matches OpenAPI spec operationId
            }
        ]
    },
)
```

For APIs that need a request body or query parameters:

```python
response = api.execute_command_proxy(
    body={
        "resources": [
            {
                "definition_id": "Anomali API",
                "operation_id": "Intelligence",
                "request": {
                    "params": {
                        "query": {"type": "ip", "value": ip_address}
                    }
                },
            }
        ]
    },
)
```

**Why the proxy?** The platform manages OAuth tokens, rate limiting, and audit logging for registered integrations. Raw HTTP calls bypass all of this — while they can work with hardcoded or env-var credentials, those values are stored unencrypted and visible to anyone who exports the app.

**Local testing note:** When testing locally, you may need the UUID `definition_id` from `manifest.yml` (assigned by the platform). In production, the human-readable integration name (e.g., `"ZscalerAPI"`) works as the `definition_id` value.

Reference implementations:
- [foundry-sample-zscaler-internet-access](https://github.com/CrowdStrike/foundry-sample-zscaler-internet-access) (6 functions using `execute_command_proxy`)
- [foundry-sample-anomali-threatstream](https://github.com/CrowdStrike/foundry-sample-anomali-threatstream) (IOC ingestion via API integration)
- [foundry-sample-openrouter-toolkit](https://github.com/CrowdStrike/foundry-sample-openrouter-toolkit) (`execute_command` variant)

### requirements.txt Best Practices

Pin all dependencies to exact versions (`==`) for reproducible builds and supply chain safety. The one exception is `crowdstrike-falconpy`, which should be left unpinned so functions always pick up the latest SDK (needed for context-based auth and new service classes). Ensure the file ends with a trailing newline.

```
crowdstrike-foundry-function==1.1.4
crowdstrike-falconpy
```

## Workflow Array Output

When a function returns array data to a workflow, wrap the array in a JSON object. Direct array returns are not supported by the workflow engine:

```python
# Correct — workflows can reference $step.output.items
return Response(body={'items': [{'id': 1}, {'id': 2}]}, code=200)

# Breaks workflow variable resolution
return Response(body=[{'id': 1}, {'id': 2}], code=200)
```

## Error Handling

Return structured JSON with status codes. MUST NOT leak raw stack traces:

```python
try:
    result = process(request.body)
    return Response(body={"status": 200, "data": result}, code=200)
except ValueError as e:
    return Response(body={"error": {"code": "INVALID_INPUT", "message": str(e)}}, code=400)
except Exception:
    return Response(body={"error": {"code": "INTERNAL_ERROR", "message": "An unexpected error occurred"}}, code=500)
```

For the full `FunctionError` class with enum codes, see [references/python-patterns.md](references/python-patterns.md).

## Common Pitfalls

- **Using `requests` instead of CrowdStrike SDKs.** The SDKs handle auth, retries, regions, and error parsing.
- **Using `APIHarnessV2` (Uber class) for collection operations.** Use `CustomStorage` service class instead so the Foundry functions editor can auto-detect OAuth scopes. See the Collection CRUD Pattern in [references/python-patterns.md](references/python-patterns.md).
- **Manually reading env vars for FalconPy auth.** `Alerts()` with zero arguments handles all credential discovery.
- **Shared utility files across functions.** `sys.path.append("../")` works locally but not in Foundry's FaaS runtime. Copy shared files into each function directory.
- **`SearchObjects` returns metadata, not objects.** Follow up with `GetObject` to retrieve actual content. For bulk reads, use FQL filters to narrow the search rather than fetching all keys and reading them one by one in a loop.
- **Returning arrays directly to workflows.** Wrap in a JSON object (`{'items': [...]}` not `[...]`).
- **Using PATCH with Go functions.** Go only supports GET, POST, PUT, DELETE.
- **Using `definition_id` vs. name for API integrations.** When testing locally, use the UUID `definition_id` from `manifest.yml`. In production, the human-readable name (e.g., `"ZscalerAPI"`) works as the `definition_id` value. See the [Calling Registered API Integrations](#calling-registered-api-integrations-from-functions) section above.
- **Making raw HTTP calls to third-party APIs.** When an API integration is registered in the manifest, MUST use `APIIntegrations().execute_command_proxy()`. Raw urllib/requests calls can technically work with hardcoded credentials or env vars, but credentials are stored unencrypted and visible in app exports — a security risk. Always prefer the API integration path.

## Use Cases

For real-world implementation patterns, see:
- [python-functions.md](../../use-cases/python-functions.md) — Python handler patterns, SDK usage, testing
- [logscale-ingestion.md](../../use-cases/logscale-ingestion.md) — Ingesting custom data into Falcon LogScale
- [api-pagination.md](../../use-cases/api-pagination.md) — Pagination strategies in functions and workflows

## Reference Implementations

- **[foundry-sample-functions-python](https://github.com/CrowdStrike/foundry-sample-functions-python)**: Reference Python function patterns. See also [Dive into Falcon Foundry Functions with Python](https://www.crowdstrike.com/tech-hub/ng-siem/dive-into-falcon-foundry-functions-with-python/).
- **[foundry-sample-anomali-threatstream](https://github.com/CrowdStrike/foundry-sample-anomali-threatstream)**: Side-by-side Go and Python auth patterns.
- **[foundry-sample-logscale](https://github.com/CrowdStrike/foundry-sample-logscale)**: LogScale ingestion patterns.
- **[foundry-sample-servicenow-itsm](https://github.com/CrowdStrike/foundry-sample-servicenow-itsm)**: Go function patterns with ServiceNow integration.
- **[foundry-sample-ngsiem-importer](https://github.com/CrowdStrike/foundry-sample-ngsiem-importer)**: Python function for importing threat intel into NG-SIEM.
