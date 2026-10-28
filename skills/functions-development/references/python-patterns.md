# Python Function Patterns Reference

> Parent skill: [functions-development](../SKILL.md)

## Handler with a Falcon API Call

FDK handler that validates input, calls a Falcon API with a zero-arg FalconPy client built inside the handler, and returns failures as `errors` (adapted from `host-details` in foundry-sample-functions-python):

```python
# functions/host-details/main.py
from crowdstrike.foundry.function import Function, Request, Response, APIError
from falconpy import Hosts

FUNC = Function.instance()


@FUNC.handler(method="POST", path="/host-details")
def on_post(request: Request) -> Response:
    if "host_id" not in request.body:
        return Response(
            code=400,
            errors=[APIError(code=400, message="missing host_id from request body")]
        )

    falcon = Hosts()  # context auth: construct inside the handler
    response = falcon.get_device_details(ids=request.body["host_id"])

    if response["status_code"] != 200:
        messages = [e.get("message", "") for e in response["body"].get("errors") or []]
        return Response(
            code=response["status_code"],
            errors=[APIError(code=response["status_code"],
                             message="; ".join(messages) or "host lookup failed")],
        )

    return Response(body={"host_details": response["body"]["resources"][0]}, code=200)


if __name__ == "__main__":
    FUNC.run()
```

A handler takes `request`, optionally `config` second and `logger` third. `Response` carries `body`, `code`, and `errors` (a list of `APIError(code, message)`); with no `code`, the FDK uses the highest code in `errors`. `tests.yml` `expect.errors` compares the `message` values.

## The `Request` Object

`Request` is a dataclass, not a dict, and it has **no `query` attribute**. Query parameters and headers live under `request.params`, itself a `RequestParams` dataclass with two fields whose values are always lists:

| Field | Type | Notes |
|-------|------|-------|
| `body` | `Dict[str, Any]` | Parsed JSON body |
| `params.query` | `Dict[str, List[str]]` | Query string — every value is a list: `request.params.query.get("limit", ["50"])[0]` |
| `params.header` | `Dict[str, List[str]]` | Request headers, same list-valued shape |
| `context` | `Dict[str, Any]` | Context object supplied by the caller (`--context` on `exec`) |
| `method`, `url` | `str` | HTTP verb and the URL the handler was invoked on |
| `access_token` | `str` | Bearer token for this request; FalconPy reads it for you, so do not pass it around |
| `trace_id` | `str` | Platform trace ID — worth including in log lines |
| `fn_id`, `fn_version` | `str`, `int` | The function's ID and deployed version |
| `files` | `Dict[str, bytes]` | Uploaded files keyed by name |

`request.query` fails with `'Request' object has no attribute 'query'`, and `request.params.get(...)` fails with `'RequestParams' object has no attribute 'get'`. Both surface only at runtime in the deployed function, so get the shape right before deploying.

## Collection CRUD Pattern

Full incident store using `CustomStorage` (Service Class) for collection operations from Python functions. Use service classes instead of the Uber class (`APIHarnessV2`) because the Falcon Foundry functions editor auto-detects required OAuth scopes (`custom-storage:read`, `custom-storage:write`) from `from falconpy import CustomStorage`. It cannot parse the Uber class `.command()` pattern.

This is the pattern used by CrowdStrike's own foundry-sample repos (`foundry-sample-collections-toolkit`, `foundry-sample-functions-python`):

```python
# functions/incidents/main.py
import json
import os
import uuid
from datetime import datetime, timezone
from typing import Dict, Any, Optional, List
from crowdstrike.foundry.function import APIError, Function, Request, Response
from falconpy import CustomStorage

func = Function.instance()

COLLECTION_NAME = "incidents"

def _app_headers() -> Dict[str, str]:
    """Build app headers for CustomStorage construction."""
    app_id = os.environ.get("APP_ID")
    if app_id:
        return {"X-CS-APP-ID": app_id}
    return {}

def get_client() -> CustomStorage:
    """Get API client with automatic auth."""
    return CustomStorage(ext_headers=_app_headers())

def create_incident(client: CustomStorage, data: Dict[str, Any]) -> Dict[str, Any]:
    """Create a new incident in the collection (PutObject = create or upsert)."""
    incident_id = data.get("id", str(uuid.uuid4()))
    incident = {
        "id": incident_id,
        "title": data["title"],
        "severity": data.get("severity", 1),
        "status": data.get("status", "open"),
        "created_at": datetime.now(timezone.utc).isoformat(),
        "updated_at": datetime.now(timezone.utc).isoformat(),
    }
    response = client.PutObject(collection_name=COLLECTION_NAME,
                                object_key=incident_id,
                                body=incident)
    if response["status_code"] != 200:
        raise Exception(f"Failed to create incident: {response.get('errors', [])}")
    return incident

def get_incident(client: CustomStorage, incident_id: str) -> Optional[Dict[str, Any]]:
    """Retrieve an incident by key. GetObject returns bytes — decode to dict."""
    response = client.GetObject(collection_name=COLLECTION_NAME,
                                object_key=incident_id)
    if isinstance(response, (bytes, bytearray)):
        return json.loads(response.decode("utf-8"))
    errors = (response.get("body") or {}).get("errors") or []
    if response.get("status_code") == 404:
        return None
    raise Exception(f"Failed to get incident: {response.get('status_code')} {errors}")

def delete_incident(client: CustomStorage, incident_id: str) -> bool:
    """Delete an incident by key."""
    response = client.DeleteObject(collection_name=COLLECTION_NAME,
                                   object_key=incident_id)
    return response["status_code"] == 200

def search_incidents(client: CustomStorage, fql_filter: str = "", limit: int = 50) -> List[Dict[str, Any]]:
    """Search incidents using FQL filter. Only indexed fields are filterable."""
    response = client.SearchObjects(collection_name=COLLECTION_NAME,
                                    filter=fql_filter,
                                    limit=limit)
    if response["status_code"] != 200:
        raise Exception(f"Search failed: {response.get('errors', [])}")
    # SearchObjects returns metadata — retrieve full objects by key
    resources = response.get("body", {}).get("resources", [])
    incidents = []
    for item in resources:
        obj = get_incident(client, item["object_key"])
        if obj:
            incidents.append(obj)
    return incidents

# Handlers. The FDK matches api_path exactly, so the key comes from the query string
def _key(request: Request) -> str:
    return request.params.query.get("id", [""])[0]

@func.handler(method='POST', path='/api/incidents')
def on_create(request: Request) -> Response:
    client = get_client()
    incident = create_incident(client, request.body)
    return Response(body=incident, code=200)

@func.handler(method='GET', path='/api/incidents')
def on_get(request: Request) -> Response:
    client = get_client()
    incident = get_incident(client, _key(request))
    if not incident:
        return Response(code=404, errors=[APIError(code=404, message="incident not found")])
    return Response(body=incident, code=200)

@func.handler(method='DELETE', path='/api/incidents')
def on_delete(request: Request) -> Response:
    client = get_client()
    if delete_incident(client, _key(request)):
        return Response(body={"deleted": True}, code=200)
    return Response(code=404, errors=[APIError(code=404, message="incident not found")])

if __name__ == '__main__':
    func.run()
```

Key points:
- `CustomStorage(ext_headers=_app_headers())` — the `ext_headers` parameter applies `X-CS-APP-ID` to all requests (needed for local dev; Foundry sets it automatically in production)
- Use `.PutObject(...)` / `.GetObject(...)` / `.DeleteObject(...)` / `.SearchObjects(...)` — direct methods instead of `.command("OperationName", ...)`
- `PutObject` acts as upsert (creates or overwrites by key). Pass body as a dict (not `json.dumps()`).
- `GetObject` returns bytes directly — decode with `json.loads(response.decode("utf-8"))`
- `SearchObjects` returns metadata with `response.get("body", {}).get("resources")` — follow up with `GetObject` per key to retrieve full objects
- FQL filters in `SearchObjects` only work on fields marked `x-cs-indexable: true` in the collection schema

### Uber Class Alternative

For cases where you need the generic Uber class (e.g., calling multiple API services from a single client):

```python
from falconpy import APIHarnessV2

client = APIHarnessV2()

# Uber class requires passing headers per-call (unlike ext_headers on service classes)
headers = {}
if os.environ.get("APP_ID"):
    headers = {"X-CS-APP-ID": os.environ.get("APP_ID")}

response = client.command("PutObject", collection_name="incidents",
                          object_key="id-123", body={"id": "id-123"}, headers=headers)
```

The Foundry functions editor cannot auto-detect scopes from Uber class usage — configure scopes manually in the manifest.

## Error Handling Class Pattern

A small exception class keeps error responses consistent across handlers. Keep it in the function's own directory: shared files outside it don't deploy.

```python
# functions/my-function/errors.py
from crowdstrike.foundry.function import APIError, Response


class FunctionError(Exception):
    def __init__(self, status_code: int, message: str):
        super().__init__(message)
        self.status_code = status_code
        self.message = message

    def to_response(self) -> Response:
        return Response(code=self.status_code,
                        errors=[APIError(code=self.status_code, message=self.message)])
```

```python
# functions/my-function/main.py
from logging import Logger
from typing import Any, Dict, Union
from crowdstrike.foundry.function import APIError, Function, Request, Response
from errors import FunctionError

FUNC = Function.instance()


@FUNC.handler(method="POST", path="/process")
def on_post(request: Request, config: Union[Dict[str, Any], None], logger: Logger) -> Response:
    try:
        if "hostname" not in request.body:
            raise FunctionError(400, "hostname is required")
        # ... processing logic ...
        return Response(body={"result": "ok"}, code=200)
    except FunctionError as e:
        return e.to_response()
    except Exception:
        logger.exception("process failed")
        return Response(code=500, errors=[APIError(code=500, message="An unexpected error occurred")])


if __name__ == "__main__":
    FUNC.run()
```

## Lookup File Uploads

Falcon Next-Gen SIEM lookup files are uploaded with the `NGSIEM` service class, not `CustomStorage` (its `upload`/`PutObject` writes a collection object). Write the rows to a temporary CSV, then upload the file to a repository (adapted from foundry-sample-ngsiem-importer):

```python
import csv
import os
import tempfile
from falconpy import NGSIEM


def upload_lookup(rows, headers, repository="search-all"):
    ngsiem = NGSIEM()
    with tempfile.TemporaryDirectory() as temp_dir:
        output_path = os.path.join(temp_dir, "ti_example.csv")
        with open(output_path, "w", newline="", encoding="utf-8") as csvfile:
            writer = csv.writer(csvfile, quoting=csv.QUOTE_MINIMAL)
            writer.writerow(headers)
            writer.writerows(rows)

        response = ngsiem.upload_file(lookup_file=output_path, repository=repository)
        if response["status_code"] >= 400:
            raise RuntimeError(f"lookup upload failed: {response.get('body', {}).get('errors', [])}")
        return response
```

Key considerations:
- The `humio-auth-proxy:write` scope is required for lookup file uploads (silently fails without it)
- Stream large inputs to the CSV row by row rather than holding them all in memory; the function's memory limit covers runtime plus code
- For large or growing lookup files, send only new or changed rows with `update_lookup_file_entries()` instead of re-uploading the whole file

## LogScale Ingestion

Ingest custom data into Falcon LogScale for querying in Falcon Next-Gen SIEM.

Required manifest scopes:
```yaml
auth:
  scopes:
    - "app-logs:read"
    - "app-logs:write"
```

### Service Class Pattern (Recommended)

`ingest_data` uploads a file, so pass the JSON as bytes in `data_file` (from foundry-sample-logscale):

```python
import os
from io import BytesIO
from json import dumps
from falconpy import FoundryLogScale

data = [
    {"timestamp": "2026-01-15T10:00:00Z", "event_type": "enrichment", "source": "greynoise"},
    {"timestamp": "2026-01-15T10:00:01Z", "event_type": "enrichment", "source": "virustotal"},
]
json_binary = dumps(data).encode(encoding="utf-8")

# X-CS-APP-ID is needed only for local runs; Falcon Foundry sets it when deployed
app_id = os.environ.get("APP_ID")
headers = {"X-CS-APP-ID": app_id} if app_id else {}

logscale = FoundryLogScale(ext_headers=headers)
response = logscale.ingest_data(data_file=BytesIO(json_binary))

if response["status_code"] != 200:
    raise Exception(f"LogScale ingestion failed: {response['body'].get('errors', [])}")
```

### Uber Class Pattern (for advanced use)

```python
from falconpy import APIHarnessV2

uber = APIHarnessV2()
file_tuple = [("data_file", ("data_file", json_binary, "application/json"))]
response = uber.command("IngestDataV1", files=file_tuple, headers=headers)
```

Data takes 1-2 minutes to appear in LogScale after ingestion. The LogScale repository is automatically named `foundry_{app_id}_applicationrepo` (the app ID is populated in `manifest.yml` after first deploy).
