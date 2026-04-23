---
name: collections
description: Design collection schemas, perform CRUD operations, search with FQL, and use collections in UI extensions and workflows
source: https://www.crowdstrike.com/tech-hub/ng-siem/getting-started-with-falcon-foundry-collections-your-guide-to-structured-data-storage-in-foundry-apps/
skills: [foundry-collections-development]
capabilities: [collection]
---

## When to Use

User wants to persist structured data (config, checkpoints, event logs, user preferences), import CSV data, query collections with FQL, access collections from UI extensions, or paginate collection results in workflows.

## Pattern

1. **Design the JSON Schema** (Draft 7) with `x-cs-indexable-fields` for searchable fields (max 10):
   ```json
   {
     "$schema": "https://json-schema.org/draft-07/schema",
     "x-cs-indexable-fields": [
       { "field": "/userId", "type": "string", "fql_name": "user_id" },
       { "field": "/lastUpdated", "type": "integer", "fql_name": "last_updated" }
     ],
     "type": "object",
     "properties": { ... },
     "required": ["userId"]
   }
   ```
2. **Create the collection** via CLI:
   ```bash
   foundry collections create --name my_data \
     --schema schemas/my_data.json --description "Purpose" --no-prompt
   ```
3. **Validate early** with `foundry apps validate --no-prompt` to check the schema against the platform.
4. **Access from functions** using `APIHarnessV2` (see Key Code).
5. **Access from UI extensions** using `@crowdstrike/foundry-js`.
6. **Configure workflow sharing** if the collection needs to be used in workflows.

## Key Code

**Schema with validation rules:**
```json
{
  "x-cs-indexable-fields": [
    { "field": "/event_id", "type": "string", "fql_name": "event_id" },
    { "field": "/severity", "type": "string", "fql_name": "severity" },
    { "field": "/timestamp_unix", "type": "integer", "fql_name": "timestamp_unix" }
  ],
  "properties": {
    "severity": {
      "type": "string",
      "enum": ["low", "medium", "high", "critical"]
    },
    "confidenceThreshold": {
      "type": "integer",
      "minimum": 0,
      "maximum": 100
    }
  }
}
```

**CRUD from Python functions (FalconPy):**
```python
from falconpy import APIHarnessV2
import json

api = APIHarnessV2()
headers = {}  # set X-CS-APP-ID for local testing

# Create/Update
api.command("PutObject", body=data,
    collection_name="my_data", object_key=unique_id, headers=headers)

# Search (returns metadata only, not full objects)
results = api.command("SearchObjects",
    filter="severity:'high'", collection_name="my_data",
    limit=50, sort="timestamp_unix.desc", headers=headers)

# Get full object (returns bytes)
obj = api.command("GetObject",
    collection_name="my_data", object_key=key, headers=headers)
data = json.loads(obj.decode("utf-8"))

# Delete
api.command("DeleteObject",
    collection_name="my_data", object_key=key, headers=headers)
```

**FQL query patterns:**
```python
# Equality
filter="user_id:'john.smith'"
# Numeric comparison
filter="confidence_threshold:>80"
# AND (use +)
filter="user_id:'john.smith'+last_login:>1623456789"
# OR (use array syntax)
filter="user_id:['john.smith','jane.doe']"
# Wildcard
filter="hostname:*'web-server*'"
```

**UI extension access (foundry-js):**
```javascript
import FalconApi from '@crowdstrike/foundry-js';
const falcon = new FalconApi();
await falcon.connect();

const prefs = falcon.collection({ collection: 'user_preferences' });
await prefs.write(userId, { theme: 'dark', lastUpdated: Date.now() });
const data = await prefs.read(userId);
const results = await prefs.search({ filter: "theme:'dark'" });
await prefs.delete(userId);
```

**Workflow share settings (CLI):**
```bash
# App workflows only
foundry collections create --name X --schema S --wf-expose=true \
  --wf-app-only-action=true --no-prompt
# App + Fusion SOAR
foundry collections create --name X --schema S --wf-expose=true \
  --wf-app-only-action=false --no-prompt
# No workflow sharing
foundry collections create --name X --schema S --wf-expose=false --no-prompt
```

## Gotchas

- **`SearchObjects` returns metadata, not full objects.** You must call `GetObject` with the `object_key` from search results to get actual values.
- **`GetObject` returns bytes**, not a dict. Always `json.loads(result.decode("utf-8"))`.
- **Max 10 indexable fields** per collection schema.
- **UI extension `search()` does NOT use FQL.** It requires exact match values, unlike the Python API.
- **Separate API credentials needed** for local collection access. The Foundry CLI credentials lack Custom Storage scope. Create a new API client with Custom Storage read/write.
- **`X-CS-APP-ID` header** is auto-set in cloud. For local dev, set `APP_ID` env var.
- **No separate edit command**: Use `foundry collections create` with the same name to update an existing collection.
- **Workflow pagination uses two patterns**: List operations use a `next` token (start key); Search operations use `offset` with `total` tracking. For List loops, check `next:!null`. For Search loops, check `offset < total`.
- **`foundryCustomStorageObjectKey` format** is required in trigger schemas for `Get object` and `Delete object` actions to appear in workflow search.
