---
name: ngsiem-query-export
description: Export Next-Gen SIEM query results to CSV using FoundryLogScale in functions or Event Query in workflows
source: https://www.crowdstrike.com/tech-hub/ng-siem/exporting-falcon-next-gen-siem-query-results-to-csv-with-falcon-foundry/
skills: [functions-development, workflows-development, collections-development]
capabilities: [function, workflow, collection, api-integration]
---

## When to Use

User needs to export Next-Gen SIEM (LogScale) query results — as CSV files, lookup tables for enrichment, collection records, or payloads to external APIs. The critical decision: use a function for programmatic control or a workflow for visual orchestration.

## Pattern

### Decision: Function vs Workflow

| Factor | Use Function | Use Workflow |
|--------|-------------|--------------|
| Output format | Custom CSV, JSON, transformed | CSV file or lookup table |
| Destination | Collections, API integrations, custom | Lookup files, downstream actions |
| Query complexity | Dynamic queries, multiple repos | Single Event Query action |
| Processing | Transform/filter before export | Direct pipe to next action |

### Function-Based (FoundryLogScale SDK)

1. **Import FoundryLogScale** from `falconpy` — requires `humio-auth-proxy:read` scope.
2. **Choose sync or async** based on expected result size.
3. **Convert to CSV** using Python's `csv.DictWriter` with `extrasaction='ignore'`.
4. **Clean up `/tmp` files** in a `finally` block — containers reuse `/tmp` across invocations.
5. **Send results** to lookup file, collection, or API integration.

### Workflow-Based (Event Query Action)

1. **Add Event Query action** with your LogScale query.
2. **Set "Output files only: false"** to preserve JSON results for downstream actions.
3. **Wire `file_csv` output** to Create Lookup File via `${query_action.file_csv}`.
4. **Or wire JSON results** to collection writes or API integration calls.

## Key Code

**Synchronous LogScale query (small results):**
```python
from falconpy import FoundryLogScale

def query_logscale_sync(query_string, repo="search-all", start="-24h", end="now"):
    logscale = FoundryLogScale()
    response = logscale.execute_dynamic(app_id="foundry-app",
                                        repositories=[repo],
                                        search_query=query_string,
                                        search_query_start=start,
                                        search_query_end=end,
                                        mode="sync")
    return response["body"]["results"]
```

**Asynchronous LogScale query (large results):**
```python
import time

def query_logscale_async(query_string, repo="search-all"):
    logscale = FoundryLogScale()

    # Start async job
    response = logscale.execute_dynamic(app_id="foundry-app",
                                        repositories=[repo],
                                        search_query=query_string,
                                        search_query_start="-7d",
                                        search_query_end="now",
                                        mode="async")
    job_id = response["body"]["job_id"]

    # Poll until complete
    while True:
        status = logscale.get_search_status(job_id=job_id)
        if status["body"].get("done"):
            break
        time.sleep(2)

    # Fetch results
    results = logscale.get_search_results(job_id=job_id)
    return results["body"]["events"]
```

**CSV conversion with field filtering:**
```python
import csv, io

def results_to_csv(results, fields=None):
    if not results:
        return ""

    if fields is None:
        fields = list(results[0].keys())

    output = io.StringIO()
    writer = csv.DictWriter(output, fieldnames=fields, extrasaction='ignore')
    writer.writeheader()
    writer.writerows(results)
    return output.getvalue()
```

**Upload as lookup file:**
```python
from falconpy import NGSIEM

def upload_lookup(csv_path, filename="export.csv", repo="search-all"):
    ngsiem = NGSIEM()
    try:
        response = ngsiem.upload_file(lookup_file=csv_path,
                                      repository=repo)
        return response["status_code"] == 200
    finally:
        import os
        os.remove(csv_path)  # Always clean up /tmp
```

**Store in collection:**
```python
from falconpy import CustomStorage


def _app_headers() -> dict:
    app_id = os.environ.get("APP_ID")
    if app_id:
        return {"X-CS-APP-ID": app_id}
    return {}


def store_results(results, collection_name):
    custom_storage = CustomStorage(ext_headers=_app_headers())
    for record in results:
        custom_storage.PutObject(body=record,
                                 collection_name=collection_name,
                                 object_key=record.get("id", str(hash(str(record)))))
```

**Workflow: Event Query → Lookup File (CEL expression):**
```yaml
actions:
  QueryEvents:
    id: event_query_action_id
    properties:
      query: "#event_simpleName=ProcessRollup2 | select(ComputerName, FileName)"
      start: "-24h"
      end: "now"
  CreateLookup:
    id: create_lookup_file_action_id
    properties:
      file_csv: ${data['QueryEvents.file_csv']}
      filename: "process_export.csv"
      repository: "search-all"
```

## Gotchas

- **`extrasaction='ignore'`** is critical for CSV conversion. LogScale results contain metadata fields not in your fieldnames list — without this, `DictWriter` raises `ValueError`.
- **Clean up `/tmp` in `finally` blocks.** Foundry function containers persist `/tmp` across invocations. Leaked files cause disk pressure and stale data.
- **Lookup file limits:** 10 MB max file size, 5 uploads per 30 seconds. For larger exports, split into multiple files or use collections instead.
- **`mode="sync"` vs `mode="async"`:** Sync blocks until results return (fast for <10K events). Async returns a job ID for polling (required for large/slow queries).
- **Scope requirements:** `humio-auth-proxy:read` for queries, `humio-auth-proxy:write` for writing events or uploading files. Add both to manifest permissions.
- **Workflow "Output files only":** If set to `true`, JSON result fields are empty — downstream actions can only use the CSV file. Set to `false` to preserve both.
- **Live enrichment after upload:** Use `| match(file="export.csv", field=ComputerName)` in LogScale queries to join lookup columns to matching events.
- **Collection writes are individual** — `PutObject` handles one record at a time. For bulk inserts, iterate. Consider batching in a function rather than doing one-per-workflow-step.
