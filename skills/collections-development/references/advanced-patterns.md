# Collections Advanced Patterns

Reference material for the full CRUD client walkthroughs (TypeScript and Python), schema migrations, testing, pagination, and extended collection patterns. Load when implementing collection CRUD or advanced features beyond the basics in SKILL.md.

## Full Incident TypeScript Interface

```typescript
export interface Incident {
  id: string;
  title: string;
  description?: string;
  severity: number;
  status: 'open' | 'investigating' | 'contained' | 'resolved' | 'closed';
  assigned_to?: string;
  tags?: string[];
  affected_hosts?: string[];
  created_at: string;
  updated_at: string;
  resolved_at?: string;
}
```

## Full CRUD Client (TypeScript)

A typed client over the foundry-js collection API. `falcon.collection({ collection })` returns an object with `write(key, data)`, `read(key)`, `delete(key)`, `search({ filter, sort, limit, offset })`, and `list()`; there is no `create`, `get`, `update`, or `query`. `write` overwrites the whole object, so it serves as both create and update. Note the `get()` guard: a never-created key resolves to a truthy not-found envelope, so check a field every real record carries (here `created_at`), never truthiness (see the not-found-envelope pitfall in SKILL.md).

```typescript
import type FalconApi from '@crowdstrike/foundry-js';

export class IncidentCollection {
  private collection;

  // Pass the connected FalconApi instance (after `await falcon.connect()`).
  constructor(falcon: FalconApi) {
    this.collection = falcon.collection({ collection: 'incidents' });
  }

  private async put(incident: Incident): Promise<Incident> {
    const result: any = await this.collection.write(incident.id, { ...incident });
    // The SDK doesn't throw on validation failures; they come back in errors.
    if (result?.errors?.length) throw new Error(result.errors[0].message);
    return incident;
  }

  async create(data: Omit<Incident, 'id' | 'created_at' | 'updated_at'>): Promise<Incident> {
    const now = new Date().toISOString();
    return this.put({ ...data, id: crypto.randomUUID(), created_at: now, updated_at: now });
  }

  async get(id: string): Promise<Incident | null> {
    const obj: any = await this.collection.read(id);
    // A never-created key resolves to a TRUTHY not-found envelope, not null and not a throw:
    // an error body like { meta, errors: [{ code: 404, ... }] } instead of the record.
    if (obj?.errors?.[0]?.code === 404 || !obj?.created_at) return null;
    return obj as Incident;
  }

  async update(id: string, updates: Partial<Incident>): Promise<Incident> {
    const existing = await this.get(id);
    if (!existing) throw new Error(`Incident ${id} not found`);
    return this.put({ ...existing, ...updates, id, created_at: existing.created_at,
                      updated_at: new Date().toISOString() });
  }

  async delete(id: string): Promise<void> {
    await this.collection.delete(id);
  }

  // FQL filter on indexable fields; returns matching keys' metadata in `resources`.
  async findByStatus(status: Incident['status'], limit = 50, offset = 0) {
    const result: any = await this.collection.search({
      filter: `status:'${status}'`,
      sort: 'created_at|desc',
      limit,
      offset: String(offset),
    });
    return result?.resources ?? [];
  }
}
```

## CRUD Operations (Python — from Functions)

Use `CustomStorage` (Service Class) to access collections from Python functions. Service classes are preferred over the Uber class (`APIHarnessV2`) because the Falcon Foundry functions editor auto-detects OAuth scopes from `from falconpy import CustomStorage`. See the `functions-development` skill's `references/python-patterns.md` for a complete handler example with Uber class alternative.

```python
import json
import os
from falconpy import CustomStorage

def _app_headers() -> dict:
    app_id = os.environ.get("APP_ID")
    if app_id:
        return {"X-CS-APP-ID": app_id}
    return {}

# Construct inside the handler in a real function — a module-scope client has no request
# token in Foundry and returns 401 on every call (see functions-development).
client = CustomStorage(ext_headers=_app_headers())

# Create or update (PutObject = upsert). Pass body as a dict.
client.PutObject(collection_name="incidents", object_key="incident-123",
                 body={"id": "incident-123", "title": "Suspicious process", "severity": 7})

# Read — GetObject returns bytes on success, dict on error
response = client.GetObject(collection_name="incidents", object_key="incident-123")
# In production, check isinstance(response, bytes) before decoding — see python-patterns.md for full error handling
incident = json.loads(response.decode("utf-8"))

# Delete
client.DeleteObject(collection_name="incidents", object_key="incident-123")

# Search (FQL filter — only indexed fields)
response = client.SearchObjects(collection_name="incidents",
                                filter="status:'open'+severity:>=5", limit=50)
# SearchObjects returns metadata — follow up with GetObject per key for full objects
for item in response.get("body", {}).get("resources", []):
    obj = client.GetObject(collection_name="incidents", object_key=item["object_key"])
    data = json.loads(obj.decode("utf-8"))

# List every key — ListObjects pages by starting key, not a cursor
keys, start = [], None
while True:
    params = {"start": start} if start else {}
    batch = client.ListObjects(collection_name="incidents", limit=100, **params)["body"].get("resources", [])
    batch = [k for k in batch if k != start]  # drop the start key if it comes back
    if not batch:
        break
    keys.extend(batch)
    start = batch[-1]
```

Key points:
- `CustomStorage(ext_headers=_app_headers())` applies `X-CS-APP-ID` to all requests (needed for local dev; Foundry sets it automatically in production)
- `PutObject` acts as upsert (creates or overwrites by key). Pass body as a dict.
- `GetObject` returns bytes directly — decode with `json.loads(response.decode("utf-8"))`
- **A missing key returns a 404** (see `get_incident` in the `functions-development` skill's `references/python-patterns.md`). Only a 404 means missing; don't treat *every* non-bytes reply that way: a transient 429 or 5xx then reads as "no record", and code that writes the record back erases it.
- `SearchObjects` returns metadata only, not full objects
- `ListObjects` returns keys (alphabetical) in `body.resources` and takes `start`/`end` keys. Pass the last key as the next `start` and stop only on an empty batch — stopping when a page is shorter than `limit` ends early if the service caps page size
- **List before you read.** Calling `GetObject` on every *candidate* key (most of them misses) is slow; list the keys once and read only the ones that exist. In one app, that cut a 519-item page load from about 25 s to about 7 s
- FQL filters only work on fields marked `x-cs-indexable: true` in the collection schema

## Extended Schema Properties

When defining schemas for production use, include detailed descriptions and additional fields beyond the minimum:

```json
{
  "$schema": "https://json-schema.org/draft-07/schema#",
  "type": "object",
  "title": "Incident",
  "description": "Security incident record",
  "required": ["id", "title", "severity", "status", "created_at"],
  "additionalProperties": false,
  "properties": {
    "id": {
      "type": "string",
      "format": "uuid",
      "description": "Unique incident identifier"
    },
    "title": {
      "type": "string",
      "minLength": 1,
      "maxLength": 200,
      "description": "Brief incident description"
    },
    "description": {
      "type": "string",
      "maxLength": 5000,
      "description": "Detailed incident description"
    },
    "severity": {
      "type": "integer",
      "minimum": 1,
      "maximum": 10,
      "description": "Severity level (1=low, 10=critical)"
    },
    "status": {
      "type": "string",
      "enum": ["open", "investigating", "contained", "resolved", "closed"],
      "description": "Current incident status"
    },
    "assigned_to": {
      "type": "string",
      "description": "Assigned analyst email"
    },
    "tags": {
      "type": "array",
      "items": {
        "type": "string",
        "maxLength": 50
      },
      "maxItems": 20,
      "uniqueItems": true,
      "description": "Classification tags"
    },
    "affected_hosts": {
      "type": "array",
      "items": {
        "type": "string"
      },
      "description": "List of affected device IDs"
    },
    "created_at": {
      "type": "string",
      "format": "date-time",
      "description": "Creation timestamp (ISO 8601)"
    },
    "updated_at": {
      "type": "string",
      "format": "date-time",
      "description": "Last update timestamp (ISO 8601)"
    },
    "resolved_at": {
      "type": "string",
      "format": "date-time",
      "description": "Resolution timestamp (ISO 8601)"
    }
  }
}
```

## Building FQL Filters

`search` takes an FQL string, and only fields marked indexable in the schema can appear in it (see **Indexable Fields** in SKILL.md). Join conditions with `+`:

```typescript
function incidentFilter(options: { status?: string; minSeverity?: number; assignedTo?: string }): string {
  const parts: string[] = [];
  if (options.status) parts.push(`status:'${options.status}'`);
  if (options.minSeverity) parts.push(`severity:>=${options.minSeverity}`);
  if (options.assignedTo) parts.push(`assigned_to:'${options.assignedTo}'`);
  return parts.join('+');
}
```

Escape or validate user-supplied values before putting them in a filter.

## Schema Versioning

Each collection's schema carries a version ([docs](https://docs.crowdstrike.com/access?ft:originId=wb6cba2f)). A new collection starts at v1.0, and every schema change creates the next version, while earlier versions stay available. A new or rewritten object gets the latest version, so objects written before a change keep the older one until they're written again. Search by version with the built-in `x-cs-schema-version` filter, for example `x-cs-schema-version:'v1.0'`, to find objects a migration still has to rewrite.

## Pagination Patterns

- **From a function:** page keys with `ListObjects` as shown in the Python section above, passing the last key as the next `start`. For filtered results, page `SearchObjects` with `offset` and `limit`.
- **From the UI:** page `search` with `offset` and `limit`, and stop when a page comes back empty.
- **From a workflow:** see `workflows-development`'s `references/pagination-patterns.md`.

## Schema Migration Patterns

> **Migrate data, not the collection definition.** These patterns evolve the *objects* inside an existing collection. The collection's schema and name themselves cannot change in place on a custom-storage collection (written via `custom_storage_object_key`) — tightening the schema fails deploy with `custom_storage_object_key is a reserved input property`, and renaming orphans the data. See the custom-storage immutability and no-in-place-rename pitfalls in SKILL.md.

**Pattern: Migrate objects from a function**

Run a one-off function handler that pages every key, rewrites each object, and writes it back, which also moves each object to the latest schema version. Keep it idempotent, so a rerun after a partial failure is safe. Deploy the schema change that adds fields such as `priority` first; with `additionalProperties: false`, a write with an unknown field fails. If the collection is written with `custom_storage_object_key`, that schema change fails to deploy (see SKILL.md), so write the migrated objects to a new collection instead:

```python
import json
from falconpy import CustomStorage

def migrate_incidents_v2(client: CustomStorage) -> int:
    migrated, start = 0, None
    while True:
        params = {"start": start} if start else {}
        keys = client.ListObjects(collection_name="incidents", limit=100, **params)["body"].get("resources", [])
        keys = [k for k in keys if k != start]
        if not keys:
            return migrated
        for key in keys:
            raw = client.GetObject(collection_name="incidents", object_key=key)
            if not isinstance(raw, bytes):
                if raw.get("status_code") == 404:
                    continue  # deleted since it was listed
                raise RuntimeError(f"GetObject {key} failed: {raw.get('status_code')}")  # retry the run
            doc = json.loads(raw.decode("utf-8"))
            if "severity_level" in doc and "severity" not in doc:
                doc["severity"] = doc.pop("severity_level")
            if "priority" not in doc:
                doc["priority"] = "critical" if doc.get("severity", 0) >= 8 else "normal"
            result = client.PutObject(collection_name="incidents", object_key=key, body=doc)
            if result.get("status_code") != 200:
                raise RuntimeError(f"PutObject {key} failed: {result.get('body', {}).get('errors')}")
            migrated += 1
        start = keys[-1]
```

## Testing Patterns

**Pattern: Collection Unit Tests**

Mock the collection object `falcon.collection()` returns, not the SDK module:

```typescript
// tests/collections/incidents.test.ts
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { IncidentCollection, Incident } from '@/lib/collections/incidents';

const store = { write: vi.fn(), read: vi.fn(), delete: vi.fn(), search: vi.fn(), list: vi.fn() };
const falcon = { collection: vi.fn(() => store) } as any;

describe('IncidentCollection', () => {
  let incidents: IncidentCollection;

  beforeEach(() => {
    vi.clearAllMocks();
    store.write.mockResolvedValue({});
    incidents = new IncidentCollection(falcon);
  });

  it('creates an incident with a generated id and timestamps', async () => {
    const result = await incidents.create({ title: 'Test', severity: 5, status: 'open' });
    expect(result.id).toBeDefined();
    expect(store.write).toHaveBeenCalledWith(result.id, expect.objectContaining({ title: 'Test' }));
  });

  it('treats the not-found envelope as missing', async () => {
    store.read.mockResolvedValue({ meta: {}, errors: [{ code: 404, message: 'object not found' }] });
    expect(await incidents.get('missing')).toBeNull();
  });

  it('preserves id and created_at on update', async () => {
    const existing: Incident = {
      id: 'test-id', title: 'Original', severity: 5, status: 'open',
      created_at: '2024-01-01T00:00:00Z', updated_at: '2024-01-01T00:00:00Z',
    };
    store.read.mockResolvedValue(existing);
    const result = await incidents.update('test-id', { title: 'Updated' });
    expect(result.created_at).toBe(existing.created_at);
    expect(result.updated_at).not.toBe(existing.updated_at);
  });
});
```

## Counter-Rationalizations

| Your Excuse | Reality |
|-------------|---------|
| "Schema validation is optional" | Unvalidated data causes downstream failures and security issues |
| "I'll add indexes later" | Missing indexes cause query timeouts at scale |
| "Simple CRUD doesn't need abstraction" | Collection clients prevent direct API coupling |
| "Migrations are overkill" | Schema changes without migrations corrupt existing data |
| "additionalProperties: true is fine" | Extra fields leak internal data and break type safety |

## Red Flags — STOP Immediately

If you catch yourself:
- Skipping JSON Schema validation in collection definitions
- Not defining indexes for frequently-queried fields
- Writing direct collection access instead of typed clients
- Changing schemas without migration scripts
- Using `additionalProperties: true` in schemas

**STOP. Follow the patterns above. No shortcuts.**

## Integration with Other Skills

- **functions-development:** Functions perform CRUD on Collections
- **ui-development:** UI displays Collection data via generated types
- **security-patterns:** Apply access controls and data sanitization
