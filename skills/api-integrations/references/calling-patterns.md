# Calling API Integrations from Code

Full examples for calling API integrations from UI extensions, Python functions, and Go functions.

## UI Extensions (JavaScript / Falcon JS SDK)

UI extensions call API integrations through `falcon.apiIntegration()`, not direct HTTP calls. Foundry UI extensions run in sandboxed iframes and cannot make arbitrary HTTP requests.

```javascript
// React example using Falcon JS SDK
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

```python
# functions/external-enrichment/main.py
from logging import Logger
from typing import Any, Dict, Union

from crowdstrike.foundry.function import Function, Request, Response
from falconpy import APIIntegrations

func = Function.instance()

@func.handler(method='POST', path='/api/enrich')
def enrich_with_external_api(request: Request, config: Union[Dict[str, Any], None], logger: Logger) -> Response:
    """Call an external API via API Integration."""
    # Get the data to enrich
    ip_address = request.body.get("ip_address")
    if not ip_address:
        return Response(body={"error": "IP address required"}, code=400)

    # Use API Integrations SDK to call the configured integration
    api_integrations = APIIntegrations()

    # Call the API integration operation
    # definition_id is the integration name from manifest.yml
    response = api_integrations.execute(
        definition_id="VirusTotal",      # Integration name
        operation_id="getIpReport",       # Operation ID from OpenAPI spec
        body={
            "request": {
                "params": {
                    "ip": ip_address
                }
            }
        }
    )

    if response["status_code"] != 200:
        logger.error(f"API integration failed: {response.get('errors')}")
        return Response(
            body={"error": "Failed to call external API"},
            code=500
        )

    # Extract the external API response
    resources = response.get("body", {}).get("resources", [])
    if not resources:
        return Response(body={"error": "No data returned"}, code=404)

    external_data = resources[0].get("response_body", {})

    return Response(
        body={
            "ip_address": ip_address,
            "enrichment": external_data
        },
        code=200
    )

if __name__ == '__main__':
    func.run()
```

## Go Functions (gofalcon)

```go
// functions/external-enrichment/main.go
package main

import (
    "context"
    "encoding/json"
    "log/slog"

    "github.com/crowdstrike/gofalcon/falcon"
    "github.com/crowdstrike/gofalcon/falcon/client"
    "github.com/crowdstrike/gofalcon/falcon/client/custom_storage"
    fdk "github.com/crowdstrike/foundry-fn-go"
)

type enrichRequest struct {
    IPAddress string `json:"ip_address"`
}

type enrichResponse struct {
    IPAddress  string                 `json:"ip_address"`
    Enrichment map[string]interface{} `json:"enrichment"`
}

func newHandler(_ context.Context, _ *slog.Logger, _ fdk.SkipCfg) fdk.Handler {
    m := fdk.NewMux()

    m.Post("/api/enrich", fdk.HandleFnOf(func(ctx context.Context, r fdk.RequestOf[enrichRequest]) fdk.Response {
        if r.Body.IPAddress == "" {
            return fdk.Response{
                Code: 400,
                Body: fdk.JSON(map[string]string{"error": "IP address required"}),
            }
        }

        // Get Falcon client for API Integrations
        accessToken := r.Header.Get("X-CS-ACCESSTOKEN")
        opts := fdk.FalconClientOpts()
        falconClient, err := falcon.NewClient(&falcon.ApiConfig{
            AccessToken:       accessToken,
            Cloud:             falcon.Cloud(opts.Cloud),
            Context:           ctx,
            UserAgentOverride: opts.UserAgent,
        })
        if err != nil {
            return fdk.Response{
                Code: 500,
                Body: fdk.JSON(map[string]string{"error": "Failed to authenticate"}),
            }
        }

        // Call API integration
        // Note: Use the integration's definition_id from manifest.yml
        integrationRequest := map[string]interface{}{
            "request": map[string]interface{}{
                "params": map[string]string{
                    "ip": r.Body.IPAddress,
                },
            },
        }

        requestBody, _ := json.Marshal(integrationRequest)

        // Execute API integration operation
        params := custom_storage.NewExecuteCommandParamsWithContext(ctx)
        params.SetDefinitionID("VirusTotal")     // Integration name from manifest.yml
        params.SetOperationID("getIpReport")      // Operation ID from OpenAPI spec
        params.SetBody(requestBody)

        apiResponse, err := falconClient.CustomStorage.ExecuteCommand(params)
        if err != nil {
            return fdk.Response{
                Code: 500,
                Body: fdk.JSON(map[string]string{"error": "Failed to call external API"}),
            }
        }

        // Parse the response
        var result struct {
            Resources []struct {
                StatusCode   int                    `json:"status_code"`
                ResponseBody map[string]interface{} `json:"response_body"`
            } `json:"resources"`
        }

        if err := json.Unmarshal(apiResponse.Payload, &result); err != nil {
            return fdk.Response{
                Code: 500,
                Body: fdk.JSON(map[string]string{"error": "Failed to parse response"}),
            }
        }

        if len(result.Resources) == 0 {
            return fdk.Response{
                Code: 404,
                Body: fdk.JSON(map[string]string{"error": "No data returned"}),
            }
        }

        response := enrichResponse{
            IPAddress:  r.Body.IPAddress,
            Enrichment: result.Resources[0].ResponseBody,
        }

        return fdk.Response{
            Code: 200,
            Body: fdk.JSON(response),
        }
    }))

    return m
}

func main() {
    fdk.Run(context.Background(), newHandler)
}
```

## Key Points

| Aspect | Detail |
|--------|--------|
| **Python SDK** | `APIIntegrations()` from FalconPy with `execute()` method |
| **Go SDK** | Falcon client with `CustomStorage.ExecuteCommand()` |
| **definition_id** | Must match the integration name in `manifest.yml` |
| **operation_id** | Must match the `operationId` in the OpenAPI spec |
| **Authentication** | Automatic when called from within FDK handlers |
| **Response structure** | Returns `resources` array with `status_code` and `response_body` |
| **Local development** | Use the UUID `definition_id` from `manifest.yml`, not the human-readable name (avoids 404 errors) |
