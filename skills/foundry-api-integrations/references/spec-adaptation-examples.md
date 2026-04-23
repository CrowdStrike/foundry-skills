# Spec Adaptation Examples

Detailed examples for adapting vendor OpenAPI specs for Foundry, including vendor spec download patterns, validation fixes, and autocomplete dropdown configuration.

## Downloading Vendor Specs

**NEVER write an OpenAPI spec from scratch.** Always download the vendor's official spec first.

### Using GitHub CLI

Check if `gh` (GitHub CLI) is installed -- it simplifies searching and downloading:

```bash
# Check if GitHub CLI is available
gh --version 2>/dev/null

# Search for a vendor's SDK repos
gh search repos "{vendor}-sdk" --owner {vendor} --json fullName,description --limit 10

# Find the default branch (not always 'main')
gh api "repos/{owner}/{repo}" --jq '.default_branch'

# Search for spec files within a repo (use the correct default branch)
gh api "repos/{owner}/{repo}/git/trees/{branch}?recursive=1" \
  --jq '.tree[].path | select(test("swagger|openapi"; "i"))'

# Download a spec file (use download_url -- base64 decode fails for large files)
curl -sL "$(gh api 'repos/{owner}/{repo}/contents/{path}' --jq '.download_url')" \
  -o /tmp/VendorApi.yaml
```

### Direct Download

```bash
# Or download directly with curl when the URL is known
curl -o /tmp/VendorApi.yaml https://raw.githubusercontent.com/vendor/repo/main/openapi.yaml
```

### Other Sources

- **API docs**: Many vendors link to their OpenAPI/Swagger spec from developer documentation
- **SwaggerHub**: Some vendors publish at `app.swaggerhub.com`

## Spec Size

**NEVER trim or subset a vendor spec unless the user explicitly asks.** Vendor specs can be huge (CrowdStrike's own swagger is multiple megabytes). Spec size is NOT a problem -- Foundry handles large specs. Keeping the full spec means more operations can be exposed later without re-downloading.

**Do NOT run spec linters (redocly, spectral, etc.) before importing.** Foundry's import handles vendor specs with lint errors (duplicate `required` arrays, etc.). Linting wastes tokens and tempts the agent to trim the spec to fix lint errors, which is worse than importing the full spec as-is.

**Validate immediately after `api-integrations create`** (`foundry apps validate --no-prompt`), before writing other code. This catches spec issues in seconds without a full deploy.

## Autocomplete Dropdown Patterns

When configuring API integration operations in the Falcon console, parameters can render as autocomplete dropdowns instead of plain text fields.

### Static Lists

Use `enum` values in the parameter or request body schema for a fixed dropdown:

```yaml
parameters:
  - name: status
    in: query
    schema:
      type: string
      enum: ["active", "inactive", "suspended"]
```

### Dynamic Lists (Providing + Consuming Operations)

Link two operations so one provides dropdown options for another:

1. **Providing operation**: Returns a list of values (e.g., list all users)
2. **Consuming operation**: Uses the result as dropdown options for a parameter (e.g., select a user to update)

Configure this in the Falcon console's API integration settings by linking the providing operation's response field to the consuming operation's parameter.

### Server-Side Search

For large datasets, use server-side search with placeholder variables:

- `~search_text~` -- the text the user types in the dropdown
- `~search_field~` -- the field being searched

These placeholders are replaced at runtime with user input, enabling autocomplete search against the external API.

### Multiselect Dropdowns

Define the body parameter as an `array` type to allow multiple selections:

```yaml
requestBody:
  content:
    application/json:
      schema:
        properties:
          user_ids:
            type: array
            items:
              type: string
```

## HTTP Actions vs. Functions Decision Framework

| Criteria | HTTP Actions | Functions |
|----------|-------------|-----------|
| **Simple API call** | Use HTTP action | Overkill |
| **Data transformation needed** | Limited (CEL only) | Full language support |
| **Multiple API calls** | Chain workflow steps | Single function handles all |
| **State management** | Workflow variables | In-memory + collections |
| **Timeout** | 30 seconds fixed | 30s - 900s configurable |
| **Response size** | 10 MB max (JSON only) | 120 KB max |

Use HTTP Actions (via API Integrations) for straightforward API calls from workflows. Use Functions when complex data transformation, multiple sequential API calls, or longer execution times are needed.

## Vendor-Specific Server URL Examples

Production-verified server URL patterns for common vendors:

**Fixed base URL** (same domain for all users):

```json
"servers": [{"url": "https://www.virustotal.com"}]
"servers": [{"url": "https://openrouter.ai/api/v1"}]
```

**ServiceNow** (variable with path suffix):
```json
"servers": [{"url": "{instance}.service-now.com", "variables": {"instance": {"description": "the \"instance\" variable is replaced with a dynamic value at execution time"}}}]
```

**SailPoint** (variable with API path):
```json
"servers": [{"url": "{host}/v3", "variables": {"host": {"description": "the \"host\" variable is replaced with a dynamic value at execution time"}}}]
```

**Generic pattern** (variable only):
```json
"servers": [{"url": "{host}", "variables": {"host": {"description": "the \"host\" variable is replaced with a dynamic value at execution time"}}}]
```

**Okta and similar per-tenant APIs:**
```yaml
# CORRECT -- matches production pattern, renders text field for domain:
servers:
  - url: "{yourOktaDomain}"
    variables:
      yourOktaDomain:
        description: the "yourOktaDomain" variable is replaced with a dynamic value at execution time

# WRONG -- includes protocol (Falcon adds it separately, causing double-protocol):
servers:
  - url: https://{yourOktaDomain}
    variables:
      yourOktaDomain:
        default: subdomain.okta.com
```

**Rules:**
- Do NOT include `https://` in server URLs with variables. The Falcon console provides a separate "Host protocol" dropdown during configuration.
- Do NOT add a `default` value to server variables for dynamic domains. A `default` value renders as a dropdown instead of a free-text input field.
