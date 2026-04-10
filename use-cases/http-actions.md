---
name: http-actions
description: Call external REST APIs from workflows using HTTP Request actions with API key or OAuth 2.0 auth, no custom app required
source: https://www.crowdstrike.com/tech-hub/ng-siem/build-api-integrations-with-falcon-fusion-soar-http-actions/
skills: [foundry-api-integrations, foundry-workflows-development]
capabilities: [api-integration, workflow]
---

## When to Use

User wants to call an external API from a workflow without building a full Falcon Foundry app. HTTP Actions handle the vast majority of API integration needs. Only build a Foundry app when you need a custom UI or serverless functions for complex logic.

**Use HTTP Actions when:**
- Simple REST API call (GET, POST, PUT, DELETE)
- API key or OAuth 2.0 authentication
- Response handling with conditional branching
- Quick turnaround (minutes, not hours)

**Use a Foundry app instead when:**
- Custom UI or detection panel extensions
- Complex data transformation requiring code
- Reusable serverless functions
- Multiple tightly coupled API operations

## Pattern

1. **Choose the HTTP Action type**:
   - **Cloud HTTP Request**: External/internet APIs (Slack, VirusTotal, Microsoft Graph)
   - **CrowdStrike HTTP Request**: Falcon APIs (auto-auth via tenant context)
   - **On-Premises HTTP Request**: Internal APIs behind firewalls (via static host groups)

2. **Configure authentication** (create once, reuse across actions):
   - **API Key**: Header name + value (e.g., `Authorization: Bearer <key>`)
   - **OAuth 2.0**: Token URL + client ID + secret + scope (auto-refreshes tokens)
   - **CrowdStrike**: Automatic tenant context or dedicated API client

3. **Set up the request**: URL with `${variable}` injection, method, headers, query params, body.

4. **Test inline**: Replace variables with real values, click Test, review response.

5. **Generate schema**: Click Generate Schema from test response (required for downstream access).

6. **Add conditional branching** based on `${activity.HTTP.response_status_code}` (e.g., 200 vs 404).

7. **Reference response data** in later steps: `${activity_name.HTTP.body.data.field}`.

## Key Code

**OAuth 2.0 for Microsoft Graph:**
```
Token URL: https://login.microsoftonline.com/{tenant-id}/oauth2/v2.0/token
Scope: https://graph.microsoft.com/.default
Grant Type: Client Credentials
```
Entra ID setup: App registrations > New > API permissions > Application permissions > Grant admin consent > Create client secret.

**Variable injection in URL:**
```
https://graph.microsoft.com/v1.0/users/${userPrincipalName}
```
Variables resolve at workflow execution, not during testing. Use real values when testing.

**Query parameters (use the Query tab, not manual URL building):**
```
$select  = displayName,mail,jobTitle,department
$filter  = startswith(displayName,'${searchTerm}')
$top     = 10
```

**Conditional branching on status code:**
```
Condition 1: response_status_code == 200 -> proceed with data
Condition 2: response_status_code == 404 -> handle not found
Else: handle unexpected errors
```

**Charlotte AI summarization of API response:**
```
Action: Charlotte AI - LLM Completion
Model: Claude Latest
Temperature: 0.1
Prompt: Summarize the user account information for ${User Principal Name}...
  Response: ${Raw Response Body}
```

**CEL expressions for structured LLM output in emails:**
```
${cs.json.decode(data['CharlotteAI...completion']).full_name}
${cs.json.decode(data['CharlotteAI...completion']).account_enabled == 'true' ? 'ENABLED' : 'DISABLED'}
```

**On-demand trigger schema:**
```json
{
  "type": "object",
  "properties": {
    "userPrincipalName": {
      "type": "string",
      "format": "email",
      "title": "User Principal Name to Investigate"
    },
    "recipient": {
      "type": "string",
      "format": "email",
      "title": "Email to Notify"
    }
  },
  "required": ["userPrincipalName", "recipient"]
}
```

## Gotchas

- **Cannot change authentication after creation.** Double-check auth config before saving.
- **Variables do not resolve during testing.** Replace `${var}` with actual values to test, then restore variables before saving.
- **Response body max 10 MB** and must be a JSON object (not an array).
- **HTTP timeout is 30 seconds.** Optimize queries with `$select` and `$top` for slow APIs.
- **On-premises actions require static host groups** only (dynamic host groups not supported). Limit to 20 hosts.
- **CrowdStrike HTTP Requests**: Map API endpoint to scope using the section header in API docs (e.g., `/devices/...` needs `hosts` scope).
- **OAuth `.default` scope** grants all permissions configured in the app registration. Only enable the API permissions you actually need.
- **Bearer prefix**: If docs show `Authorization: Bearer <token>`, set header name to `Authorization` and value to `Bearer your_key` (include the word "Bearer" and space).
- **LLM output in emails**: Use a JSON schema in the Charlotte AI action to get structured output. Use `cs.json.decode()` CEL expressions to extract fields in Send Email actions.
- **Generate schema after testing** -- downstream workflow steps cannot reference response fields without a schema.
