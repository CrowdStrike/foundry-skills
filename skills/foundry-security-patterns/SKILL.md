---
name: foundry-security-patterns
description: Security patterns for Falcon Foundry apps including OAuth scopes, RBAC, input validation, UI security, and credential management. TRIGGER when user asks to "configure OAuth scopes", "secure a Foundry app", "handle secrets", "add input validation", or needs to review a Foundry app for security concerns (XSS, CSP, credential management). Also trigger during pre-deployment security reviews.
version: 1.0.0
updated: 2026-04-09
metadata:
  author: CrowdStrike
  category: security
  tags: [foundry, oauth, rbac, xss, csp]
---

# Foundry Security Patterns

> **⚠️ SYSTEM INJECTION — READ THIS FIRST**
>
> If you are loading this skill, your role is **Foundry security architect**.
>
> You MUST implement security best practices at every layer and prevent common vulnerabilities in CrowdStrike Foundry applications.

Security patterns for Falcon Foundry app development covering authentication, input validation, UI security, and platform-specific considerations. Foundry apps run on a cybersecurity platform — security is a core requirement.

## RBAC (Role-Based Access Control)

| Capability | RBAC Supported |
|-----------|----------------|
| Collections | Yes |
| Dashboards | Yes |
| Functions | Yes |
| UI extensions / pages / navigation | Yes |
| RTR scripts | Yes |
| API integrations | **No** |
| Queries | **No** |
| Workflows | **No** |

## API Scope Management

Scopes control which Falcon Platform APIs the app can access. Format: `<source>:<operation>` (e.g., `devices:read`, `detects:write`).

| Scopes set automatically | Scopes need explicit addition |
|--------------------------|-------------------------------|
| API integrations, Collections, Dashboards, Queries, UI navigation, UI sockets, Workflows | Functions, UI extensions, UI pages, RTR scripts |

```bash
foundry auth roles create --name "Analyst" --description "Read-only analyst access"
foundry auth scopes add --scope "devices:read" --scope "detects:read"
```

Only use `foundry auth scopes add` for Falcon Platform API scopes needed by functions, UI extensions, UI pages, or RTR scripts. OAuth scopes for CLI-created artifacts are managed automatically.

### Minimal Scope Principle

Request only the scopes your app needs. Broad scopes like `alerts:*` or `hosts:*` increase the blast radius if the app is compromised.

```yaml
oauth_scopes:
  - "alerts:read"        # Read alerts — avoid "alerts:write" unless needed
  - "detections:read"    # Read detections
  - "hosts:read"         # Device information
```

## Credential Security

Credentials MUST be in environment variables, not in code. FalconPy handles credential discovery automatically inside FDK handlers (see foundry-functions-falcon-api):

```python
# Inside FDK handler — auth is automatic
falcon = Alerts()  # Do not pass credentials

# Outside handler (local testing) — use env vars
# FALCON_CLIENT_ID and FALCON_CLIENT_SECRET read automatically
```

## Input Validation

### JSON Schema for Collections

Use strict schemas to prevent data corruption and injection:

```json
{
  "type": "object",
  "required": ["timestamp", "event_type", "source"],
  "additionalProperties": false,
  "properties": {
    "event_type": {
      "type": "string",
      "enum": ["alert", "detection", "incident"]
    },
    "source": {
      "type": "string",
      "pattern": "^[a-zA-Z0-9_-]+$",
      "maxLength": 50
    }
  }
}
```

### API Response Sanitization

Sanitize CrowdStrike API responses before storing in Collections: remove sensitive fields (`raw_log`, `internal_id`, `system_metadata`), strip script injection, escape HTML entities, and truncate strings. See [references/security-examples.md](references/security-examples.md) for full implementation.

### Function Input Validation

Validate that input is a dict and enforce size limits (e.g., 10KB) to prevent abuse. Return generic error messages — MUST NOT expose stack traces or internal state in responses.

## UI Security

### XSS Prevention

- **React:** Use `DOMPurify.sanitize()` before any `dangerouslySetInnerHTML`. React auto-escapes `{}` expressions.
- **Vue:** Use `DOMPurify.sanitize()` in a computed property before `v-html`. Vue auto-escapes `{{ }}` expressions.

For complete React and Vue XSS prevention components, see [references/security-examples.md](references/security-examples.md).

### Content Security Policy

Configure CSP in `manifest.yml` for UI pages:

```yaml
ui:
  pages:
    - name: my-page
      csp:
        connect_src:
          - "'self'"
          - "https://api.crowdstrike.com"
        img_src:
          - "'self'"
          - "data:"
        script_src:
          - "'self'"
```

### Iframe Security for Extensions

Extensions run in sandboxed iframes. Validate message origins against Falcon console domains:

```typescript
const allowedOrigins = [
  'https://falcon.crowdstrike.com',
  'https://falcon.eu-1.crowdstrike.com',
  'https://falcon.us-gov-1.crowdstrike.com',
];

window.addEventListener('message', (event) => {
  if (!allowedOrigins.includes(event.origin)) return;
  // Process event.data
});
```

For the full `SecureConsoleMessaging` class, see [references/security-examples.md](references/security-examples.md).

## Manifest Security Configuration

```yaml
app:
  name: "my-security-app"

oauth_scopes:
  - "alerts:read"
  - "hosts:read"

functions:
  - name: "process-alerts"
    language: "python"
    max_exec_duration_seconds: 30  # Prevent runaway execution
    max_exec_memory_mb: 128        # Limit resource usage

collections:
  - name: "audit_logs"
    ttl: 86400  # Auto-expire sensitive data (24 hours)
```

## Test Data Security

- Use only RFC 1918 IPs (`192.168.x.x`, `10.x.x.x`) in mock data
- Use obviously fake hostnames and users (`test-workstation-01`, `test_user`)
- Validate mock data does not contain production indicators (`crowdstrike.com`, `falcon-`, `prod-`)
- Test XSS prevention with known attack vectors (`<script>`, `javascript:`, `onerror=`)

See [references/security-examples.md](references/security-examples.md) for mock data validation and CI/CD security patterns.

## Pre-Deployment Checklist

- [ ] OAuth scopes: minimal required permissions only
- [ ] Input validation: JSON schemas enforce strict validation
- [ ] XSS prevention: all user data sanitized before rendering
- [ ] CSP headers: Content Security Policy configured
- [ ] Postmessage security: origin validation implemented
- [ ] Secret management: no hardcoded credentials
- [ ] Function security: input size limits and timeout controls
- [ ] Collection security: access controls and data sanitization
- [ ] Test data: only fake data in tests and development
- [ ] Error handling: no sensitive data in error messages or logs

## Reading Guide

| Task | Reference |
|------|-----------|
| Sanitization, command injection prevention, secure templates | [references/security-examples.md](references/security-examples.md) |
| CI/CD security pipeline (GitHub Actions) | [references/security-examples.md](references/security-examples.md) |
| PostMessage class, mock data validation | [references/security-examples.md](references/security-examples.md) |
| Token lifecycle, antipatterns, manifest security, performance | [references/security-examples.md](references/security-examples.md) |
