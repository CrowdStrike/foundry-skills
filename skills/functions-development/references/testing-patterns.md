# Testing Patterns Reference

> Parent skill: [functions-development](../SKILL.md)

## Testing in the Falcon Console (Python)

The browser-based Python editor lets you edit, test, and debug functions without leaving the Falcon console. For users unfamiliar with terminal-based testing, this is the fastest path to understanding how their code executes.

### Navigating to the Editor

1. Go to Foundry → App builder, then open your app
2. Click the ⋮ menu (top right, next to Exit) → **Edit app** (enters draft mode)
3. Click the **Logic** icon in the left sidebar
4. Scroll to the **Functions** section
5. Click ⋮ on the function row → **Edit function**

The editor opens to `main.py` by default. It supports Python only — Go functions still require the Foundry CLI.

### Editor Layout

**Tabs:** Function code | Handlers | Runtime config | Test

**Top right buttons:** Function logs (opens Advanced event search) | Save

The "Function code" tab shows `main.py` and `requirements.txt`. The "Runtime config" tab shows auto-detected API scopes from FalconPy imports (origin: "Code derived").

### Adding Logging

The FDK injects a logger automatically when you include it in the handler signature:

```python
from logging import Logger
from typing import Dict, Optional

def on_post(request: Request, _config: Optional[Dict[str, object]], logger: Logger) -> Response:
    host_id = request.body["host_id"]
    logger.info(f"Looking up host: {host_id}")
    # ... rest of handler
```

### Making the Function Testable

The Test tab requires either preview mode or an installed app:

- **Preview mode** (no Falcon API calls): Deploy the app, then enable preview mode from the Falcon title bar Developer tools button (</> icon). Select the app name and version to test.
- **Installed app** (uses FalconPy): Functions that call Falcon APIs need context-aware authentication, which only works when the app is installed. Complete the full cycle: Deploy → Release → Install from App Catalog.

For integrations you won't invoke during testing, placeholder credentials work for basic auth and API key authentication. OAuth integrations typically require real credentials because the install process validates the token endpoint.

### Running a Test

1. Click the **Test** tab
2. Select the handler from the **Handler name** dropdown (e.g., `host-details`)
3. Enter the **Request JSON**:
   ```json
   { "host_id": "abc123def456" }
   ```
4. Click **Test**

Results appear inline with the HTTP status code and response body. Errors (400, 500) show immediately for rapid iteration.

### Finding Test Data

For functions that require real IDs (hosts, detections, etc.), find them in the Falcon console:

- **Host IDs:** Host Setup and Management → Host Management → click a host → copy its host ID
- **Detection IDs:** Endpoint security → Endpoint detections → click a detection → copy from URL or details panel

### Function Logs

Click the **Function logs** button (top right of the editor). This opens Advanced event search in a new tab with a pre-populated query filtered to your function ID. Results appear automatically showing `logger.info()` output and any errors from recent executions.

This is where logging becomes visible — once users see their log messages appearing here, the connection between code and runtime behavior clicks.

---

## Local Testing Methods

Four ways to test functions locally:

```bash
# 1. Via Foundry CLI with Docker (random ports, closest to production)
foundry functions run

# 2. Direct Go execution (port 8081, no Docker required)
cd functions/my-function && go run main.go

# 3. Direct Python execution (port 8081, no Docker required)
cd functions/my-function && python3 main.py

# 4. With configuration file (local only)
CS_FN_CONFIG_PATH=./config.json python3 main.py
```

The local runner doesn't route on the request path. Post a request envelope to the root URL; the FDK routes on its `method` and `url` fields, which must match the handler's `api_path`:

```bash
curl -X POST http://localhost:8081 \
  -H "Content-Type: application/json" \
  --data '{"body": {"name": "World"}, "method": "POST", "url": "/greetings"}'
```

**Docker vs non-Docker:** `foundry functions run` uses Docker and assigns random ports (closest to production). Direct execution (`go run` / `python3`) runs on port 8081 and is faster for development iteration but does not fully replicate the Foundry runtime.

## Environment Variables and Configuration

Functions can use configuration files and environment variables:

```yaml
# manifest.yml
functions:
  - name: my-function
    environment_variables:
      LOG_LEVEL: "info"
      CUSTOM_SETTING: "value"
```

Configuration files:
- Go: `config.json` or `config.yaml` in the function directory
- Python: `config.json` only
- Access via the `config` parameter in the handler signature
- Use `fdk.SkipCfg` (Go) when no config file is needed
- Set `CS_FN_CONFIG_PATH` env var for local testing with a config file

## Function Scopes (Auto-Detection)

When using the Foundry UI Editor (Python only), API scopes are auto-detected from FalconPy service classes used in the code. Use `CustomStorage` for collection operations so the editor auto-detects `custom-storage:read` and `custom-storage:write` scopes. The Uber class (`APIHarnessV2`) requires manual scope configuration because the editor cannot parse `.command()` calls to determine which APIs are being called.

## Go Handler Test

Call the mux from `newHandler` directly with a request built by `fdktest.RequestOf`. This exercises routing, body decoding, and validation without a Falcon client; for the alerts handler in [go-patterns.md](go-patterns.md), the validation branch returns before the client is built:

```go
// functions/alerts/main_test.go
package main

import (
    "context"
    "net/http"
    "testing"

    fdk "github.com/CrowdStrike/foundry-fn-go"
    "github.com/CrowdStrike/foundry-fn-go/fdktest"
)

func TestAlerts_RejectsLimitOutOfRange(t *testing.T) {
    h := newHandler(context.Background(), fdktest.NewLogger(t), fdk.SkipCfg{})

    req := fdktest.RequestOf(t, fdk.RequestOf[alertsReq]{
        URL:    "/alerts",
        Method: http.MethodPost,
        Body:   alertsReq{Limit: 500},
    })
    resp := h.Handle(context.Background(), req)

    if resp.StatusCode() != http.StatusBadRequest {
        t.Fatalf("want 400, got %d", resp.StatusCode())
    }
    if len(resp.Errors) != 1 || resp.Errors[0].Message != "limit must be between 1 and 100" {
        t.Fatalf("unexpected errors: %v", resp.Errors)
    }
}

func TestAlerts_UnknownRoute(t *testing.T) {
    h := newHandler(context.Background(), fdktest.NewLogger(t), fdk.SkipCfg{})

    req := fdktest.RequestOf(t, fdk.RequestOf[alertsReq]{URL: "/nope", Method: http.MethodPost})
    resp := h.Handle(context.Background(), req)

    if resp.StatusCode() != http.StatusNotFound {
        t.Fatalf("want 404, got %d", resp.StatusCode())
    }
}
```

To unit test the Falcon API path, put the gofalcon calls behind a small interface the handler receives, and pass a fake in tests (foundry-sample-anomali-threatstream does this for `CustomStorage`).

## Running Python Tests Like CI

Run function tests in a virtual environment built from the same Python version and install commands as the project's CI, never the global interpreter. `crowdstrike-falconpy` is unpinned, so CI and the deployed function install the latest release, while a global interpreter may hold a much older one — a test run there can miss service classes that exist in production, or pass against behavior that has since changed.

```bash
uv venv --python 3.14 .venv   # match the version your CI uses
uv pip install --python .venv/bin/python -r functions/my-function/requirements.txt pytest
.venv/bin/python -m pytest functions/my-function/tests
```

A repo-root `.venv` is safe to leave in place: the deploy never packages hidden paths (any path component starting with `.`). A `.venv` or `.pytest_cache` *inside* `functions/<name>/` is still excluded from the deploy, but `foundry functions exec` and `test` count it as an undeployed local change, so keep virtual environments at the repo root.

## Python Handler Test

The reference pattern from foundry-sample-functions-python: patch `Function.handler` with a pass-through decorator, reload `main` so the handlers are plain functions, then call them with a `Request()` and patch the FalconPy class where `main` imports it. This tests the `host-details` handler in [python-patterns.md](python-patterns.md#handler-with-a-falcon-api-call):

```python
# functions/host-details/test_main.py
import importlib
import unittest
from unittest.mock import MagicMock, patch

from crowdstrike.foundry.function import Request

import main


def mock_handler(*_args, **_kwargs):
    """Replace @FUNC.handler so the decorated function is returned unchanged."""
    def identity(func):
        return func
    return identity


class FnTestCase(unittest.TestCase):
    def setUp(self):
        patcher = patch("crowdstrike.foundry.function.Function.handler", new=mock_handler)
        self.addCleanup(patcher.stop)
        patcher.start()
        importlib.reload(main)  # re-apply the decorators with the patch in place

    @patch("main.Hosts")
    def test_on_post_success(self, mock_hosts_class):
        mock_hosts = MagicMock()
        mock_hosts_class.return_value = mock_hosts
        mock_hosts.get_device_details.return_value = {
            "status_code": 200,
            "body": {"resources": [{"device_id": "test-host-123", "hostname": "test-host"}]},
        }

        request = Request()
        request.body = {"host_id": "test-host-123"}
        response = main.on_post(request)

        self.assertEqual(response.code, 200)
        self.assertEqual(response.body["host_details"]["device_id"], "test-host-123")
        mock_hosts.get_device_details.assert_called_once_with(ids="test-host-123")

    def test_on_post_missing_host_id(self):
        response = main.on_post(Request())

        self.assertEqual(response.code, 400)
        self.assertEqual(response.errors[0].message, "missing host_id from request body")

    @patch("main.Hosts")
    def test_on_post_api_error(self, mock_hosts_class):
        mock_hosts_class.return_value.get_device_details.return_value = {
            "status_code": 404,
            "body": {"errors": [{"message": "Host not found"}]},
        }

        request = Request()
        request.body = {"host_id": "nonexistent-host"}
        response = main.on_post(request)

        self.assertEqual(response.code, 404)
        self.assertEqual(response.errors[0].message, "Host not found")


if __name__ == "__main__":
    unittest.main()
```

Run it from the function directory (`import main` resolves there) with the CI-style venv above. For handlers that read query parameters, set `request.params.query = {"id": ["abc"]}`; values are lists.
