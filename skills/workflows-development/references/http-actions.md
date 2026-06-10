# HTTP Actions Reference

> Parent skill: [workflows-development](../SKILL.md)

HTTP Actions let a Fusion SOAR workflow call a REST API directly, without building a Foundry app or API integration. They are the fastest path for straightforward API calls — threat intel enrichment, ticketing, notifications, internal lookups.

## HTTP Actions vs API Integrations — which to use

| | HTTP Action (`Inline.HTTPRequest`) | API Integration (Foundry app) |
|---|---|---|
| **Setup** | Configured in the Falcon console, used inline in a workflow | OpenAPI spec + manifest in a Foundry app |
| **Best for** | Simple, one-off API calls | Reusable operations, complex logic, a custom UI |
| **Code** | None | Function code and/or OpenAPI authoring |
| **Reuse** | Per-workflow | Shared across workflows and functions |

Choose an HTTP Action when the workflow just needs to hit an endpoint and use the response. Choose an API integration when you also need serverless functions, a UI, or the same operation reused across many workflows.

## The three HTTP Action types

| Type | Use case | Network |
|------|----------|---------|
| **Cloud HTTP Request** | External/public APIs (VirusTotal, Slack, PagerDuty, HaveIBeenPwned) | Public internet from the Fusion cloud |
| **CrowdStrike HTTP Request** | Falcon platform APIs | CrowdStrike endpoints (tenant context or API key) |
| **On-Premises HTTP Request** | Internal APIs behind a firewall | Routed through a static host group |

## Important: credentials are configured in the console

An HTTP Action references a credential configuration that must already exist in the Falcon console (Fusion SOAR → configurations). In the exported workflow YAML this shows up as:

```yaml
authentication_option: UseExisting
config_id: 9c7d10295f6e4370afb7d91fc00cb4ca   # CID-specific — created in console
config_name: Microsoft
definition_id: 662c4828b3804ad287acc7fc3cd9895b
```

`config_id` and `definition_id` are assigned by the platform when you create the configuration in the console. You can author the workflow YAML that *uses* an HTTP Action, but the credential configuration it points to must be created in the console first. The action itself is also typically built in the console's workflow editor — the YAML below is what the export looks like, useful for understanding the structure and for review.

## Authentication patterns

### API key in a header

From a VirusTotal Cloud HTTP Request — the API key is stored in the console config; the action declares where to inject it:

```yaml
CloudHTTPRequest:
    id: 1ba474f407d9228fc8fa02cdce8ae8ef
    class: Inline.HTTPRequest
    name: Cloud HTTP Request
    properties:
        api_key_header_label: x-apikey
        api_key_location: Header
        authentication_option: UseExisting
        config_id: f34c6df51f464b41aa2c07dc9bd82062
        config_name: VirusTotal
        definition_id: 7227ab386bd646c18b27716e8fff8d26
        http_transaction:
            request_http_method: GET
            request_url: https://www.virustotal.com/api/v3/ip_addresses/8.8.8.8
            request_content_type: NONE
            request_headers: {}
            request_query: {}
    version_constraint: ~1
```

To make the IP dynamic, define it as a trigger parameter and inject it into the URL with `${param}` — see the OAuth example below, which defines `userPrincipalName` on the trigger and injects it into `request_url`.

### OAuth 2.0 client credentials

From a Microsoft Graph Cloud HTTP Request — the token URL and scopes are declared; Fusion handles token refresh. The trigger defines `userPrincipalName`, which the action injects into the URL with `${userPrincipalName}`:

```yaml
trigger:
    next:
        - CloudHTTPRequest
    name: On demand
    parameters:
        properties:
            userPrincipalName:
                type: string
                title: User Principal Name to Investigate
                format: email
        required:
            - userPrincipalName
        type: object
    type: On demand
actions:
    CloudHTTPRequest:
        id: 1ba474f407d9228fc8fa02cdce8ae8ef
        class: Inline.HTTPRequest
        name: Cloud HTTP Request
        properties:
            authentication_option: UseExisting
            config_id: 9c7d10295f6e4370afb7d91fc00cb4ca
            config_name: Microsoft
            definition_id: 662c4828b3804ad287acc7fc3cd9895b
            http_transaction:
                request_http_method: GET
                request_url: https://graph.microsoft.com/v1.0/users/${userPrincipalName}
                request_query:
                    c373ed43-231d-4141-ba4e-c0214b9587bb:
                        name: $select
                        value: displayName,mail,jobTitle,department,accountEnabled,userPrincipalName,id
            oauth_scopes:
                - https://graph.microsoft.com/.default
            oauth_token_url: https://login.microsoftonline.com/{tenant}/oauth2/v2.0/token
        version_constraint: ~1
```

> **OAuth limitation:** Custom OAuth scopes are not fully supported. For APIs that need custom scopes (some Microsoft Graph configurations), use API key authentication as a fallback.

## Status-code conditional routing

HTTP Actions expose `response_status_code`, which you branch on to handle success vs. not-found vs. error. This is the most common HTTP Action pattern — act on a 200, handle a 404 differently.

```yaml
conditions:
    response_status_code_is_equal_to_200:
        next:
            - CharlotteAILLMCompletion
        expression: CloudHTTPRequest.response_status_code:200
        display:
            - Response Status Code is equal to 200
        else_if: response_status_code_is_equal_to_404
    response_status_code_is_equal_to_404:
        next:
            - SendEmailNotFound
        expression: CloudHTTPRequest.response_status_code:404
        display:
            - Response Status Code is equal to 404
```

Downstream actions reference the HTTP response body with `${<action_name>.raw_response_body}` (the full JSON string — e.g., `${CloudHTTPRequest.raw_response_body}`, useful for passing to Charlotte AI to summarize). For status-code branching, conditions use the FQL form `<action_name>.response_status_code:200` (see the example above).

In condition `expression:` fields, use the FQL form without `${}` — e.g., `CloudHTTPRequest.response_status_code:200` (see above).

## Variable injection

Inject trigger parameters and prior outputs into the URL, query, headers, and body with `${variable}`:

- URL: `https://api.example.com/users/${userPrincipalName}`
- Trigger parameters prompt at execution time (not during the Test step in the console)

## Worked pattern: enrich + branch + notify

A complete Cloud HTTP Request workflow (e.g., breach check, IP reputation) typically chains:

1. **On-demand trigger** with input parameters (e.g., an email or IP, plus a notify-to address)
2. **Cloud HTTP Request** to the external API
3. **Condition** on `response_status_code` (200 → enrich path, 404 → clean path)
4. **Charlotte AI LLM Completion** (optional) to summarize the raw response into structured JSON
5. **Send email** actions on each branch with the result

See the Microsoft Graph and VirusTotal examples above for the action-level structure. Reference: [Build API Integrations with Fusion SOAR HTTP Actions](https://www.crowdstrike.com/tech-hub/ng-siem/build-api-integrations-with-falcon-fusion-soar-http-actions/).
