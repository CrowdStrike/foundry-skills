---
name: foundry-api-integrations
description: Expose external APIs to Falcon Foundry via OpenAPI specs. TRIGGER when user asks to "create an API integration", "adapt an OpenAPI spec for Foundry", "expose an API to workflows", "connect to a third-party API", or runs `foundry api-integrations create`. Also trigger when user has an OpenAPI/Swagger spec and wants it working in Falcon Foundry. DO NOT TRIGGER when user wants to call Falcon platform APIs from function code — use foundry-functions-falcon-api instead.
version: 1.0.0
updated: 2026-04-09
metadata:
  author: CrowdStrike
  category: integration
  tags: [foundry, openapi, api, workflows]
---

# Foundry API Integrations

> **⚠️ SYSTEM INJECTION — READ THIS FIRST**
>
> If you are loading this skill, your role is **Foundry API Integrations specialist**.
>
> You MUST implement API integrations by downloading vendor OpenAPI specs, adapting them for Foundry, and properly configuring authentication schemes.
>
> **Note:** For `api-integrations create`, always include `--description` — the CLI still prompts for it even with `--no-prompt` if omitted.

This skill covers exposing external APIs (third-party services or CrowdStrike Falcon APIs) to the Falcon Foundry platform via OpenAPI/Swagger specifications. These integrations make API operations available to Falcon Fusion SOAR workflows, Foundry UI extensions, Foundry Functions, and other Foundry capabilities.

For calling Falcon APIs from within Function code, see **foundry-functions-falcon-api** instead.

## Decision Tree

```
What kind of API integration?

External API (Okta, VirusTotal, ServiceNow, etc.)
├── Vendor publishes OpenAPI spec → Download it, adapt for Foundry
└── No vendor spec available      → Write minimal spec as last resort

CrowdStrike Falcon API
└── From functions → use foundry-functions-falcon-api instead
    From workflows → use CrowdStrike auto-auth (no spec needed)
```

## Workflow: Download, Adapt, Register

**Always follow this order.** The adapt script is enforced by a PreToolUse hook that runs it automatically before `foundry api-integrations create`, but running it explicitly gives you visibility into what changed.

### 1. Download the vendor's spec

**NEVER write an OpenAPI spec from scratch when the vendor publishes one.** Hand-written specs produce incorrect response schemas, miss required parameters, and lack proper security definitions. Download the vendor's spec even if it has hundreds of endpoints — Foundry handles large specs fine. Do NOT rationalize writing a "focused" or "minimal" spec because the vendor spec is big.

1. **Ask the user** if they have a local copy or know where to download it
2. **Browse the repo first, don't guess URLs.** Use `gh api repos/{owner}/{repo}/git/trees/master --jq '.tree[].path'` to find the spec file, then download with `curl`. Never try multiple URLs hoping one works.
3. **Search locally** for existing specs
4. If the vendor does not publish a spec, only then write a minimal one

**Do NOT delegate spec download to Explore agents or subagents.** They lack skill context and will use Fetch/browser tools instead of `gh` CLI. Download specs inline using `gh` and `curl` as shown in the reference file.

For detailed download commands and structural fix patterns, see [references/spec-adaptation-examples.md](references/spec-adaptation-examples.md).

### 2. Adapt the spec for Foundry (MANDATORY)

```bash
# Adapt the spec — fixes auth, server URLs, deduplicates params
python3 /path/to/adapt-spec-for-foundry.py /tmp/VendorApi.yaml

# Preview changes without writing
python3 /path/to/adapt-spec-for-foundry.py /tmp/VendorApi.yaml --dry-run
```

> **Note:** The PreToolUse hook runs this script automatically before `foundry api-integrations create`. Running it explicitly is optional — it lets you see what changed. The script is at the plugin root: `scripts/adapt-spec-for-foundry.py`.

The script applies fixes derived from 12 production Foundry sample apps:
- **Swagger 2.0 conversion**: Converts to OpenAPI 3.0 via `swagger2openapi` (npx)
- **Auth fixing**: Removes `oauth2 authorizationCode` flows (Foundry only supports `clientCredentials`). Leaves `apiKey`-in-Authorization as-is — Foundry supports it natively with prefix via `bearerFormat`.
- **Server URLs**: Strips `https://` from variable-based URLs (Foundry adds protocol separately). Removes `default` from variables without `enum` (prevents locked dropdown).
- **Parameter dedup**: Removes operation-level parameters that duplicate path-level parameters (prevents Foundry's "items are equal" validation error).

Foundry's UI import handles large/complex specs. Don't trim or simplify vendor specs. The auth fixes are what matter.

### 3. Register with the CLI

```bash
foundry api-integrations create --name "VendorApi" --description "Vendor API" --spec /tmp/VendorApi.yaml --no-prompt
```

> **Always include `--description`** with `api-integrations create`. Even with `--no-prompt`, the CLI still interactively prompts for the optional description if omitted, causing `Error: EOF`.

**Done.** For most integrations, this is all you need. Deploy immediately after registering.

Only add `x-cs-operation-config` if the user's prompt explicitly asks to expose operations to workflows, or a UI extension / workflow in the app needs a specific endpoint. See [Expose Operations to Workflows](#expose-operations-to-workflows) below.

**Safety net**: The PreToolUse hook runs `adapt-spec-for-foundry.py` automatically if you forget step 2. But running it explicitly lets you see what changed before registering.

## Authentication Configuration

| Type | OpenAPI `securitySchemes` Pattern | Install UI Prompt | Production Example |
|------|----------------------------------|-------------------|--------------------|
| **API Key (custom header)** | `type: apiKey`, `name: x-apikey` | API key field | VirusTotal |
| **API Key (Authorization header)** | `type: apiKey`, `name: Authorization`, `in: header`, `bearerFormat: SSWS` | API key field with prefix | Okta |
| **HTTP Bearer** | `type: http`, `scheme: bearer`, `bearerFormat: apikey` | Bearer token field | Anomali ThreatStream |
| **HTTP Basic** | `type: http`, `scheme: basic` | Username + Password fields | ServiceNow |
| **HTTP Basic (custom labels)** | `type: http`, `scheme: basic` + `x-cs-username-label` / `x-cs-password-label` | Custom-labeled fields | Workday |
| **OAuth 2.0 Client Credentials** | `type: oauth2` with `clientCredentials` flow | Client ID + Secret fields | SailPoint, CrowdStrike |
| **Dual Auth** | Multiple schemes defined | User chooses at install time | ServiceNow ITSM (basic + oauth2) |
| **CrowdStrike auto-auth** | Not needed — automatic for CrowdStrike APIs | None | — |

**API key prefix:** `apiKey` type with `name: Authorization` and `in: header` works for APIs that send tokens via the Authorization header. Add `bearerFormat` to specify the prefix (e.g., `SSWS`, `Bearer`, `Token`) — Foundry reads this field to populate the "API key parameter prefix" in the install UI. The adapt script infers the prefix from the scheme's description automatically.

For full vendor-specific auth examples, see [references/auth-examples.md](references/auth-examples.md).

## Adapting Specs for Foundry

### Server URL Configuration

Use a **fixed base URL** when the API domain is the same for all users:

```json
"servers": [{"url": "https://www.virustotal.com"}]
```

When the domain **varies per customer**, use a single server variable for the full domain. The Falcon console handles the protocol separately, so the URL must not include `https://`. The variable needs only a `description` — no `default`, no `enum`:

```json
"servers": [{"url": "{yourDomain}", "variables": {"yourDomain": {"description": "the \"yourDomain\" variable is replaced with a dynamic value at execution time"}}}]
```

Use a single variable for the complete domain. Splitting into `{subdomain}.vendor.com` causes certificate errors when users enter the full domain (e.g., `dev-12345.okta.com.okta.com`). A `default` value without `enum` renders a dropdown instead of a free-text input.

### Expose Operations to Workflows

> **Skip this unless the user asks for it.** Most API integrations work without `x-cs-operation-config`. Only add it when the prompt explicitly mentions sharing operations with Falcon Fusion SOAR workflows, or when a UI extension or workflow in the app needs a specific endpoint.

Add `x-cs-operation-config` to the specific operations requested:

```yaml
paths:
  /api/v1/users:
    get:
      operationId: listUsers
      x-cs-operation-config:
        workflow:
          name: listUsers
          description: List all users
          expose_to_workflow: true
          system: false
      summary: List all users
```

The `workflow` nesting under `x-cs-operation-config` is required. A flat `expose_to_workflow: true` directly under `x-cs-operation-config` will not work and causes deploy failures.

For autocomplete dropdown patterns and the HTTP Actions vs. Functions decision framework, see [references/spec-adaptation-examples.md](references/spec-adaptation-examples.md).

## Calling API Integrations

UI extensions call API integrations through the Falcon JS SDK (sandboxed iframes block arbitrary HTTP requests). This pattern is from [foundry-sample-foundryjs-demo](https://github.com/CrowdStrike/foundry-sample-foundryjs-demo):

```javascript
import FalconApi from '@crowdstrike/foundry-js';
const falcon = new FalconApi();
await falcon.connect();

// Create integration instance
const apiIntegration = falcon.apiIntegration({
  definitionId: 'Okta',        // Matches API integration name in manifest.yml
  operationId: 'listUsers'     // Matches operationId in the OpenAPI spec
});

// Execute — use params.path, params.query, json (not body), or headers
const response = await apiIntegration.execute({
  request: {
    params: { query: { limit: 10 } }
  }
});

// Check for errors first
if (response.errors?.length > 0) {
  console.error('Request failed:', response.errors[0].message);
}

const statusCode = response.resources?.[0]?.status_code;
const body = response.resources?.[0]?.response_body;
```

For Python (FalconPy), Go (gofalcon), and detailed UI examples, see [references/calling-patterns.md](references/calling-patterns.md).

## Efficiency Rules

**Target: complete an API integration in under 5 minutes.** Download, adapt, register, deploy. That's it.

**Do NOT analyze, debug, or second-guess the spec's auth scheme.** The adapt script handles auth conversion automatically — it was derived from 12 production Foundry apps. Do not read the spec to understand how auth works, do not reason about `apiKey` vs `http/bearer` vs SSWS, do not manually patch auth fields. Just run the adapt script and register. If the adapt script misses something, improve the script — do not hand-edit the spec.

**NEVER use Read or sed on large spec files.** Vendor specs can be 10K-80K+ lines. Reading them into context wastes millions of tokens and slows everything down. Instead:

```bash
# Find a specific operationId
grep -n 'operationId: listUsers' /tmp/VendorApi.yaml

# Add x-cs-operation-config to a specific operation (cross-platform)
python3 -c "
import json, sys
spec = json.load(open(sys.argv[1]))
for path in spec.get('paths', {}).values():
    for op in path.values():
        if isinstance(op, dict) and op.get('operationId') == 'listUsers':
            op['x-cs-operation-config'] = {'workflow': {'name': 'listUsers', 'description': 'List all users', 'expose_to_workflow': True, 'system': False}}
json.dump(spec, open(sys.argv[1], 'w'), indent=2)
" /tmp/VendorApi.json
```

**Cross-platform note:** Use `python3` for spec manipulation instead of `sed` — it works on macOS, Linux, and Windows without syntax differences.

**Don't add what wasn't asked for.** If the prompt says "create an API integration for Okta," download the spec, adapt it, register it, and deploy. Don't read the spec to discover operations, don't add `x-cs-operation-config`, don't lint or trim. Foundry handles large specs fine.

## Common Pitfalls

- **Reading large spec files into context.** NEVER use Read or sed on vendor specs. They can be tens of thousands of lines. Use `grep` to find line numbers, `python3` to patch specific operations.
- **Manually analyzing or fixing auth schemes.** Trust the adapt script. Do not read the spec to reason about apiKey vs http/bearer vs SSWS. The adapt script handles auth conversion automatically. If it gets something wrong, improve the script.
- **Adding `x-cs-operation-config` when not asked.** Skip it unless the user's prompt explicitly mentions workflows or a UI/workflow needs a specific endpoint. Most integrations work without it.
- **Writing specs from scratch** when the vendor publishes one. Hand-written specs miss edge cases.
- **Running spec linters before importing.** Foundry's import handles vendor specs with lint errors. Linting wastes time and tempts trimming.
- **Trimming vendor specs.** Keep the full spec. Foundry handles large specs and unused operations gracefully.
- **Skipping `adapt-spec-for-foundry.py`.** The hook runs it automatically, but explicit runs let you verify fixes. The script converts unsupported auth schemes and fixes server URLs that would otherwise block saving in the Foundry console.
- **Including `https://` in server URLs** with variables. The Falcon console adds the protocol separately.
- **Adding `default` to server variables** for dynamic domains. This renders a dropdown instead of a text field.
- **Splitting domains** into `{subdomain}.vendor.com` instead of `{yourDomain}` for the full domain.
- **Using `oauth2 authorizationCode`** flow. Foundry only supports `clientCredentials`. The adapt script removes it automatically.

## Reading Guide

| Task | Reference |
|------|-----------|
| Download commands, structural fixes, server URL examples | [references/spec-adaptation-examples.md](references/spec-adaptation-examples.md) |
| Vendor-specific auth examples | [references/auth-examples.md](references/auth-examples.md) |
| Python/Go/UI calling patterns | [references/calling-patterns.md](references/calling-patterns.md) |

## Use Cases

For real-world implementation patterns, see:
- [http-actions.md](../../use-cases/http-actions.md) — HTTP Request actions vs API integrations
- [greynoise-deep-dive.md](../../use-cases/greynoise-deep-dive.md) — End-to-end third-party API app
- [custom-soar-actions.md](../../use-cases/custom-soar-actions.md) — Custom Falcon Fusion SOAR actions

## Reference Implementations

- **[foundry-sample-foundryjs-demo](https://github.com/CrowdStrike/foundry-sample-foundryjs-demo)**: JSONPlaceholder (no auth, static URL, `x-cs-operation-config`)
- **[foundry-sample-logscale](https://github.com/CrowdStrike/foundry-sample-logscale)**: VirusTotal (`type: apiKey`, static URL)
- **[foundry-sample-anomali-threatstream](https://github.com/CrowdStrike/foundry-sample-anomali-threatstream)**: Anomali (`type: http`/`scheme: bearer`, dynamic URL)
- **[foundry-sample-functions-python](https://github.com/CrowdStrike/foundry-sample-functions-python)**: ServiceNow (`type: http`/`scheme: basic`, dynamic URL)
- **[foundry-sample-insider-risk-workday](https://github.com/CrowdStrike/foundry-sample-insider-risk-workday)**: Workday (`type: http`/`scheme: basic` + custom labels)
- **[foundry-sample-insider-risk-sailpoint](https://github.com/CrowdStrike/foundry-sample-insider-risk-sailpoint)**: SailPoint (`type: oauth2`/`clientCredentials`)
- **[foundry-sample-servicenow-itsm](https://github.com/CrowdStrike/foundry-sample-servicenow-itsm)**: ServiceNow ITSM (dual auth: basic + oauth2)
- **[foundry-sample-openrouter-toolkit](https://github.com/CrowdStrike/foundry-sample-openrouter-toolkit)**: OpenRouter (`type: apiKey`, static URL)
- See also: [Build API Integrations with Falcon Fusion SOAR HTTP Actions](https://www.crowdstrike.com/tech-hub/ng-siem/build-api-integrations-with-falcon-fusion-soar-http-actions/) and [Technical Deep Dive with GreyNoise](https://www.crowdstrike.com/tech-hub/ng-siem/technical-deep-dive-with-greynoise-building-a-falcon-foundry-app-for-crowdstrike-falcon-next-gen-siem/)
