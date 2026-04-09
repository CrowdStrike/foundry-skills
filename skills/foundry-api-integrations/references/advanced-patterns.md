# Advanced Patterns and Guardrails

Behavioral guardrails, counter-rationalizations, and cross-skill integration points for API integrations.

## Counter-Rationalizations Table

| Your Excuse | Reality |
|-------------|---------|
| "I can write the OpenAPI spec from scratch" | Vendor specs are tested, comprehensive, and handle edge cases you'll miss |
| "I know what this API looks like, I'll just write it" | You'll miss parameters, response fields, error schemas, and security definitions |
| "I'll validate the spec with a linter first" | Skip linting -- Foundry handles specs with lint errors. Linting wastes tokens and tempts trimming |
| "The CLI handles workflow sharing" | It doesn't -- `api-integrations create` only sets name/description/spec; add `x-cs-operation-config` manually |
| "I'll add enum to constrain server variable values" | `enum` on server variables creates a dropdown -- users can't type custom values |
| "Foundry needs OAuth 2.0, I should switch from apiKey" | Foundry supports apiKey (with bearerFormat for prefix), http/bearer, http/basic, and oauth2/clientCredentials |
| "I'll include https:// in the server URL" | Falcon console provides a separate "Host protocol" dropdown |
| "This spec is too big, I need to trim it" | Spec size is NOT a problem -- keep the full spec unless deployment fails |
| "The spec has hundreds of endpoints but I only need one" | Download the full spec anyway. Foundry handles large specs. Writing a "focused" spec loses response schemas, error handling, and security definitions |
| "Let me check how the auth scheme works before registering" | Do not analyze the spec's auth. Run adapt-spec-for-foundry.py and register. The script handles auth conversion from 12 production patterns |

## Red Flags - STOP Immediately

If you catch yourself:
- Writing an OpenAPI spec from scratch when the vendor publishes one (even if their spec is "too big")
- Trimming, subsetting, or extracting operations from a vendor's OpenAPI spec (keep the full spec)
- Using Python/Ruby/Node or linters to validate OpenAPI specs before importing (Foundry handles lint errors)
- Assuming `foundry api-integrations create` handles `x-cs-operation-config`
- Adding `enum` to OpenAPI server variables (creates dropdowns instead of text fields)
- Including `https://` in server URLs that use variables
- Changing the vendor's auth type (but DO remove unused extra schemes)
- Adding `default` values to server variables for dynamic domains

**STOP. Follow the patterns above. No shortcuts.**

## Integration with Other Skills

- **foundry-development-workflow:** API integrations are delegated from the orchestrator
- **foundry-ui-development:** UI extensions call API integrations via `falcon.apiIntegration()`
- **foundry-workflows-development:** Workflows use HTTP Actions to call API integration operations
- **foundry-functions-development:** Functions call API integrations for external service access
- **foundry-security-patterns:** Authentication scheme configuration
