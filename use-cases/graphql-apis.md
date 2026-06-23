---
name: graphql-apis
description: Integrate GraphQL APIs (Falcon Identity Protection, GitHub, Snyk) into Foundry apps using FalconPy or HTTP POST
source: https://www.crowdstrike.com/tech-hub/ng-siem/working-with-graphql-apis-in-falcon-foundry/
skills: [functions-development, functions-falcon-api]
capabilities: [function]
---

## When to Use

User wants to call a GraphQL API from a Foundry function — either a Falcon platform GraphQL endpoint (Identity Protection, Threat Graph) via FalconPy, or a third-party GraphQL API (GitHub, Snyk, Hasura) via HTTP POST. Also applies when the user asks about queries with fragments, variables, or nested response extraction.

## Pattern

### Falcon GraphQL APIs (FalconPy)

FalconPy service classes handle authentication automatically inside Foundry functions (zero-arg constructor):

```python
from falconpy import IdentityProtection

def handler(request, config):
    idp = IdentityProtection()

    query = """
    {
        entities(types: ["user"], first: 10, sortKey: RISK_SCORE, sortOrder: DESCENDING) {
            nodes {
                primaryDisplayName
                riskScore
                riskFactors { type severity }
            }
        }
    }
    """

    response = idp.graphql(query=query)
    return {"body": response["body"]["resources"]}
```

**Auth scopes needed:** Add `idp-graph:read` (or the relevant scope for the service) to the manifest.

### Third-Party GraphQL APIs (HTTP POST)

For external GraphQL endpoints, use environment variables for credentials and standard HTTP POST:

```python
import os
import requests

def handler(request, config):
    token = os.environ.get("GITHUB_TOKEN")
    query = """
    query($owner: String!, $name: String!) {
        repository(owner: $owner, name: $name) {
            vulnerabilityAlerts(first: 10) {
                nodes { securityVulnerability { severity package { name } } }
            }
        }
    }
    """
    variables = {"owner": "CrowdStrike", "name": "foundry-skills"}

    response = requests.post(
        "https://api.github.com/graphql",
        json={"query": query, "variables": variables},
        headers={"Authorization": f"Bearer {token}"}
    )
    return {"body": response.json()}
```

**Security warning:** Environment variables are visible to anyone with App Developer privileges who exports the app. For production use, prefer API integrations (platform-managed credentials) over raw env vars. See the credential management decision table in the functions skill.

### Key Differences from REST

| Aspect | REST | GraphQL |
|--------|------|---------|
| Request | GET/POST to different endpoints | POST to single endpoint with query body |
| Response shape | Fixed by the endpoint | Client specifies exactly what fields to return |
| Auth in Foundry | API integration (preferred) or env vars | FalconPy (Falcon APIs) or env vars (third-party) |
| Pagination | Offset/cursor in query params | Cursor in query variables (`after`, `first`) |

## Sample App

[foundry-sample-idp-notifications](https://github.com/CrowdStrike/foundry-sample-idp-notifications) — Queries Identity Protection GraphQL for risky users and timeline events, combines with REST methods from the same FalconPy service class.
