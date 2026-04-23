# Testing Patterns Reference

> Parent skill: [functions-development](../SKILL.md)

## Local Testing Methods

Four ways to test functions locally:

```bash
# 1. Via Foundry CLI with Docker (random ports, closest to production)
foundry functions run

# 2. Direct Go execution (port 8081, no Docker required)
cd functions/my-function && go run main.go
# Then test: curl -X POST http://localhost:8081/greetings -d '{"name":"World"}'

# 3. Direct Python execution (port 8081, no Docker required)
cd functions/my-function && python3 main.py
# Then test: curl -X POST http://localhost:8081/greetings -d '{"name":"World"}'

# 4. With configuration file (local only)
CS_FN_CONFIG_PATH=./config.json python3 main.py
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

## Go Test with httptest

```go
// functions/alerts/main_test.go
package main

import (
    "net/http"
    "net/http/httptest"
    "testing"

    "github.com/stretchr/testify/assert"
    "github.com/stretchr/testify/require"
)

func TestHandler_Success(t *testing.T) {
    // Set up environment
    t.Setenv("FALCON_CLIENT_ID", "test-id")
    t.Setenv("FALCON_CLIENT_SECRET", "test-secret")

    // Create request
    req := httptest.NewRequest(http.MethodGet, "/alerts?limit=10", nil)
    w := httptest.NewRecorder()

    // Call handler (with mocked Falcon client)
    Handler(w, req)

    // Assert response
    assert.Equal(t, http.StatusOK, w.Code)
    assert.Contains(t, w.Header().Get("Content-Type"), "application/json")
}

func TestHandler_MethodNotAllowed(t *testing.T) {
    req := httptest.NewRequest(http.MethodPost, "/alerts", nil)
    w := httptest.NewRecorder()

    Handler(w, req)

    assert.Equal(t, http.StatusMethodNotAllowed, w.Code)
}

func TestHandler_MissingCredentials(t *testing.T) {
    // Ensure no credentials set
    t.Setenv("FALCON_CLIENT_ID", "")
    t.Setenv("FALCON_CLIENT_SECRET", "")

    req := httptest.NewRequest(http.MethodGet, "/alerts", nil)
    w := httptest.NewRecorder()

    Handler(w, req)

    assert.Equal(t, http.StatusInternalServerError, w.Code)
}

// Mock Falcon client for isolated testing
type MockFalconClient struct {
    QueryAlertsFunc func() (interface{}, error)
}

func (m *MockFalconClient) QueryAlerts(params interface{}) (interface{}, error) {
    if m.QueryAlertsFunc != nil {
        return m.QueryAlertsFunc()
    }
    return nil, nil
}
```

## Python Test with pytest and mock

```python
# tests/test_alerts.py
import pytest
import json
from unittest.mock import Mock, patch
from functions.alerts.main import handler, fetch_alerts

@pytest.fixture
def mock_falcon():
    """Create a mock Falcon API client."""
    mock = Mock()
    mock.query_alerts_v2.return_value = {
        "status_code": 200,
        "body": {"resources": ["alert-1", "alert-2"]}
    }
    mock.get_alerts_v2.return_value = {
        "status_code": 200,
        "body": {
            "resources": [
                {"id": "alert-1", "severity": 8, "description": "Test alert 1"},
                {"id": "alert-2", "severity": 5, "description": "Test alert 2"},
            ]
        }
    }
    return mock

@pytest.fixture
def api_event():
    """Create a sample API Gateway event."""
    return {
        "httpMethod": "GET",
        "queryStringParameters": {"limit": "10"},
        "pathParameters": None,
        "body": None
    }

class TestAlertHandler:
    def test_successful_get(self, api_event, mock_falcon):
        with patch('functions.alerts.main.Alerts', return_value=mock_falcon):
            response = handler(api_event, None)

        assert response["statusCode"] == 200
        body = json.loads(response["body"])
        assert body["status"] == 200
        assert len(body["data"]) == 2

    def test_method_not_allowed(self, api_event):
        api_event["httpMethod"] = "DELETE"
        response = handler(api_event, None)

        assert response["statusCode"] == 405
        body = json.loads(response["body"])
        assert body["error"]["code"] == "METHOD_NOT_ALLOWED"

    def test_limit_capping(self, api_event, mock_falcon):
        api_event["queryStringParameters"]["limit"] = "500"

        with patch('functions.alerts.main.Alerts', return_value=mock_falcon):
            response = handler(api_event, None)

        # Verify limit was capped at 100
        mock_falcon.query_alerts_v2.assert_called_once()
        call_args = mock_falcon.query_alerts_v2.call_args
        assert call_args.kwargs.get("limit", 100) <= 100
```
