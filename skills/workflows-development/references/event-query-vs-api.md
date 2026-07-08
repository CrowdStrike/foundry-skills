# Event Query vs. Source-of-Truth API

Deciding how a workflow should read Falcon alert, detection, or incident data. The rule turns
on **whether the workflow already holds the object**, not on the data type.

## The distinction: population vs. enrich

**Enriching an object the workflow already holds** → Event Query action (`Inline.QueryEvent`).

When a workflow is triggered on a detection (or otherwise already has its ID), pulling more
fields about *that* object is what the Event Query action is for. Query by the ID you already
have and go schemaless, because detection field shapes vary by type:

```
Ngsiem.detection.id = ?detectID
```

This is common, well-supported, and endorsed by the CrowdStrike blog
[Falcon Fusion SOAR Event Queries: When and How to Go Schemaless](https://www.crowdstrike.com/tech-hub/ng-siem/falcon-fusion-soar-event-queries-when-and-how-to-go-schemaless/),
whose worked example is exactly this detection-enrichment case. **Do not steer this toward a
function.**

**Fetching a population the workflow does NOT already have** → source-of-truth API.

Requests like "summarize all high-severity alerts from the last 24 hours" or "list open
detections across products" ask for a set of objects the workflow hasn't been handed. Whether
that population even lives in NG-SIEM is connector-dependent, so an Event Query can silently
return nothing. Go to the source of truth instead (see ordering below).

**Historical / aggregate telemetry** (patterns over time, counts by vendor, trend analysis) →
Event Query is fine, subject to the same connector caveat about what's ingested.

## Source-of-truth ordering (for the population case)

When you do need to fetch a population, prefer in order:

1. **A native platform action**, if one exists — no app, no code. Examples:
   - CrowdStrike Cases → **Search Cases** (`filter: detection_ids:'<id>'`)
   - Hosts, Incidents, and other first-party Fusion SOAR actions
2. **A FalconPy `Alerts`/`Detects` function** — only when no native action covers the need.
   Requires the app to declare the matching OAuth scope (e.g. `alerts:read`) and wire the
   function into the workflow. See [../../functions-falcon-api/SKILL.md](../../functions-falcon-api/SKILL.md).

## Verified FQL filter (function path)

When the function path is the right one, `query_alerts_v2` accepts an FQL `filter`. Verified
against the live Alerts API:

```python
filter="severity_name:'High'+created_timestamp:>'now-24h'"
```

Use `severity_name` (a string field: `'High'`, `'Critical'`), not the numeric `severity`
field — they are different scales.
