# Authentication Examples for API Integrations

Vendor-specific authentication configuration examples, all verified from production Foundry apps.

## API Key — Custom Header (VirusTotal)

Token sent via custom header (`x-apikey`), not the `Authorization` header:

```json
"securitySchemes": {
  "apiKey": {
    "name": "x-apikey",
    "type": "apiKey"
  }
}
```

## API Key — Authorization Header with Prefix (Okta)

Okta requires `Authorization: SSWS {token}`. Use `type: apiKey` with `name: Authorization`, `in: header`, and `bearerFormat` to specify the prefix:

```yaml
# CORRECT — Foundry prompts for token at install, sends Authorization: SSWS {token}
apiToken:
  type: apiKey
  name: Authorization
  in: header
  bearerFormat: SSWS
```

The `bearerFormat` field tells Foundry what prefix to prepend to the token value. The adapt script infers this from the scheme's description automatically (e.g., "SSWS {API Token}" → `bearerFormat: SSWS`).

## HTTP Bearer (Anomali ThreatStream)

Token sent as `Authorization: Bearer {token}`:

```json
"securitySchemes": {
  "http_bearer": {
    "bearerFormat": "apikey",
    "in": "header",
    "scheme": "bearer",
    "type": "http"
  }
}
```

## HTTP Basic with Custom Labels (Workday)

Basic auth with CrowdStrike extensions to customize the install UI field labels:

```json
"securitySchemes": {
  "http_basic": {
    "scheme": "basic",
    "type": "http",
    "x-cs-password-label": "clientSecret",
    "x-cs-username-label": "clientID"
  }
}
```

Use `x-cs-username-label` / `x-cs-password-label` on basic auth to customize field labels shown in the Falcon console install UI.

## OAuth 2.0 Client Credentials (SailPoint)

Client credentials flow with custom labels for client ID and secret:

```json
"securitySchemes": {
  "oauth2": {
    "flows": {
      "clientCredentials": {
        "scopes": {},
        "tokenUrl": "{host}/oauth/token"
      }
    },
    "type": "oauth2",
    "x-cs-client-id-label": "clientId",
    "x-cs-client-secret-label": "clientSecret"
  }
}
```

Use `x-cs-client-id-label` / `x-cs-client-secret-label` on oauth2 to customize field labels in the install UI.

## OAuth 2.0 Client Credentials for a Falcon API

When the host must be **one of a known set**, such as the Falcon API regions for an OAuth client-credentials integration that calls a Falcon API, use an `enum` of hosts (no `https://`) with a `default`. The console renders it as a dropdown, so a settings editor can't send the secret to another host. An `enum` variable without a `default` rendered a stray `[object Object]` entry:

```json
"servers": [{"url": "{host}", "variables": {"host": {"default": "api.crowdstrike.com", "enum": ["api.crowdstrike.com", "api.us-2.crowdstrike.com", "api.us-3.crowdstrike.com", "api.eu-1.crowdstrike.com"]}}}]
```

Pair it with the token URL `{host}/oauth2/token`. Auth can't be changed after the integration is created.

## Dual Auth (ServiceNow ITSM)

When a vendor spec defines multiple `securitySchemes` (e.g., `apiToken` + `oauth2`), Foundry defaults Auth type to `allOf`, requiring ALL auth methods at install time. Remove the unused scheme unless dual auth is intentional.

For ServiceNow ITSM, both basic and oauth2 are kept because users choose their preferred auth method at install time.

## Setting Top-Level Security

After configuring security schemes, set a top-level `security` field so all operations inherit auth by default:

```yaml
# Top-level -- all operations require this auth unless overridden
security:
  - apiToken: []

components:
  securitySchemes:
    apiToken:
      type: apiKey
      name: Authorization
      in: header
      bearerFormat: SSWS
```

## Notes

- Authentication configuration in API integrations is immutable after creation. To change auth settings, delete the integration and recreate it.
- Foundry supports `apiKey`, `http/bearer`, `http/basic`, and `oauth2/clientCredentials`. It does NOT support `authorizationCode` flow.
- Remove unsupported OAuth 2.0 flows (like `authorizationCode`) from vendor specs. Also remove per-operation `- oauth2:` security entries so only the kept scheme remains.
- The adapt script adds `bearerFormat` to `apiKey` schemes when it can infer the prefix from the description. If the description doesn't contain a recognizable prefix pattern, no `bearerFormat` is added.
