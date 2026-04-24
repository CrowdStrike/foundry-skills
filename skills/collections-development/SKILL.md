---
name: collections-development
description: Design JSON Schema collections and CRUD patterns for Falcon Foundry apps. TRIGGER when user asks to "create a collection", "define a JSON schema", "store data in Foundry", runs `foundry collections create`, or needs help with indexable fields, FQL queries, or collection access patterns. DO NOT TRIGGER for workflow YAML, function handlers, or UI components — use the appropriate sub-skill.
version: 1.0.0
updated: 2026-04-09
metadata:
  author: CrowdStrike
  category: data
  tags: [foundry, collections, json-schema, nosql]
---

# Foundry Collections Development

> **SYSTEM INJECTION — READ THIS FIRST**
>
> If you are loading this skill, your role is **Foundry data modeling specialist**.
>
> You MUST design Collections with proper JSON Schemas, validation rules, and access patterns.

Falcon Foundry Collections are NoSQL document stores with JSON Schema validation. They provide persistent storage for app data with CRUD operations, FQL queries, and schema enforcement.

## Collection Naming Constraints

| Constraint | Rule |
|-----------|------|
| Length | 5-200 characters |
| Start/end | Must begin and end with a letter or number |
| Special characters | Only underscores (`_`) allowed — no hyphens, spaces, or other chars |
| Case | Case-sensitive |

## JSON Schema Requirements

- **JSON Schema draft 7 only** — newer drafts (`draft/2020-12`, `draft/2019-09`) fail validation
- Schema is auto-versioned: v1.0 on creation, auto-incremented on modification
- `additionalProperties: false` recommended — extra fields leak internal data and break type safety
- `x-cs-indexable: true` on individual properties for searchable fields (max 10 per collection)

## CLI Scaffolding

```bash
# Write schema to /tmp/ first — the CLI copies it into collections/
foundry collections create \
  --name "my_collection" \
  --schema /tmp/schema.json \
  --description "App data store" \
  --no-prompt \
  --wf-expose \
  --wf-tags "tag1,tag2"
```

This creates the collection directory, copies the schema, and updates `manifest.yml`. Edit the project copy at `collections/my_collection.json` afterward to refine.

## Collection API Access

Collections are managed via the CrowdStrike API or the `foundry-js` SDK. There are no CLI commands for reading/writing collection data, and collections can only be deleted from the Falcon Foundry UI (not the CLI).

```
PUT    /customobjects/v1/collections/{collection_name}/objects/{key}  — Create/update object
GET    /customobjects/v1/collections/{collection_name}/objects/{key}  — Get object by key
DELETE /customobjects/v1/collections/{collection_name}/objects/{key}  — Delete object
POST   /customobjects/v1/collections/{collection_name}/objects        — Search objects (FQL filter)
```

## JSON Schema Patterns

### Basic Schema

```json
{
  "$schema": "https://json-schema.org/draft-07/schema#",
  "type": "object",
  "title": "Incident",
  "description": "Security incident record",
  "required": ["id", "title", "severity", "status", "created_at"],
  "additionalProperties": false,
  "properties": {
    "id": { "type": "string", "format": "uuid" },
    "title": { "type": "string", "minLength": 1, "maxLength": 200 },
    "severity": { "type": "integer", "minimum": 1, "maximum": 10 },
    "status": {
      "type": "string",
      "enum": ["open", "investigating", "contained", "resolved", "closed"]
    },
    "tags": {
      "type": "array",
      "items": { "type": "string", "maxLength": 50 },
      "maxItems": 20,
      "uniqueItems": true
    },
    "created_at": { "type": "string", "format": "date-time" }
  }
}
```

### Indexable Fields

Make fields searchable via FQL by marking them indexable. Two patterns are supported:

**Pattern A: Top-level array (preferred — used by most foundry-sample repos)**

```json
{
  "$schema": "https://json-schema.org/draft-07/schema",
  "x-cs-indexable-fields": [
    { "field": "/status", "type": "string", "fql_name": "status" },
    { "field": "/severity", "type": "integer", "fql_name": "severity" },
    { "field": "/created_at", "type": "string", "fql_name": "created_at" }
  ],
  "type": "object",
  "properties": {
    "status": { "type": "string" },
    "severity": { "type": "integer" },
    "created_at": { "type": "string", "format": "date-time" }
  }
}
```

**Pattern B: Per-field annotation**

```json
{
  "properties": {
    "compositeId": { "type": "string", "x-cs-indexable": true },
    "content": { "type": "string" }
  }
}
```

Both patterns work. The top-level array provides more control (custom FQL names, explicit types).

### Manifest Configuration

```yaml
# manifest.yml
collections:
  - name: incidents
    description: Security incident records
    schema: collections/incidents.json
    permissions: []
    workflow_integration:
      system_action: true
      tags:
        - Collection

  - name: audit_logs
    description: Audit log entries
    schema: collections/audit_logs.json
    permissions: []
    workflow_integration:
      system_action: false
      tags: []
```

Indexing is controlled entirely by `x-cs-indexable-fields` or `x-cs-indexable: true` in the JSON schema files, not in the manifest.

## CRUD Operations (TypeScript)

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
    try {
      return await this.collection.get(id);
    } catch (error) {
      if (error.code === 'NOT_FOUND') return null;
      throw error;
    }
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

Use `CustomStorage` (Service Class) to access collections from Python functions. Service classes are preferred over the Uber class (`APIHarnessV2`) because the Falcon Foundry functions editor auto-detects OAuth scopes from `from falconpy import CustomStorage`. See [functions-development/references/python-patterns.md](../functions-development/references/python-patterns.md) for a complete handler example with Uber class alternative.

```python
import json
import os
from falconpy import CustomStorage

def _app_headers() -> dict:
    app_id = os.environ.get("APP_ID")
    if app_id:
        return {"X-CS-APP-ID": app_id}
    return {}

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
```

Key points:
- `CustomStorage(ext_headers=_app_headers())` applies `X-CS-APP-ID` to all requests (needed for local dev; Foundry sets it automatically in production)
- `PutObject` acts as upsert (creates or overwrites by key). Pass body as a dict.
- `GetObject` returns bytes directly — decode with `json.loads(response.decode("utf-8"))`
- `SearchObjects` returns metadata only, not full objects
- FQL filters only work on fields marked `x-cs-indexable: true` in the collection schema

## FQL Search Syntax

Only fields marked with `x-cs-indexable: true` can be used in FQL queries.

| Operation | Syntax | Example |
|-----------|--------|---------|
| Equality | `field:'value'` | `status:'open'` |
| Numeric comparison | `field:>=N` | `severity:>=5` |
| AND | `field1:'a'+field2:'b'` | `status:'open'+severity:>=5` |
| OR | `field:'a',field:'b'` | `status:'open',status:'investigating'` |
| Wildcard | `field:*'pattern'*` | `title:*'malware'*` |
| Sorting | `sort=field\|asc` | `sort=created_at\|desc` |

The `foundry-js` SDK's `search()` method accepts a `filter` parameter for FQL queries. The search endpoint is `POST /customobjects/v1/collections/{name}/objects` with a `filter` field in the request body.

## Workflow Share Settings

To make a collection accessible from workflows:

```yaml
collections:
  - name: incidents
    schema: collections/incidents/schema.json
    permissions: []
    workflow_integration:
      system_action: true           # true = app workflows only, false = also available as Fusion SOAR action
      tags:
        - Collection
```

| Setting | Behavior |
|---------|----------|
| `workflow_integration.system_action: true` | Available to app workflows only |
| `workflow_integration.system_action: false` | Available to both app workflows AND Falcon Fusion SOAR |

## RBAC and Direct API Access

Collections can be accessed directly via the CrowdStrike API (outside of functions) using custom roles with specific collection permissions. Include the `X-CS-APP-ID` header to identify your Foundry app. Foundry CLI credentials cannot access collections directly; use a separate API client with `Custom Storage` read/write scope.

## Common Pitfalls

- **Using `APIHarnessV2` (Uber class) for collection operations.** Use `CustomStorage` service class instead — the Foundry functions editor auto-detects OAuth scopes from service class imports but cannot parse Uber class `.command()` calls.
- **Using JSON Schema newer than draft 7.** Foundry only supports draft 7.
- **Missing indexes.** Fields used in queries must be marked with `x-cs-indexable: true` or listed in `x-cs-indexable-fields`. Max 10 per collection.
- **Invalid collection names.** Names must be 5-200 chars, start/end with letter or number, and contain only letters, numbers, and underscores.
- **Not configuring workflow share settings.** Set `workflow_integration.system_action: true` for app-only workflow access, or `false` to also expose collections as Falcon Fusion SOAR actions.
- **Trying to delete collections via CLI.** Collections can only be deleted from the Falcon Foundry UI.
- **Trying to manage objects via CLI.** Collection CRUD requires the CrowdStrike API or `foundry-js` SDK.

## Reading Guide

| Task | Reference |
|------|-----------|
| Migrations, testing, pagination, extended schemas, counter-rationalizations | [references/advanced-patterns.md](references/advanced-patterns.md) |

## Use Cases

For real-world implementation patterns, see:
- [collections.md](../../use-cases/collections.md) — CRUD operations, search, field types
- [lookup-table-enrichment.md](../../use-cases/lookup-table-enrichment.md) — 3rd-party data for automated enrichment

## Reference Implementations

- **[foundry-sample-collections-toolkit](https://github.com/CrowdStrike/foundry-sample-collections-toolkit)**: CSV import, bulk operations, pagination workflows, test data generation. See also [Getting Started with Falcon Foundry Collections](https://www.crowdstrike.com/tech-hub/ng-siem/getting-started-with-falcon-foundry-collections-your-guide-to-structured-data-storage-in-foundry-apps/).
