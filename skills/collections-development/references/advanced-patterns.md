# Collections Advanced Patterns

Reference material for schema migrations, testing, pagination, and extended collection patterns. Load when implementing advanced collection features beyond basic CRUD.

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

A typed collection client wrapping the `foundry-js` `Collection` for create/get/update/delete/list. Note the `get()` guard: a never-created key resolves to a truthy not-found envelope, so gate on a field the record must have (`obj.id`), never on truthiness (see the not-found-envelope pitfall in SKILL.md).

```typescript
import { Collection } from '@crowdstrike/foundry-js';

export class IncidentCollection {
  private collection: Collection<Incident>;

  constructor() {
    this.collection = new Collection<Incident>('incidents');
  }

  async create(data: Omit<Incident, 'id' | 'created_at' | 'updated_at'>): Promise<Incident> {
    const incident: Incident = {
      ...data,
      id: crypto.randomUUID(),
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    };
    await this.collection.create(incident.id, incident);
    return incident;
  }

  async get(id: string): Promise<Incident | null> {
    const obj = await this.collection.get(id);
    // A never-created key resolves to a TRUTHY not-found envelope, not null and not a throw.
    // Gate on a field the record must have — never on truthiness.
    if (!obj || !obj.id) return null;
    return obj;
  }

  async update(id: string, updates: Partial<Incident>): Promise<Incident> {
    const existing = await this.get(id);
    if (!existing) throw new Error(`Incident ${id} not found`);
    const updated: Incident = {
      ...existing,
      ...updates,
      id: existing.id,
      created_at: existing.created_at,
      updated_at: new Date().toISOString(),
    };
    await this.collection.update(id, updated);
    return updated;
  }

  async delete(id: string): Promise<void> {
    await this.collection.delete(id);
  }

  async list(options?: { status?: string; limit?: number; offset?: number }) {
    const filters: Record<string, any> = {};
    if (options?.status) filters.status = options.status;
    return this.collection.query(filters, {
      limit: options?.limit ?? 50,
      offset: options?.offset ?? 0,
      sort: [{ field: 'created_at', order: 'desc' }],
    });
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

## Enhanced List Method with Filters

The full list method supports `minSeverity`, `assignedTo`, and `status` filters:

```typescript
async list(options?: {
  status?: Incident['status'];
  minSeverity?: number;
  assignedTo?: string;
  limit?: number;
  offset?: number;
}): Promise<{ items: Incident[]; total: number }> {
  const filters: Record<string, any> = {};

  if (options?.status) {
    filters.status = options.status;
  }
  if (options?.minSeverity) {
    filters.severity = { $gte: options.minSeverity };
  }
  if (options?.assignedTo) {
    filters.assigned_to = options.assignedTo;
  }

  return this.collection.query(filters, {
    limit: options?.limit ?? 50,
    offset: options?.offset ?? 0,
    sort: [{ field: 'created_at', order: 'desc' }],
  });
}
```

## Compound Indexes

Include compound indexes in the manifest when queries filter on multiple fields:

```yaml
collections:
  - name: incidents
    schema: collections/incidents/schema.json
    indexes:
      - fields: ["status"]
      - fields: ["severity"]
      - fields: ["created_at"]
      - fields: ["assigned_to", "status"]  # Compound index for filtered queries
```

## Schema Versioning

Collection schemas are automatically versioned:
- **v1.0** assigned on creation
- Version auto-increments when the schema is modified
- Schema changes are applied to the collection on deploy

## Pagination Patterns

### List Pagination (start/next token)

Use for iterating through all records in a collection:

```yaml
# Workflow pattern: List with pagination
steps:
  - name: list_page
    activity: readCollection
    config:
      collection: incidents
      operation: list
      start: $steps.previous_page.output.next  # null for first page
      limit: 100

  - name: check_more
    if: $steps.list_page.output.next != null
    activity: goto
    config:
      step: list_page
```

### Search Pagination (offset/total)

Use for filtered queries with known total count:

```yaml
steps:
  - name: search_page
    activity: readCollection
    config:
      collection: incidents
      operation: search
      filter: "status:'open'"
      offset: $steps.track_offset.output.current_offset
      limit: 100

  - name: check_more
    if: $steps.track_offset.output.current_offset < $steps.search_page.output.total
    activity: goto
    config:
      step: search_page
```

## Schema Migration Patterns

> **Migrate data, not the collection definition.** These patterns evolve the *objects* inside an existing collection. The collection's schema, TTL, and name themselves cannot change in place on a custom-storage collection (written via `custom_storage_object_key`) — adding a TTL or tightening the schema fails deploy with `custom_storage_object_key is a reserved input property`, and renaming orphans the data. See the custom-storage immutability and no-in-place-rename pitfalls in SKILL.md.

**Pattern: Version-Based Migration**

```typescript
// migrations/incidents_v2.ts
import { Collection, Migration } from '@crowdstrike/foundry-js';

export const incidentsMigrationV2: Migration = {
  version: 2,
  description: 'Add priority field and rename severity_level to severity',

  async up(collection: Collection<any>): Promise<void> {
    const allDocs = await collection.query({}, { limit: 1000 });

    for (const doc of allDocs.items) {
      const updates: Record<string, any> = {};

      // Rename field
      if ('severity_level' in doc && !('severity' in doc)) {
        updates.severity = doc.severity_level;
        updates.severity_level = undefined;  // Remove old field
      }

      // Add new field with default
      if (!('priority' in doc)) {
        updates.priority = doc.severity >= 8 ? 'critical' : 'normal';
      }

      if (Object.keys(updates).length > 0) {
        await collection.update(doc.id, { ...doc, ...updates });
      }
    }
  },

  async down(collection: Collection<any>): Promise<void> {
    // Reverse migration if needed
    const allDocs = await collection.query({}, { limit: 1000 });

    for (const doc of allDocs.items) {
      if ('severity' in doc) {
        await collection.update(doc.id, {
          ...doc,
          severity_level: doc.severity,
          severity: undefined,
          priority: undefined,
        });
      }
    }
  },
};
```

## Testing Patterns

**Pattern: Collection Unit Tests**

```typescript
// tests/collections/incidents.test.ts
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { IncidentCollection, Incident } from '@/lib/collections/incidents';

vi.mock('@crowdstrike/foundry-js', () => ({
  Collection: vi.fn().mockImplementation(() => ({
    create: vi.fn(),
    get: vi.fn(),
    update: vi.fn(),
    delete: vi.fn(),
    query: vi.fn(),
  })),
}));

describe('IncidentCollection', () => {
  let collection: IncidentCollection;

  beforeEach(() => {
    vi.clearAllMocks();
    collection = new IncidentCollection();
  });

  describe('create', () => {
    it('creates incident with generated id and timestamps', async () => {
      const input = { title: 'Test', severity: 5, status: 'open' as const };
      const result = await collection.create(input);

      expect(result.id).toBeDefined();
      expect(result.created_at).toBeDefined();
      expect(result.updated_at).toBeDefined();
      expect(result.title).toBe('Test');
    });
  });

  describe('update', () => {
    it('preserves id and created_at on update', async () => {
      const existing: Incident = {
        id: 'test-id',
        title: 'Original',
        severity: 5,
        status: 'open',
        created_at: '2024-01-01T00:00:00Z',
        updated_at: '2024-01-01T00:00:00Z',
      };

      vi.mocked(collection['collection'].get).mockResolvedValue(existing);

      const result = await collection.update('test-id', { title: 'Updated' });

      expect(result.id).toBe('test-id');
      expect(result.created_at).toBe('2024-01-01T00:00:00Z');
      expect(result.title).toBe('Updated');
      expect(result.updated_at).not.toBe(existing.updated_at);
    });
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
