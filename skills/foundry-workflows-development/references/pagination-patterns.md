# Pagination Patterns Reference

> Parent skill: [foundry-workflows-development](../SKILL.md)

## Six Common Pagination Strategies

1. **Offset/limit** — increment offset by page size each iteration
2. **Cursor-based** — pass opaque next token between iterations
3. **Page number** — increment page counter
4. **Link header** — follow `next` URL from response headers
5. **search_after** — pass last record's sort key
6. **Timestamp-based** — advance time window each iteration

## Function vs. Workflow Pagination

| Approach | Best When |
|----------|-----------|
| **Function-based** | Complex data transformation needed between pages |
| **Workflow-based** | Orchestrating simple API calls with collection state persistence |

**Guidelines:**
- Store pagination state in a collection to survive function timeouts
- Implement exponential backoff with `Retry-After` header support for rate-limited APIs
- Use the "0" gotcha check (see main skill) for any pagination token returned from functions

## The "0" Gotcha in Pagination

When a function omits a field from its response, the workflow engine maps the missing variable to the string `"0"`, not `null`. A loop condition checking only `:!null` evaluates true (because `"0"` is not null) and continues forever.

**Fix:** Always check for both null and "0":

```
WorkflowCustomVariable.next:!null+WorkflowCustomVariable.next:!'0'
```

This applies to any pagination token, cursor, or "has more" indicator returned from functions.

## External References

- [API Pagination Strategies for Falcon Foundry Functions and Workflows](https://www.crowdstrike.com/tech-hub/ng-siem/api-pagination-strategies-for-falcon-foundry-functions-and-workflows/)
