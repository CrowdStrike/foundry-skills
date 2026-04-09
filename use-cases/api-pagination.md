---
name: api-pagination
description: Paginate through external API results using functions for small datasets or workflows for large/unknown datasets
source: https://www.crowdstrike.com/tech-hub/ng-siem/api-pagination-strategies-for-falcon-foundry-functions-and-workflows/
skills: [foundry-functions-development, foundry-workflows-development]
capabilities: [function, workflow]
---

## When to Use

User needs to fetch paginated data from an external API (threat intel feeds, CMDB, ITSM). The critical decision: use a function loop for <10K records or workflow-based pagination for larger/unknown datasets.

## Pattern

### Decision: Function vs Workflow

| Factor | Use Function | Use Workflow |
|--------|-------------|--------------|
| Data size | < 10,000 records | > 10,000 or unknown |
| API speed | Fast (< 1s/page) | Slow or rate-limited |
| Execution time | < 10 minutes total | Potentially hours/days |
| Reliability | Occasional failures OK | Must be bulletproof |

### Function-Based (Small Datasets)

1. **Create a function** that fetches one page and saves state to a collection.
2. **Loop inside the function** if all pages fit within the 15-minute timeout.
3. **Add a reset endpoint** for testing and recovery.
4. **Test locally first** -- iterate faster than deploy/release/install cycle.

### Workflow-Based (Large Datasets)

1. **Build function that processes ONE page**: accepts `next` token, returns `next` token.
2. **Create a workflow** with: CreateVariable -> Initial function call -> UpdateVariable -> Loop.
3. **Loop condition** must check BOTH null and "0": `next:!null+next:!'0'`
4. **Inside loop**: call function with `${WorkflowCustomVariable.next}`, then UpdateVariable.

### Recommended dev approach

Build the function first, test locally, then add workflow orchestration.

## Key Code

**Function accepting pagination token (workflow-compatible):**
```python
@FUNC.handler(method="POST", path="/ingest")
def on_post(request: Request, _config, logger: Logger) -> Response:
    next_token = request.body.get("next", None)
    limit = request.body.get("limit", 1000)

    if next_token:
        query_params = {"limit": limit, "offset": next_token}
    else:
        query_params = {"limit": limit, "offset": 0}

    data, meta = fetch_page(api_client, query_params, logger)
    process_data(data)

    response_body = {"total": len(data)}
    next_value = meta.get("next")
    if next_value:
        response_body["next"] = next_value  # omit when done!

    return Response(body=response_body, code=200)
```

**Workflow YAML pagination loop:**
```yaml
loops:
  Loop:
    for:
      condition: WorkflowCustomVariable.next:!null+WorkflowCustomVariable.next:!'0'
      max_iteration_count: 500
      max_execution_seconds: 7200
      sequential: true
    trigger:
      next: [FetchPage]
    actions:
      FetchPage:
        next: [UpdateNext]
        id: functions.my-func.Ingest
        properties:
          limit: 1000
          next: ${data['WorkflowCustomVariable.next']}
      UpdateNext:
        id: 6c6eab39063fa3b72d98c82af60deb8a
        class: UpdateVariable
        properties:
          WorkflowCustomVariable:
            next: ${data['FetchPage.FaaS.my-func.Ingest.next']}
```

**Exponential backoff with Retry-After support:**
```python
import random, time

def fetch_with_retry(api, params, logger, max_retries=5):
    for attempt in range(max_retries + 1):
        response = api.execute_command_proxy(...)

        if response["status_code"] == 429:
            if attempt < max_retries:
                retry_after = response.get("headers", {}).get("Retry-After")
                if retry_after:
                    delay = int(retry_after)
                else:
                    delay = 5 * (2 ** attempt) + random.uniform(0, 2)
                logger.warning(f"Rate limited, retry in {delay:.1f}s")
                time.sleep(delay)
                continue
            raise Exception("Rate limit exceeded after max retries")

        if response["status_code"] not in [200, 207]:
            raise Exception(f"API error: {response['status_code']}")

        return response
```

**State management with collections:**
```python
def save_pagination_state(key, limit, offset):
    api = APIHarnessV2()
    api.command("PutObject", body={"limit": limit, "offset": offset},
        collection_name="pagination_tracker", object_key=key)

def get_pagination_state(key):
    api = APIHarnessV2()
    try:
        result = api.command("GetObject",
            collection_name="pagination_tracker", object_key=key)
        if isinstance(result, bytes):
            data = json.loads(result.decode("utf-8"))
            return data.get("limit", -1), data.get("offset", -1)
    except Exception:
        return -1, -1
```

## Gotchas

- **The "0" gotcha**: When a function omits the `next` field, the workflow engine maps it to `"0"` (not null). Your loop condition MUST check both: `next:!null+next:!'0'`. Without both checks, the loop runs forever.
- **Omit `next` field when done** -- do not return `next: null`. Use Pythonic approach: only add the key if there is a next token.
- **Save state AFTER successful processing**, not before. Otherwise a failure loses data and the checkpoint advances past unprocessed records.
- **Function timeout is 15 minutes max**. If your dataset might exceed this, use workflow-based pagination from the start.
- **Workflow limits**: 100,000 iterations, 7-day execution window.
- **Add jitter to retries** to prevent thundering herd: `5 * (2 ** attempt) + random.uniform(0, 2)`.
- **FalconPy auto-renews tokens** during long workflows -- use it instead of raw HTTP when calling Falcon APIs.
- **Test workflow behavior locally** with a bash script that chains curl calls, extracting `next` from each response and passing it to the next call.
- **Six pagination patterns**: offset/limit, cursor, page-number, Link header (RFC 5988), search-after (Elasticsearch), timestamp-based. Identify which pattern the API uses before implementing.
