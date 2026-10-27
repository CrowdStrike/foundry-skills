---
name: security-patterns
description: Security patterns for Falcon Foundry apps including OAuth scopes, RBAC, input validation, UI security, and credential management. TRIGGER when user asks to "configure OAuth scopes", "secure a Foundry app", "handle secrets", "add input validation", or needs to review a Foundry app for security concerns (XSS, CSP, credential management). Also trigger during pre-deployment security reviews.
version: 1.6.0
updated: 2026-10-01
tags: [foundry, oauth, rbac, xss, csp]
author: CrowdStrike
license: MIT
compatibility: Claude Code >=1.0
metadata:
  category: security
---

# Foundry Security Patterns

> **Part of a suite.** If `development-workflow` has not already run, and this is a new app or its first capability, load the `development-workflow` skill first — it owns the CLI prerequisite check, scaffolding order, and manifest coordination.

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

### The Permission → Role → Artifact Model

RBAC is three linked pieces the table above doesn't spell out — you need all three or the gate is silently absent.

**1. Permission** (one command, also creates the role):

```bash
foundry auth permissions create \
  --key "myapp:access" \
  --name "My App Access" \
  --description "Access to My App" \
  --role-name "My App Operator" \
  --role-description "My App operator role" \
  --no-prompt
```

Two undocumented constraints, each a silent first-attempt failure if missed: **`--key` must be colon-segmented** (`myapp:access`, not a plain word), and **`--description` must be ≤ 50 characters**. This writes `auth.permissions["myapp:access"]: {id, name, description}` into `manifest.yml` and creates + associates the role in one shot.

> **Prefix the key and role name with your app name.** Permission and role names are unique CID-wide; a generic name (`app:access`, `Operator`) collides with other apps' identically-named entries on the same tenant and the deploy fails with no useful error.

**2. Role** — appears automatically under `auth.roles` after step 1; inspect it there, and do NOT run `foundry auth roles create` for it (that would orphan a duplicate role). Reserve standalone `foundry auth roles create` for a role built *independently* of `permissions create` — e.g. one that bundles permission keys that already exist (via `--permissions`); it creates a role but no permission:

```bash
foundry auth roles create --name "Analyst" --permissions "myapp:access,myapp:report" --description "Read-only analyst access" --no-prompt
```

That makes a second role carrying already-created permission keys; it does NOT create a new permission. Use it only when you deliberately want a role separate from the one `permissions create` already made — never to "add" the role from step 1.

**3. Artifact gates** — reference the permission **key** in the `permissions:` list of each artifact. Gating a page does NOT hide its nav link — gate both:

```yaml
ui:
  pages:
    - name: dashboard
      path: /
      permissions: [ "myapp:access" ]
  navigation:
    links:
      - name: Dashboard
        path: /
        permissions: [ "myapp:access" ]   # separate — page gate alone won't hide the menu entry
collections:
  - name: app_config
    schema: collections/app_config.json
    permissions: [ "myapp:access" ]
```

`foundry apps validate --no-prompt` is a free syntax check before deploying. A full end-to-end manifest example is in [references/security-examples.md](references/security-examples.md).

### New roles auto-assign to all Falcon Administrators

`foundry auth permissions create` / `foundry auth roles create` prints: *"Your new role will be automatically assigned to all Falcon Administrators and can later be assigned to other users individually."* Implications:

- The console role view shows **"0 users"** — that counts only *explicit* assignments; the Falcon Admin grant is implicit and invisible there. The role is active even at zero.
- **RBAC can't exclude Falcon Administrators** — admins always hold the permission and bypass every gate, so you can't lock them *out* (consistent with Workflows being non-gateable above). Restricting an app *to* admins is the easy direction: create the permission and simply never assign its role to a non-admin.
- It **cushions lockout**: if your own account is a Falcon Admin you keep implicit access even if you forget to assign the role before release. Assign explicitly anyway.

### Lockout-safe RBAC rollout

Turning on RBAC is the one change that can lock you out of your own app mid-release. Safe sequence:

1. `foundry auth permissions create` — permission + role into the manifest.
2. `foundry apps deploy` — gate is in the bundle, not yet live.
3. **Assign the role to yourself in the Falcon console** (Users → Roles & Permissions) — don't rely only on the implicit admin grant.
4. **Release only after you've confirmed your own access** — open the app and verify you can still reach it.
5. Upgrade in the App Catalog; users need the role assigned before the gate applies to them.

**Rollback needs no app access** — App Manager upgrade/uninstall are console-admin capabilities the app's own RBAC cannot block. Do NOT `git checkout manifest.yml` to roll back: that also discards the `app_id` and per-artifact IDs the deploy wrote back, so the next deploy fails with *"an app with the provided name already exists."* Revert only the RBAC additions, leaving every deploy-written ID in place — delete the `auth.permissions` and `auth.roles` entries you added, and remove the `permissions:` gate list from each artifact you gated (or commit the deploy-written IDs first, then revert just those sections). Then:

```bash
foundry apps deploy --change-type Patch --change-log "Roll back RBAC" --no-prompt
foundry apps release --change-type Patch --deployment-id <deployment-id> --notes "Roll back RBAC" --no-prompt
```

Then upgrade in the App Catalog.

### Collection RBAC vs workflow system-action writes

When you gate a collection that a workflow also writes to via a `system_action: true` store action, the human-role gate does **not** block those writes — system actions run under the app identity, not the human user's. Confirm it after enabling the gate: trigger a run and verify results still store. The deploy-first-then-release sequence above makes that check safe before any user is affected.

## API Scope Management

Scopes control which Falcon Platform APIs the app can access. Format: `<source>:<operation>` (e.g., `devices:read`, `detects:write`).

| Scopes set automatically | Scopes need explicit addition |
|--------------------------|-------------------------------|
| API integrations, Collections, Dashboards, Queries, UI navigation, UI sockets, Workflows | Functions, UI extensions, UI pages, RTR scripts |

```bash
foundry auth scopes add --scopes "devices:read,detects:read" --no-prompt
```

Only use `foundry auth scopes add` for Falcon Platform API scopes needed by functions, UI extensions, UI pages, or RTR scripts. OAuth scopes for CLI-created artifacts are managed automatically.

- **Adding a scope makes the next release a major version**, and the app's users must accept the new permission before it takes effect. Decide the app's scopes before its first release, but don't add ones it may never use (see Minimal Scope Principle).
- **`scopes add` rejects some valid scope names.** Its built-in list is incomplete (as of CLI 2.1.2 it rejects `humio-auth-proxy:read`, which Falcon Next-Gen SIEM searches need, and `ngsiem-persisted-aggregations:read`). When the API's swagger names a scope the CLI rejects, add it to `auth.scopes` in `manifest.yml` by hand. `foundry apps validate` and deploy accept it.

### Minimal Scope Principle

Request only the scopes your app needs. Broad scopes like `alerts:*` or `devices:*` increase the blast radius if the app is compromised.

```yaml
# manifest.yml
auth:
  scopes:
    - "alerts:read"      # Read alerts — avoid "alerts:write" unless needed
    - "detects:read"     # Read detections
    - "devices:read"     # Device information (Hosts API)
```

## Credential Security

Credentials MUST be in environment variables, not in code. FalconPy handles credential discovery automatically inside FDK handlers (see functions-falcon-api):

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

auth:
  scopes:
    - "alerts:read"
    - "devices:read"

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
- [ ] Collection security: access controls and data sanitization. ⚠️ **Default posture is wide open:** a fresh app ships `auth: {scopes: [], permissions: {}, roles: []}` and every collection `permissions: []` — any Falcon console user in the CID can read and write every collection, including any credentials or per-tenant data stored there. Gate every collection and page (see RBAC above) before the first release if the app handles secrets or multi-tenant data.
- [ ] Test data: only fake data in tests and development
- [ ] Error handling: no sensitive data in error messages or logs

## Reading Guide

| Task | Reference |
|------|-----------|
| Sanitization, command injection prevention, secure templates | [references/security-examples.md](references/security-examples.md) |
| CI/CD security pipeline (GitHub Actions) | [references/security-examples.md](references/security-examples.md) |
| PostMessage class, mock data validation | [references/security-examples.md](references/security-examples.md) |
| Token lifecycle, antipatterns, manifest security, performance | [references/security-examples.md](references/security-examples.md) |
