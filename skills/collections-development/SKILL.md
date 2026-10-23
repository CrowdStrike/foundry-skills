---
name: collections-development
description: Design JSON Schema collections and CRUD patterns for Falcon Foundry apps. TRIGGER when user asks to "create a collection", "define a JSON schema", "store data in Foundry", runs `foundry collections create`, or needs help with indexable fields, FQL queries, or collection access patterns. DO NOT TRIGGER for workflow YAML, function handlers, or UI components — use the appropriate sub-skill.
version: 1.6.0
updated: 2026-10-01
tags: [foundry, collections, json-schema, nosql]
author: CrowdStrike
license: MIT
compatibility: Claude Code >=1.0
metadata:
  category: data
---

# Foundry Collections Development

> **Part of a suite.** If `development-workflow` has not already run, and this is a new app or its first capability, load the `development-workflow` skill first — it owns the CLI prerequisite check, scaffolding order, and manifest coordination.

Falcon Foundry Collections are NoSQL document stores with JSON Schema validation. They provide persistent storage for app data with CRUD operations, FQL queries, and schema enforcement.

## Collection Naming Constraints

| Constraint | Rule |
|-----------|------|
| Length | 5-200 characters |
| Start/end | Must begin and end with a letter or number |
| Special characters | Only underscores (`_`) allowed — no hyphens, spaces, or other chars |
| Case | Case-sensitive |

## Collection Description Constraints

| Constraint | Rule |
|-----------|------|
| Length | 3-500 characters |
| Start | Must begin with an alphanumeric character |
| Allowed characters | Letters, numbers, spaces, dashes, periods, parentheses, and underscores only |
| Not allowed | Commas, colons, semicolons, quotes, slashes, or other special characters |

**Check the description against this table before running `collections create`.** The CLI accepts a comma (or any other disallowed character) in `--description` without complaint; the rejection only surfaces later, from `foundry apps validate` or deploy, by which time the collection is already in the manifest and has to be fixed by hand. Write the description with letters, numbers, spaces, dashes, periods, parentheses, and underscores only.

## Collection Limits

| Resource | Limit |
|----------|-------|
| Single object size | ~50 MB |
| Schema size | 256 KB |
| Object key length | 1-1,000 characters |
| Indexed fields per schema | 10 |
| Objects per collection | No enforced limit |
| Collections per app | No enforced limit |
| Search results per page | 500 max (default 50) |

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

## Exposing a Collection as an Agent Tool

Add `--agent-tools-expose` to let a Foundry AI agent read and write the collection:

```bash
foundry collections create --name "triage_notes" --schema /tmp/schema.json \
  --description "Agent triage notes" --agent-tools-expose --no-prompt
```

That writes one block onto the collection's manifest entry:

```yaml
collections:
    - name: triage_notes
      agent_tools_integration:
        exposed: true
```

Exposure is only half the wiring. The agent must also name each operation it may call in its own `tools` list, using `action:collections.<collection_name>.<Operation>`. Without the `action:` prefix, the deploy fails with a bare `500`:

```yaml
ai:
    agents:
        - name: Detection Triage Agent
          tools:
            - action:collections.triage_notes.CreateObject
            - action:collections.triage_notes.SearchObjects
```

Valid operations, exact casing required: `CreateObject`, `GetObject`, `DeleteObject`, `ListObjects`, `SearchObjects`.

A collection exposed but not listed in `tools` is unreachable by the agent, and vice versa — neither case produces an error, just an agent that silently cannot use the data. `agent_tools_integration` is independent of `workflow_integration`; a collection can be exposed to agents, to Fusion, to both, or to neither.

Agents can also use the generic collection, `action:mcp/gce/collections:collections:generic:<Operation>` — a scratch collection the platform creates per agent at runtime, needing no collection of your own. Use a named app collection when the data must outlive the agent or be readable by other capabilities. See `ai-agents-development`.

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

## CRUD Operations

Use a typed `foundry-js` `Collection` client from UI/TypeScript, and the `CustomStorage` service class (not the `APIHarnessV2` Uber class) from Python functions. **Full walkthroughs** — the typed TypeScript `IncidentCollection` client and the Python `CustomStorage` CRUD/search/paginate example with its key points — are in [references/advanced-patterns.md](references/advanced-patterns.md). Two behaviors that bite in both: a never-created key reads as a truthy not-found envelope on the JS side and a 404 on the Python side (gate on a real field, not truthiness), and FQL filters only work on fields marked `x-cs-indexable: true`.

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
- **Commas or other punctuation in `--description`.** `collections create` accepts them; `foundry apps validate` and deploy reject them. Stick to letters, numbers, spaces, dashes, periods, parentheses, and underscores.
- **Editing a schema file and redeploying does not change an existing collection.** Writes keep validating against the schema the collection was created with (observed: a new top-level field rejected as `additional properties not allowed` after the schema that declared it was deployed). Ship `"additionalProperties": true` at the top level if fields may be added later, and treat any breaking schema change as a new collection name.
- **Custom-storage collections are effectively immutable — decide schema + TTL at create time.** Once a collection is written via `custom_storage_object_key` (the standard app pattern: `collections.*.create` with `custom_storage_object_key`, and foundry-js `collection.write(key, obj)`), you can no longer add a `ttl` or tighten its schema (`additionalProperties: false`, a new `maxLength`, etc.). The deploy fails with `Invalid Collection - {"code":400,"message":"custom_storage_object_key is a reserved input property"}`. Confirmed by isolation — reverting the schema to its exact original and changing *only* `ttl` still failed, on every custom-storage-written collection in the diff: you can neither declare `custom_storage_object_key` in the schema (rejected as reserved) nor omit it (Foundry injects it during re-provision validation). Bake per-object expiry and strict validation into the INITIAL definition. Compounding trap: a failed collection deploy poisons the diff base — later plain deploys report `no deployable artifacts found` or keep replaying the error, and `--re-deploy` only retries the failed bundle. Recover with `git checkout` of the collection/manifest changes (the failed deploys never went live).
- **There is no in-place collection rename.** Foundry has no rename operation; changing a collection's `name` provisions a NEW empty collection and orphans every object written under the old name — unrecoverable, since collection data is UI-only readable. Rename a collection only if you can afford to lose its contents; for a brand/display rename, leave the internal collection names untouched. (This is also why a breaking schema change is handled as a new collection name — see the bullet above.)
- **A deleted collection name tombstones per `app_id`.** After CrowdStrike support deletes an app's collections, redeploying into the same `app_id` fails with `Invalid Collection - resource <app_id>:<name> existed previously, but was deleted`. Collection names are namespaced per `app_id`, and a previously-deleted name cannot be recreated in that same `app_id`. Escape: strip the `app_id` (and all other provisioned ids) from the manifest and cold-deploy a fresh `app_id` — the names are free in the new namespace.
- **Concurrent writers lose fields.** `PutObject` replaces the whole object, and there is no compare-and-set or version check. When two handlers can update the same key at once, read the object right before the write, merge your fields into it, and write it back. That narrows the window but doesn't close it. Collections can't give you mutual exclusion: a lock object would be written with the same `PutObject`, so taking the lock is its own race. When lost writes matter, send every update to the key through one writer, and make sure two runs of that writer can't overlap.
- **Not configuring workflow share settings.** Set `workflow_integration.system_action: true` for app-only workflow access, or `false` to also expose collections as Falcon Fusion SOAR actions.
- **Trying to delete collections via CLI.** Collections can only be deleted from the Falcon Foundry UI.
- **Trying to manage objects via CLI.** Collection CRUD requires the CrowdStrike API or `foundry-js` SDK.
- **Schema field names must match exactly.** If a field name in your write payload doesn't match the collection schema (e.g., writing `score` when the schema defines `severity`), the write fails and returns errors in the response body — but the SDK does not throw. Without checking `result.errors`, the failure is invisible. Always read the collection schema file before writing seed data; verify required fields, enum values, and exact field names.
- **Not checking write responses for errors.** The SDK does not throw on server-side validation failures. Always check `result?.errors?.length` after write operations — errors include specific messages like `"missing property 'severity'"` or `"value must be one of 'low', 'medium', 'high', 'critical'"`. Verify persistence with a follow-up read or list call.
- **Reading a never-created key returns a truthy NOT-FOUND envelope — not `null`, not a throw, not `{}`.** On the foundry-js side, `collection.get()`/`.read()` of a key that was never written resolves to a truthy-but-empty not-found envelope object. Two traps follow: `if (obj)` takes the "load existing" branch for a missing key (an empty-state gate that always thinks data exists — so the record's first write never fires), and spreading that envelope into a read-modify-write **poisons the payload** — `PutObject` returns 200 but the stored object is unreadable garbage. Gate on a real field the record must carry (`obj.run_id || obj.collected_at`), and sanitize a read before merging it into a write. Same bug as the Python 404 caveat above, surfacing on the JS side.

## Reading Guide

| Task | Reference |
|------|-----------|
| Migrations, testing, pagination, extended schemas, counter-rationalizations | [references/advanced-patterns.md](references/advanced-patterns.md) |

## Use Cases

For real-world implementation patterns, see:
- `use-cases/collections.md` — CRUD operations, search, field types
- `use-cases/lookup-table-enrichment.md` — 3rd-party data for automated enrichment

## Reference Implementations

- **[foundry-sample-collections-toolkit](https://github.com/CrowdStrike/foundry-sample-collections-toolkit)**: CSV import, bulk operations, pagination workflows, test data generation. See also [Getting Started with Falcon Foundry Collections](https://www.crowdstrike.com/tech-hub/ng-siem/getting-started-with-falcon-foundry-collections-your-guide-to-structured-data-storage-in-foundry-apps/).
