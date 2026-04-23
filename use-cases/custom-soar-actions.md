---
name: custom-soar-actions
description: Create custom Falcon Fusion SOAR actions from a third-party API integration and orchestrate data into LogScale
source: https://www.crowdstrike.com/tech-hub/ng-siem/create-custom-actions-for-soar-with-falcon-foundry/
skills: [foundry-api-integrations, foundry-workflows-development, foundry-functions-development]
capabilities: [api-integration, workflow, function]
---

## When to Use

User wants to integrate a third-party API (Okta, ServiceNow, Jira, etc.) as custom SOAR actions in Falcon Fusion SOAR, create scheduled or on-demand workflows that call external APIs, or ingest third-party data into LogScale.

## Pattern

### 1. Create the App and API Integration

1. Create a Foundry app (CLI or App Builder UI).
2. Add an API integration by importing an OpenAPI spec or creating operations manually.
3. Configure authentication (API key, OAuth, or Bearer token):
   - API key: specify parameter name, location (header/query), and prefix (e.g., `SSWS` for Okta).
4. Test each operation against the live API using a temporary configuration.
5. Fix response schemas: copy test response body > Response > Response body > Generate schema.
6. **Validate** immediately after adding the API integration (`foundry apps validate --no-prompt`).

### 2. Share Operations with Fusion SOAR

1. For each operation, go to Workflow Share settings.
2. Set display name, description, and tags (e.g., `Okta`).
3. Configure Advanced settings for autocomplete if the operation returns a list:
   - Array field: `root response`
   - ID field: `id`
   - Display field: `profile.email` (or other human-readable field)
4. Deploy and release the app so actions become visible in Fusion SOAR.

### 3. Create Workflows

**Scheduled workflow (data ingestion into LogScale):**
1. Fusion SOAR > Workflows > create from scratch > Scheduled trigger.
2. Add the shared API action (e.g., `listUsers`). Select credential profile.
3. Add a For Each loop over the response body (processing: sequential).
4. Inside the loop, add a "Write to log repo" action with custom JSON:

```json
{
  "event": {
    "kind": "UserState",
    "provider": "Okta"
  },
  "user": {
    "email": "${Email instance}",
    "first_name": "${FirstName instance}",
    "last_name": "${LastName instance}"
  }
}
```

1. Save, set status to On, and execute.

**On-demand workflow (user action):**
1. Create from scratch > On demand trigger.
2. Add action (e.g., `deactivateUser`). Autocomplete resolves IDs to display names.
3. Save and execute.

### 4. Verify in LogScale

Query results in Next-Gen SIEM > Advanced event search:
```
#repo = fusion
| event.provider = Okta
```

## Key Code

```bash
# CLI approach to create the app and API integration
foundry apps create --name "Okta Demo" --no-prompt --no-git
cd okta-demo
foundry api-integrations create --name "Okta" --spec okta-api.json --no-prompt

# Validate after API integration is added (catches spec issues in seconds)
foundry apps validate --no-prompt

# Deploy later after all capabilities are built
foundry apps deploy \
  --change-type Minor --change-log "Okta API integration" --no-prompt
```

## Gotchas

- **Actions not visible in Fusion SOAR**: The app must be released AND installed. Use Preview mode (`</>` icon) during development to see pre-release actions.
- **Response schema errors**: If you get a status error after testing an operation, the response schema is missing. Copy the response body and generate the schema.
- **Autocomplete "Array field" shows only `body`**: The response schema needs updating. Regenerate it from a real API response sample.
- **Authentication limitations**: Private JWT auth is not currently supported in Foundry for OAuth. Use API key auth as a workaround.
- **Rate limiting on scheduled workflows**: Turn off or delete scheduled workflows when finished testing. Hourly schedules trigger rate limit warnings from APIs like Okta within days.
- **Deploy vs Release separation**: Deploy saves a version for developers. Release publishes to App catalog for users. This isolation is intentional for team workflows.
- **Major releases require manual acceptance**: Users must accept major version updates in App catalog. Minor/patch releases auto-apply.
