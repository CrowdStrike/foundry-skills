---
name: logscale-ingestion
description: Ingest custom data into Falcon LogScale using a Python function with FalconPy
source: https://www.crowdstrike.com/tech-hub/ng-siem/ingesting-custom-data-into-falcon-logscale-with-falcon-foundry-functions/
skills: [functions-development]
capabilities: [function]
---

## When to Use

User wants to send custom data (threat intel, alerts, security events) into Falcon LogScale
from a Foundry function, or query LogScale data from a UI extension.

## Pattern

1. **Create a Python function** with a POST handler for the ingest endpoint.
2. **Accept JSON in `request.body["data"]`**, validate it exists.
3. **Convert JSON to binary** with `dumps(data).encode("utf-8")`.
4. **Call LogScale via FalconPy** using the Service Class (`FoundryLogScale`) or Uber Class (`APIHarnessV2`).
5. **Add manifest scopes** `app-logs:read` and `app-logs:write`.
6. **Query ingested data** in Advanced event search using the app repository: `foundry_{app_id}_applicationrepo`.
7. **(Optional) Query from UI extensions** using `falcon.logscale.query()` from `@crowdstrike/foundry-js`.

## Key Code

### Function handler (Service Class -- recommended)

```python
from io import BytesIO
from json import dumps
from crowdstrike.foundry.function import APIError, Function, Request, Response
from falconpy import FoundryLogScale

FUNC = Function.instance()

@FUNC.handler(method="POST", path="/ingest")
def on_create(request: Request, config: dict, logger) -> Response:
    data = request.body.get("data")
    if not data:
        return Response(code=400, errors=[APIError(code=400, message="missing data from request body")])

    json_binary = dumps(data).encode("utf-8")
    json_file = BytesIO(json_binary)
    api_client = FoundryLogScale()
    result = api_client.ingest_data(data_file=json_file)
    return Response(code=result["status_code"], body=result["body"])
```

### Uber Class alternative (for newer/advanced endpoints)

```python
from falconpy import APIHarnessV2

file_tuple = [("data_file", ("data_file", json_binary, "application/json"))]
api_client = APIHarnessV2()
result = api_client.command("IngestDataV1", files=file_tuple)
```

### Manifest scopes

```yaml
auth:
  scopes:
    - app-logs:read
    - app-logs:write
```

### Query from UI extension (foundry-js)

```javascript
import FalconApi from '@crowdstrike/foundry-js';
const falcon = new FalconApi();
await falcon.connect();

// Query app repository (default)
const result = await falcon.logscale.query({
  search_query: "*",
  start: "1h",
  end: "now"
});

// Query search-all (Falcon telemetry)
const result = await falcon.logscale.query({
  search_query: '#event_simpleName=ProcessRollup2',
  start: '1h',
  end: 'now',
  repo_or_view: 'search-all'
});
```

### LogScale queries

```
// App repository format
#repo=foundry_{app_id}_applicationrepo

// Filter and aggregate
event_type=custom_alert severity=high
| groupBy(severity) | count()

// Correlate with Falcon detections
event_type=custom_alert severity=high
| join({#event_simpleName=DetectionSummaryEvent}, field=aid)
```

## Gotchas

- **Binary format required**: LogScale API expects binary data, not raw JSON. Always `dumps().encode("utf-8")` and wrap in `BytesIO` (Service Class) or file tuple (Uber Class).
- **No explicit credentials in deployed functions**: FalconPy auto-authenticates using the function execution context. Only set `FALCON_CLIENT_ID`/`FALCON_CLIENT_SECRET` for local testing.
- **Local testing needs APP_ID**: Set `X-CS-APP-ID` header with `os.environ.get("APP_ID")` when running locally. Get the app ID from `manifest.yml` after first deploy.
- **Data indexing delay**: Ingested data takes 1-2 minutes to appear in LogScale queries.
- **Batch ingestion**: For multiple events, loop and ingest each item or send an array in a single binary payload. Watch memory for large payloads.
- **Scheduled ingestion**: Use a Falcon Fusion SOAR workflow to trigger the function on a schedule for periodic data pulls (threat intel feeds, polling APIs).
- **Reference app**: [CrowdStrike/foundry-sample-logscale](https://github.com/CrowdStrike/foundry-sample-logscale) provides a working template with UI extension included.
