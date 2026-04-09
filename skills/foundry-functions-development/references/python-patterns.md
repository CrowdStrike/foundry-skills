# Python Function Patterns Reference

> Parent skill: [foundry-functions-development](../SKILL.md)

## Lambda-Style Handler Pattern

Full REST endpoint handler using the legacy lambda-style pattern (pre-FDK):

```python
# functions/alerts/main.py
import json
from typing import Dict, Any, Optional, List
from dataclasses import dataclass, asdict
from falconpy import Alerts

@dataclass
class APIError:
    code: str
    message: str

@dataclass
class APIResponse:
    status: int
    data: Optional[Any] = None
    error: Optional[APIError] = None

    def to_dict(self) -> Dict[str, Any]:
        result = {"status": self.status}
        if self.data is not None:
            result["data"] = self.data
        if self.error is not None:
            result["error"] = asdict(self.error)
        return result

def handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """Main function handler for alert retrieval."""

    # Validate request method
    method = event.get("httpMethod", "GET")
    if method != "GET":
        return respond_error(405, "METHOD_NOT_ALLOWED", "Only GET method is supported")

    try:
        # Initialize Falcon API client (zero-arg: auto-discovers credentials)
        falcon = Alerts()

        # Parse query parameters
        params = event.get("queryStringParameters", {}) or {}
        limit = min(int(params.get("limit", 50)), 100)  # Cap at 100

        # Fetch alerts
        alerts_data = fetch_alerts(falcon, limit)

        return respond_success(alerts_data)

    except ValueError as e:
        return respond_error(400, "INVALID_INPUT", str(e))
    except Exception as e:
        return respond_error(500, "INTERNAL_ERROR", "An unexpected error occurred")

def fetch_alerts(falcon: Alerts, limit: int) -> List[Dict[str, Any]]:
    """Fetch alerts from Falcon API."""
    response = falcon.query_alerts_v2(limit=limit)

    if response["status_code"] != 200:
        raise Exception(f"API error: {response.get('errors', [])}")

    alert_ids = response.get("body", {}).get("resources", [])

    if not alert_ids:
        return []

    # Get full alert details
    details_response = falcon.get_alerts_v2(ids=alert_ids)

    if details_response["status_code"] != 200:
        raise Exception("Failed to fetch alert details")

    return details_response.get("body", {}).get("resources", [])

def respond_success(data: Any) -> Dict[str, Any]:
    """Create success response."""
    response = APIResponse(status=200, data=data)
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(response.to_dict())
    }

def respond_error(status: int, code: str, message: str) -> Dict[str, Any]:
    """Create error response."""
    response = APIResponse(status=status, error=APIError(code=code, message=message))
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(response.to_dict())
    }
```

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
from crowdstrike.foundry.function import Function, Request, Response
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
    response = client.PutObject(
        collection_name=COLLECTION_NAME,
        object_key=incident_id,
        body=incident,
    )
    if response["status_code"] != 200:
        raise Exception(f"Failed to create incident: {response.get('errors', [])}")
    return incident

def get_incident(client: CustomStorage, incident_id: str) -> Optional[Dict[str, Any]]:
    """Retrieve an incident by key. GetObject returns bytes — decode to dict."""
    response = client.GetObject(
        collection_name=COLLECTION_NAME,
        object_key=incident_id,
    )
    if isinstance(response, dict) and response.get("status_code") == 404:
        return None
    if isinstance(response, dict) and response.get("status_code", 200) != 200:
        raise Exception(f"Failed to get incident: {response.get('errors', [])}")
    return json.loads(response.decode("utf-8"))

def delete_incident(client: CustomStorage, incident_id: str) -> bool:
    """Delete an incident by key."""
    response = client.DeleteObject(
        collection_name=COLLECTION_NAME,
        object_key=incident_id,
    )
    return response["status_code"] == 200

def search_incidents(client: CustomStorage, fql_filter: str = "", limit: int = 50) -> List[Dict[str, Any]]:
    """Search incidents using FQL filter. Only indexed fields are filterable."""
    response = client.SearchObjects(
        collection_name=COLLECTION_NAME,
        filter=fql_filter,
        limit=limit,
    )
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

# Handler process
@func.handler(method='POST', path='/api/incidents')
def on_create(request: Request) -> Response:
    client = get_client()
    incident = create_incident(client, request.body)
    return Response(body=incident, code=200)

@func.handler(method='GET', path='/api/incidents/{id}')
def on_get(request: Request) -> Response:
    client = get_client()
    incident = get_incident(client, request.params.get("id", ""))
    if not incident:
        return Response(body={"error": "Not found"}, code=404)
    return Response(body=incident, code=200)

@func.handler(method='DELETE', path='/api/incidents/{id}')
def on_delete(request: Request) -> Response:
    client = get_client()
    if delete_incident(client, request.params.get("id", "")):
        return Response(body={"deleted": True}, code=200)
    return Response(body={"error": "Not found"}, code=404)

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

Structured error class with enum codes for consistent error responses:

```python
# functions/common/errors.py
from enum import Enum
from typing import Optional
import json

class ErrorCode(Enum):
    VALIDATION_ERROR = "VALIDATION_ERROR"
    NOT_FOUND = "NOT_FOUND"
    UNAUTHORIZED = "UNAUTHORIZED"
    FORBIDDEN = "FORBIDDEN"
    RATE_LIMITED = "RATE_LIMITED"
    INTERNAL_ERROR = "INTERNAL_ERROR"
    SERVICE_UNAVAILABLE = "SERVICE_UNAVAILABLE"

class FunctionError(Exception):
    def __init__(
        self,
        code: ErrorCode,
        message: str,
        status_code: int = 500,
        details: Optional[dict] = None
    ):
        self.code = code
        self.message = message
        self.status_code = status_code
        self.details = details or {}
        super().__init__(message)

    def to_response(self) -> dict:
        return {
            "statusCode": self.status_code,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({
                "status": self.status_code,
                "error": {
                    "code": self.code.value,
                    "message": self.message,
                    "details": self.details
                }
            })
        }

# Usage in handler
def handler(event, context):
    try:
        # ... processing logic ...
        pass
    except FunctionError as e:
        return e.to_response()
    except Exception as e:
        return FunctionError(
            ErrorCode.INTERNAL_ERROR,
            "An unexpected error occurred",
            500
        ).to_response()
```

## Batch Processing and Memory Management

Process large data sets in batches to stay within the 1 GB memory limit. This example uses the `CustomStorage` service class for **lookup file uploads**, which is a different use case from collection CRUD (see above):

```python
import gc
from falconpy import CustomStorage

def process_large_dataset(records, batch_size=10000):
    """Process records in batches to manage memory."""
    storage = CustomStorage()

    for i in range(0, len(records), batch_size):
        batch = records[i:i + batch_size]
        # Process batch...
        result = storage.upload(body=batch)

        # Free memory between batches
        del batch
        gc.collect()
```

Key considerations:
- Process in batches of ~10,000 records
- Call `gc.collect()` between batches to free memory
- The `humio-auth-proxy:write` scope is required for lookup file uploads (silently fails without it)
- Lookup files are limited to 50 MB

## LogScale Ingestion

Ingest custom data into Falcon LogScale for querying in Falcon Next-Gen SIEM.

Required manifest scopes:
```yaml
oauth_scopes:
  - "app-logs:read"
  - "app-logs:write"
```

### Service Class Pattern (Recommended)

```python
from falconpy import FoundryLogScale

logscale = FoundryLogScale()

data = [
    {"timestamp": "2026-01-15T10:00:00Z", "event_type": "enrichment", "source": "greynoise"},
    {"timestamp": "2026-01-15T10:00:01Z", "event_type": "enrichment", "source": "virustotal"},
]

response = logscale.ingest_data(body=data)

if response["status_code"] != 200:
    raise Exception(f"LogScale ingestion failed: {response.get('errors', [])}")
```

### Uber Class Pattern (for advanced use)

```python
from falconpy import APIHarnessV2
from falconpy.api_complete import IngestDataV1

uber = APIHarnessV2()
response = uber.command("IngestDataV1", body=data)
```

Data takes 1-2 minutes to appear in LogScale after ingestion. The LogScale repository is automatically named `foundry_{app_id}_applicationrepo` (the app ID is populated in `manifest.yml` after first deploy).
