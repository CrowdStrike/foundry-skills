---
name: schemaless-queries
description: Disable schema validation on Falcon Fusion SOAR Event Queries to handle dynamic or variable response structures
source: https://www.crowdstrike.com/tech-hub/ng-siem/falcon-fusion-soar-event-queries-when-and-how-to-go-schemaless/
skills: [foundry-workflows-development]
capabilities: [workflow]
---

## When to Use

User is building a workflow with an Event Query action that fails due to schema validation
errors because query results have variable fields across runs. Common triggers: detection
enrichment queries, dynamic aggregations, conditional fields across event types.

## Pattern

1. **Identify the problem**: Workflow fails with "Schema validation failed: unexpected field" or silently drops fields not in the generated schema.
2. **Evaluate if schemaless is appropriate**: Use when queries return variable structures (detection enrichment, dynamic aggregations, conditional fields). Keep schema validation for predictable, consistent queries.
3. **Disable schema validation**: In the Event Query action, uncheck **Automatically generate schema and enforce schema validation**.
4. **Handle variable data with CEL expressions**: Use null checks, `size()` guards, and ternary operators for safe field access.
5. **(Optional) Normalize data**: Use a Create Variable action after the query to map variable fields into a consistent structure for downstream actions.
6. **(Optional) Use Charlotte AI**: Pass `data['eventQuery.raw_results']` to a Charlotte AI action for flexible summarization of variable data.

## Key Code

### CEL: Safe field access with null check

```
${size(data['eventQuery.results']) > 0
  && data['eventQuery.results'][0].customField != null
  ? data['eventQuery.results'][0].customField
  : "N/A"}
```

### CEL: Safe array access

```
${size(data['eventQuery.results']) > 0
  ? data['eventQuery.results'][0].fieldName
  : "No results"}
```

### CEL: Normalize schemaless data into consistent structure

Use a **Create Variable** action with these expressions:

```
{
  "detectionId": ${data['query.results'][0].detection.id},
  "severity": ${data['query.results'][0].severity != null
    ? data['query.results'][0].severity : "unknown"},
  "hostname": ${data['query.results'][0].device != null
    && data['query.results'][0].device.hostname != null
    ? data['query.results'][0].device.hostname : "N/A"},
  "description": ${data['query.results'][0].description != null
    ? data['query.results'][0].description : "No description available"}
}
```

### Charlotte AI prompt for variable detection data

```
Analyze this Falcon Next-Gen SIEM detection and provide a security summary:

${data['eventQuery.raw_results']}

Include:
- Detection type and severity
- Key indicators present in the data
- Recommended investigation steps
```

### CrowdStrike CEL extensions for validation

```
cs.json.valid(someString)     // validate JSON string
cs.json.decode(someString)    // parse JSON string
cs.ip.valid(someString)       // validate IP address
```

## Gotchas

- **CEL data path naming**: The action name in data paths has spaces removed. An action named "Event Query" becomes `data['EventQuery.results']`. Use the **Workflow data** panel to copy exact paths.
- **No `??` null coalescing in CEL**: Use ternary expressions (`condition ? value : default`) instead. This is a common mistake when coming from other languages.
- **Without schema, only `results` is recognized at top level**: Standard CEL handles the rest -- `[0]` for array access, `.fieldName` for properties.
- **Always check array length first**: Use `size(data['eventQuery.results']) > 0` before accessing `[0]`. Empty results with direct access will fail the workflow.
- **Nested null checks must be chained**: To safely access `device.hostname`, check `device != null && device.hostname != null`. A single null check on the leaf field is not sufficient if the parent object is null.
- **Hybrid approach is best practice**: Use schemaless query for flexibility at the source, then normalize into a typed structure with a Create Variable action before passing to downstream actions.
- **Test with diverse data**: Run the workflow against multiple detection types and event structures. Don't just test the happy path where all fields exist.
- **Default schemas don't require all fields**: Before disabling schema entirely, check if simply removing `required` fields from the generated schema solves your problem. See the [customizing event query I/O docs](https://docs.crowdstrike.com/r/u3794cfd).
- **Data Transformation Agent**: If Charlotte AI is available, it generates CEL expressions from plain-language descriptions and explains the evaluation logic.
