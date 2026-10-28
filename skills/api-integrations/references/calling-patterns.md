# Calling API Integrations from Code

Full examples for calling API integrations from UI extensions, Python functions, and Go functions.

## UI Extensions (JavaScript / Foundry-JS)

UI extensions call API integrations through `falcon.apiIntegration()`, not direct HTTP calls. Foundry UI extensions run in sandboxed iframes and cannot make arbitrary HTTP requests.

```javascript
// React example using Foundry-JS
import FalconApi from '@crowdstrike/foundry-js';

const falcon = new FalconApi();
await falcon.connect();

// Call an API integration operation
const apiIntegration = falcon.apiIntegration({
  definitionId: 'Okta',        // Matches the API integration name in manifest.yml
  operationId: 'listUsers'     // Matches the operationId in the OpenAPI spec
});

const response = await apiIntegration.execute({
  request: { params: {} }      // Pass query parameters here
});

// Response structure:
// response.resources[0].status_code  - HTTP status from the external API
// response.resources[0].response_body - Parsed response body
const resource = response.resources?.[0];
const statusCode = resource?.status_code;
const body = resource?.response_body;
```

**Reference:** See `foundry-sample-foundryjs-demo` for a working example of `falcon.apiIntegration().execute()`.

## Python Functions (FalconPy APIIntegrations)

FalconPy's `APIIntegrations` class has three methods: `get_plugin_configs`, `execute_command`, and `execute_command_proxy`. Use `execute_command_proxy`. It returns the vendor's own JSON in `response["body"]`, not a `resources` array. This pattern is from [foundry-sample-anomali-threatstream](https://github.com/CrowdStrike/foundry-sample-anomali-threatstream) (`functions/anomali-ioc-ingest/main.py`):

```python
# functions/anomali-lookup/main.py
from logging import Logger
from typing import Any, Dict, Union

from crowdstrike.foundry.function import APIError, Function, Request, Response
from falconpy import APIIntegrations

func = Function.instance()

@func.handler(method='POST', path='/api/lookup')
def lookup(request: Request, config: Union[Dict[str, Any], None], logger: Logger) -> Response:
    """Call an external API through an API integration."""
    api = APIIntegrations()  # Zero-arg constructor; auth is automatic
    response = api.execute_command_proxy(
        definition_id="Anomali API",   # API integration name in manifest.yml
        operation_id="Intelligence",   # operationId in the OpenAPI spec
        params={"query": {"limit": 10, "status": "active"}},
    )

    if response["status_code"] >= 400:
        logger.error(f"API integration failed: {response.get('body')}")
        return Response(
            code=response["status_code"],
            errors=[APIError(code=response["status_code"], message="Anomali request failed")],
        )

    # The vendor's response body, unwrapped
    return Response(body={"objects": response["body"].get("objects", [])}, code=200)

if __name__ == '__main__':
    func.run()
```

In keyword form, FalconPy builds the request from `definition_id`, `operation_id`, `params` (or `path` / `query` / `header` / `cookie`), `data`, and the optional `id`, `version`, `config_id`, `config_auth_type`, and `description`; it ignores `request=` and `json=`. To send a JSON request body, pass the full payload as `body=` (see [Request Schema Validation](#request-schema-validation-happens-before-the-proxy-call) below).

## Go Functions (gofalcon)

gofalcon has the same calls under `falcon/client/api_integrations`. This is trimmed from [foundry-sample-anomali-threatstream](https://github.com/CrowdStrike/foundry-sample-anomali-threatstream) (`functions/anomali-ioc-ingest/main.go`):

```go
package main

import (
    "context"
    "log/slog"

    fdk "github.com/CrowdStrike/foundry-fn-go"
    "github.com/crowdstrike/gofalcon/falcon"
    "github.com/crowdstrike/gofalcon/falcon/client/api_integrations"
    "github.com/crowdstrike/gofalcon/falcon/models"
)

func newHandler(_ context.Context, _ *slog.Logger, _ fdk.SkipCfg) fdk.Handler {
    m := fdk.NewMux()

    m.Post("/api/lookup", fdk.HandleFnOf(func(ctx context.Context, r fdk.RequestOf[struct{}]) fdk.Response {
        opts := fdk.FalconClientOpts()
        falconClient, err := falcon.NewClient(&falcon.ApiConfig{
            AccessToken:       r.AccessToken,
            Cloud:             falcon.Cloud(opts.Cloud),
            Context:           ctx,
            UserAgentOverride: opts.UserAgent,
        })
        if err != nil {
            return fdk.Response{Code: 500, Body: fdk.JSON(map[string]string{"error": "Failed to authenticate"})}
        }

        definitionID := "Anomali API" // API integration name in manifest.yml
        operationID := "Intelligence" // operationId in the OpenAPI spec
        response, err := falconClient.APIIntegrations.ExecuteCommandProxy(&api_integrations.ExecuteCommandProxyParams{
            Body: &models.DomainExecuteCommandRequestV1{
                Resources: []*models.DomainExecuteCommandV1{
                    {
                        DefinitionID: &definitionID,
                        OperationID:  &operationID,
                        Config: &models.DomainConfigData{
                            Params: &models.DomainParams{
                                Query: map[string]interface{}{"limit": 10, "status": "active"},
                            },
                        },
                    },
                },
            },
            Context: ctx,
        })
        if err != nil {
            return fdk.Response{Code: 502, Body: fdk.JSON(map[string]string{"error": "Failed to call external API"})}
        }

        // ExecuteCommandProxy returns the vendor's response body directly
        body, _ := response.Payload.(map[string]interface{})
        return fdk.Response{Code: 200, Body: fdk.JSON(map[string]interface{}{"objects": body["objects"]})}
    }))

    return m
}

func main() {
    fdk.Run(context.Background(), newHandler)
}
```

gofalcon treats every non-2xx status as an error, including `207 Multi-Status`. The sample unwraps `*runtime.APIError` to read a 207 body and to retry on 429; copy that handling from it when you need it.

## Request Schema Validation Happens Before the Proxy Call

The platform validates the `request` object against the OpenAPI spec's parameter schemas before it forwards anything to the vendor. Values must be scalars typed exactly as the spec declares them — an `integer` parameter takes `1`, not `"1"` and not `["1"]`. A mismatch never reaches the vendor; it comes back as:

```
400 request failed schema validation: /properties/params/properties/query/properties/limit ...
```

This trips up two habits. The foundry-js `Params` type suggests `query?: Record<string, string[]>`, and the FDK's own `request.params.query` is `Dict[str, List[str]]` — both list-valued shapes fail for anything other than `type: string` array parameters. Unwrap and convert before forwarding:

```python
# Python — forward a query param from the handler's request to an integration
limit = int(request.params.query.get("limit", ["25"])[0])
response = api.execute_command_proxy(body={"resources": [{
    "definition_id": "VendorApi",
    "operation_id": "listItems",
    "request": {"params": {"query": {"limit": limit}}},   # scalar, typed per the spec
}]})
```

```javascript
// foundry-js — same rule
await apiIntegration.execute({ request: { params: { query: { limit: 25 } } } });  // number, not '25' or ['25']
```

Path parameters go under `params.path`, query parameters under `params.query`, and headers under `params.header`; a request body goes in `json`. Check each parameter's `schema.type` in the spec before building the request.

## Extracting Fields from API Responses

Before writing code that reads fields from an API response, verify the field's location in the OpenAPI spec's response schema. Fields are often nested under objects (e.g., `meta.severity` not `severity`). Similarly, query parameter names may differ from response field names (e.g., filtering by `meta.severity` even though the CSV column is just `severity`).

**Checklist:**
1. Find the endpoint's response schema in the OpenAPI spec
2. Trace the field path — is it top-level or nested under an object?
3. For query parameters, check the `parameters` section for the exact name
4. Match your struct/dict access to the actual nesting (e.g., `ioc.get("meta", {}).get("severity", '')`)

## Key Points

| Aspect | Detail |
|--------|--------|
| **Python SDK** | `APIIntegrations().execute_command_proxy()` from FalconPy |
| **Go SDK** | `falconClient.APIIntegrations.ExecuteCommandProxy()` from gofalcon |
| **definition_id** | The integration `name` in `manifest.yml`, as the samples pass it |
| **operation_id** | Must match the `operationId` in the OpenAPI spec |
| **Authentication** | Automatic when called from within FDK handlers |
| **Response structure** | Functions: the vendor body directly in `response["body"]` (Go: `response.Payload`). foundry-js `apiIntegration().execute()`: a `resources` array with `status_code` and `response_body` |
| **Request validation** | Validated against the spec's parameter schemas before proxying — scalars typed per the spec, not string arrays |
