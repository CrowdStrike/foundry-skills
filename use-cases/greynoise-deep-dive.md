---
name: greynoise-deep-dive
description: Build a multi-capability Foundry app that imports third-party threat intel into Falcon Next-Gen SIEM as a lookup file
source: https://www.crowdstrike.com/tech-hub/ng-siem/technical-deep-dive-with-greynoise-building-a-falcon-foundry-app-for-crowdstrike-falcon-next-gen-siem/
skills: [foundry-api-integrations, foundry-ui-development, foundry-functions-development, foundry-workflows-development]
capabilities: [api-integration, ui-page, function, workflow]
---

## When to Use

User wants to build a Foundry app that pulls data from an external API, transforms it into
a CSV lookup file, and uploads it to Falcon Next-Gen SIEM. Applies to any third-party threat
intel feed (GreyNoise, VirusTotal, AlienVault OTX, etc.) or bulk data import pattern.

## Pattern

1. **Define API integration** for the external service (GreyNoise, etc.) with necessary endpoints.
2. **Create a Python function** that:
   - Calls the external API to fetch indicator data
   - Processes results in batches (10K records per batch) to stay within memory limits
   - Writes only needed fields to a CSV temp file
   - Uploads the CSV via the FalconPy `NGSIEM.upload_file()` lookup API
3. **Increase function resource limits** in manifest for large data processing.
4. **Create a workflow** with a schedule trigger that invokes the function periodically.
5. **Add `humio-auth-proxy:write` scope** for lookup file upload permissions.
6. **Test locally** using Docker via `foundry functions run`, send curl requests to the container.

## Key Code

### Function imports and handler

```python
from crowdstrike.foundry.function import APIError, Function, Request, Response
from falconpy import NGSIEM
from greynoise.api import GreyNoise, APIConfig  # or any third-party SDK
import pandas as pd
import tempfile, os, csv, gc

func = Function.instance()

@func.handler(method="POST", path="/greynoise-ti-import-bulk")
def on_post(request: Request, config, logger) -> Response:
    logger.info("Starting NGSIEM CSV import process")
    # ... fetch, process, upload
```

### Batch processing to stay within memory limits

```python
batch_data = response["data"]
rows_to_write = []
for i, item in enumerate(batch_data):
    if processed_count >= max_indicator_count:
        break
    row = process_record(item, total_records + i + 1, logger)
    if row is not None:
        rows_to_write.append(row)
        processed_count += 1

if rows_to_write:
    writer.writerows(rows_to_write)

# Free memory after each batch
del batch_data, rows_to_write
gc.collect()
```

### File size guard (lookup upload limit is 50 MB)

```python
file_size = os.path.getsize(output_path)
logger.info(f"CSV file size: {file_size} bytes ({file_size / 1024 / 1024:.2f} MB)")
if file_size > 47_000_000:  # buffer below 50 MB limit
    logger.warning("File size > 47MB, stopping processing")
    break
```

### Upload lookup file via FalconPy

```python
ngsiem = NGSIEM()
response = ngsiem.upload_file(lookup_file=output_path, repository=repository)
logger.info(f"API response: {response}")
```

### Manifest: extended function resources and required scope

```yaml
functions:
  - name: greynoise-ti-import-to-ng-siem
    language: python
    max_exec_duration_seconds: 900   # max allowed runtime
    max_exec_memory_mb: 1024         # max allowed memory
    handlers:
      - name: greynoise-ti-import-bulk
        method: POST
        api_path: /greynoise-ti-import-bulk
        workflow_integration:
          disruptive: false
          system_action: false

auth:
  scopes:
    - humio-auth-proxy:write  # REQUIRED for lookup file upload
```

### Local testing via Docker

```bash
foundry functions run  # starts Docker container on random port

curl --request POST --url http://localhost:<port>/ \
  --header 'content-type: application/json' \
  --data '{
    "body": {
      "api_key": "KEY",
      "max_indicator_count": "1000000",
      "query": "last_seen:1d -classification:unknown",
      "repository": "search-all"
    },
    "method": "POST",
    "url": "/greynoise-ti-import-bulk"
  }'
```

## Gotchas

- **Lookup file upload limit is 50 MB**, not what the console displays. Add a file size guard at ~47 MB to leave buffer. This limit may increase in the future.
- **Memory is capped at 1024 MB**. Process API responses in batches (e.g., 10K records), write to CSV immediately, then delete the batch and run `gc.collect()`.
- **Max execution time is 900 seconds**. Budget time across API fetch, CSV write, and upload. Log progress to track where time is spent.
- **`humio-auth-proxy:write` scope is required** for `NGSIEM.upload_file()`. Missing this scope causes silent upload failures (function reports success, but no lookup file appears).
- **403 during local Docker testing is expected**: the container can't authenticate to upload. Verify CSV generation locally, test upload after deploy.
- **Workflow inputs must match function request schema**: Define function parameters (`api_key`, `query`, `repository`, `max_indicator_count`) in the manifest request schema and wire them as workflow inputs.
- **Reference app**: [CrowdStrike/foundry-sample-ngsiem-importer](https://github.com/CrowdStrike/foundry-sample-ngsiem-importer) provides the base lookup file upload pattern.
