# CEL Expressions Reference

> Parent skill: [workflows-development](../SKILL.md)

Falcon Fusion SOAR uses [Common Expression Language (CEL)](https://github.com/google/cel-spec/blob/master/doc/langdef.md) for data transformations, conditions, and field access. All variable references use `${data['...']}` expression syntax.

## Common Patterns

```yaml
# Check if results exist before accessing
"${size(data['eventQuery.results']) > 0 ? data['eventQuery.results'][0].field : \"N/A\"}"
# (len() is a null-safe alternative to size() — len(null) returns 0 instead of erroring)

# Null-safe field access — traditional pattern
"${data['action.field'] != null ? data['action.field'] : \"default\"}"

# Null-safe field access — optional pattern (preferred, avoids verbose null checks)
"${data[?'action.field'].orValue(\"default\")}"

# Fallback chain (like ?? coalescing — tries each key, returns first that exists)
"${data[?'primary'].or(data[?'fallback']).orValue(\"none\")}"

# Safe list exists-and-non-empty check
"${len(data[?'Key'].orValue([])) > 0}"

# Array element access (index goes INSIDE the ${...}, not after it)
"${data['action.API_Integration.Custom_Name.op.body'][0]}"

# Lookup table (map literal needs its own braces inside ${...})
"${ {'1': 'Low', '2': 'Medium', '3': 'High', '4': 'Critical'}[string(data['severity'])] }"
```

## `has()` vs `!= null` — know the difference

- `data['key'] != null` — checks if a **data store key** has a value. Use for trigger parameters and action outputs.
- `has(obj.field)` — checks if a **field exists on a retrieved object**. Only works *after* you've retrieved an object from the data store (e.g., `has(data['WorkflowCustomVariable'].offset)` works because CEL first retrieves `WorkflowCustomVariable` then checks `.offset`). Do NOT use `has(data['key'])` directly on the data store — this fails with `Q0910: invalid argument to has() macro`.
- `data[?'key'].orValue(default)` — the cleanest approach. Uses CEL optionals to safely handle missing keys without verbose null checks.

## CrowdStrike CEL Extensions

CrowdStrike provides [custom CEL extensions](https://docs.crowdstrike.com/r/k223d842) including `cs.json.valid()`, `cs.json.decode()`, `cs.ip.valid()`, `cs.timestamp.now()`, and `cs.timestamp.parse()`. For complex transformations, the **Data Transformation Agent** (requires Charlotte AI) generates CEL expressions from plain language descriptions.

For schemaless event queries and dynamic data handling patterns, see [Falcon Fusion SOAR Event Queries: When and How to Go Schemaless](https://www.crowdstrike.com/tech-hub/ng-siem/falcon-fusion-soar-event-queries-when-and-how-to-go-schemaless/).
