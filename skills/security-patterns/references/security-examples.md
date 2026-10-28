# Security Code Examples Reference

> Parent skill: [security-patterns](../SKILL.md)

## API Response Sanitization (Python)

Trim API responses before storing them: drop fields the app doesn't need and bound string lengths. Store the values raw. HTML-escaping before storage double-escapes when the UI renders the value, and no regex strips every script vector; escape or sanitize at render time instead (see the React and Vue examples below).

```python
from typing import Any, Dict

SENSITIVE_FIELDS = ("raw_log", "internal_id", "system_metadata")
MAX_STRING_LENGTH = 1000

def trim_api_response(data: Dict[str, Any]) -> Dict[str, Any]:
    """Drop unneeded fields and bound string lengths before storing in a collection."""
    trimmed = {k: v for k, v in data.items() if k not in SENSITIVE_FIELDS}
    for key, value in trimmed.items():
        if isinstance(value, str):
            trimmed[key] = value[:MAX_STRING_LENGTH]
    return trimmed
```

## Command Injection Prevention (Python)

```python
import subprocess
import shlex

def safe_command_execution(user_input: str) -> str:
    """Safe execution avoiding command injection"""

    # Allowlist approach - only allow specific commands
    allowed_commands = {
        'ping': ['ping', '-c', '1'],
        'nslookup': ['nslookup']
    }

    try:
        parts = shlex.split(user_input)
        command = parts[0]

        if command not in allowed_commands:
            raise ValueError(f"Command {command} not allowed")

        # Build command safely
        cmd = allowed_commands[command] + parts[1:5]  # Limit arguments

        # Execute with timeout and restricted environment
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=10,
            env={'PATH': '/usr/bin:/bin'}  # Restricted PATH
        )

        return result.stdout

    except (ValueError, subprocess.TimeoutExpired) as e:
        return f"Error: {str(e)}"
```

## XSS Prevention in React

```typescript
import DOMPurify from 'dompurify';

interface AlertProps {
  alertData: {
    description: string;
    hostname: string;
    severity: number;
  };
}

export const AlertComponent: React.FC<AlertProps> = ({ alertData }) => {
  const safeDescription = DOMPurify.sanitize(alertData.description);

  return (
    <div className="alert-card">
      {/* Safe - React escapes by default */}
      <h3>{alertData.hostname}</h3>
      <span className="severity">{alertData.severity}</span>

      {/* Dangerous - only use with sanitized content */}
      <div
        dangerouslySetInnerHTML={{
          __html: safeDescription
        }}
      />
    </div>
  );
};
```

## XSS Prevention in Vue.js

```vue
<template>
  <div class="alert-details">
    <!-- Safe - Vue escapes automatically -->
    <h2>{{ alert.title }}</h2>

    <!-- Sanitize before v-html -->
    <div v-html="sanitizedDescription"></div>
  </div>
</template>

<script>
import DOMPurify from 'dompurify';

export default {
  props: ['alert'],
  computed: {
    sanitizedDescription() {
      return DOMPurify.sanitize(this.alert.description);
    }
  }
};
</script>
```

## Secure Function Structure (Python)

Use the FDK handler pattern from the `functions-development` skill. The FDK supplies credentials inside the handler, so don't check for credential environment variables; they aren't set in the Falcon cloud. Let `request_schema.json` validate the body's shape, and bound its size in code.

```python
import json
from logging import Logger
from typing import Dict, Optional

from crowdstrike.foundry.function import Function, Request, Response, APIError

FUNC = Function.instance()
MAX_BODY_BYTES = 10_000


@FUNC.handler(method="POST", path="/process")
def on_post(request: Request, _config: Optional[Dict[str, object]], logger: Logger) -> Response:
    if not isinstance(request.body, dict):
        return Response(code=400, errors=[APIError(code=400, message="Request body must be a JSON object")])

    if len(json.dumps(request.body)) > MAX_BODY_BYTES:
        return Response(code=413, errors=[APIError(code=413, message="Request body is too large")])

    try:
        result = process_event_safely(request.body)
    except (KeyError, ValueError) as e:
        logger.error(f"Processing failed: {type(e).__name__}")  # no payload or stack trace
        return Response(code=500, errors=[APIError(code=500, message="Internal error")])

    return Response(body={"data": result}, code=200)


if __name__ == "__main__":
    FUNC.run()
```

## Role-Based Collection Access

The FDK `Request` has no roles field, so don't build role checks into function code. Gate the collection itself with `permissions` and assign the role in the console; see the RBAC section of the parent skill and the full manifest example at the end of this file. To narrow what a handler returns, filter server-side with FQL on `x-cs-indexable` fields:

```python
from falconpy import CustomStorage

storage = CustomStorage()  # inside the handler; pass ext_headers={"X-CS-APP-ID": ...} for local runs
response = storage.SearchObjects(collection_name="incidents", filter="severity:>=3", limit=100)
if response["status_code"] != 200:
    ...  # return an error Response
object_keys = [r["object_key"] for r in response["body"]["resources"]]  # metadata only; GetObject for content
```

## Secure Mock Data (TypeScript)

```typescript
export const mockAlertData = {
  alerts: [
    {
      id: "mock_alert_001",
      hostname: "test-workstation-01",
      description: "Simulated malware detection",
      severity: 7,
      timestamp: "2024-01-15T10:30:00Z",
      source_ip: "192.168.1.100",  // RFC 1918 ranges only
      user: "test_user"
    }
  ]
};

export const validateMockData = (data: any) => {
  const prodIndicators = ['crowdstrike.com', 'falcon-', 'prod-', '.internal'];
  const jsonStr = JSON.stringify(data);
  for (const indicator of prodIndicators) {
    if (jsonStr.includes(indicator)) {
      throw new Error(`Mock data contains production indicator: ${indicator}`);
    }
  }
};
```

## Security Test Patterns (Python)

```python
import pytest

class TestSecurityPatterns:

    @pytest.fixture
    def safe_test_data(self):
        return {
            'alerts': [
                {
                    'id': 'test_001',
                    'hostname': 'junit-host-01',
                    'ip': '10.0.0.1',
                    'user': 'test_user_001',
                    'description': 'Test malware signature XYZ'
                }
            ]
        }

    def test_sanitization(self):
        malicious_inputs = [
            '<script>alert("xss")</script>',
            'javascript:alert(1)',
            '"><img src=x onerror=alert(1)>',
        ]

        for malicious_input in malicious_inputs:
            sanitized = sanitize_input(malicious_input)
            assert '<script>' not in sanitized
            assert 'javascript:' not in sanitized
```

## CI/CD Security Pipeline

```yaml
# .github/workflows/security.yml
name: Security Checks

on: [push, pull_request]

jobs:
  security:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Secret Detection
        run: |
          grep -r "client_secret" . && exit 1 || true
          grep -r "api_key" . && exit 1 || true

      - name: Manifest Security Validation
        run: python scripts/validate_manifest_security.py manifest.yml

      - name: Dependency Security
        run: |
          pip install safety
          safety check -r requirements.txt
```

## Falcon API Clients in Functions (Python)

Inside an FDK handler, construct FalconPy service classes with no arguments; the FDK supplies auth. Passing `client_id` / `client_secret` breaks context-based auth in the Falcon cloud (see `functions-falcon-api`). Check `status_code` on every response rather than validating a token up front.

```python
from crowdstrike.foundry.function import Function, Request, Response, APIError
from falconpy import Hosts

FUNC = Function.instance()


@FUNC.handler(method="POST", path="/host-details")
def on_post(request: Request) -> Response:
    falcon = Hosts()  # no credentials: auth comes from the handler context
    response = falcon.get_device_details(ids=request.body["host_id"])
    if response["status_code"] != 200:
        return Response(
            code=response["status_code"],
            errors=[APIError(code=response["status_code"], message="Failed to retrieve host")],
        )
    return Response(body={"host_details": response["body"]["resources"][0]}, code=200)
```

## Multi-Environment Security

The manifest declares scopes once, in `auth.scopes`; it has no per-environment scope settings. Declare the minimum the production app needs, and keep broader test-only scopes out of the committed manifest.

```yaml
# manifest.yml
auth:
  scopes: ["alerts:read", "alerts:write", "devices:read"]  # Minimal required
```

## Local Development Security

For running functions locally, FalconPy reads credentials from the environment. Use a separate API client with only the scopes the app needs, keep the values in an untracked file, and never commit them.

```bash
# .env (gitignored): local function testing only
FALCON_CLIENT_ID=<API_CLIENT_ID>
FALCON_CLIENT_SECRET=<API_CLIENT_SECRET>
APP_ID=<APP_ID>   # sent as X-CS-APP-ID for collection calls
```

## CSP for UI Pages and Extensions

Foundry apps don't set HTTP response headers, so `X-Frame-Options`, `frame-ancestors`, and similar header-based controls don't apply. The Falcon console builds the CSP from each page's or extension's `content_security_policy` block in `manifest.yml`, which accepts `connect-src`, `img-src`, `script-src`, `style-src`, `style-src-elem`, `form-action`, `media-src`, and `object-src`. List only the external hosts the code calls; the full manifest example below shows the block in place.

## Secure Manifest Settings (Full Example)

The security-relevant parts of a `manifest.yml`. The CLI generates every entry; edit only the values shown.

```yaml
# Minimal OAuth scopes: only what the functions call
auth:
  scopes:
    - alerts:read
    - devices:read

ui:
  pages:
    dashboard:
      name: dashboard
      path: ui/pages/dashboard/src/dist
      entrypoint: ui/pages/dashboard/src/dist/index.html
      content_security_policy:
        connect-src:
          - https://api.example.com   # only the external hosts the page calls
        script-src: []
      permissions: [ "myapp:access" ]

functions:
  - name: process-alerts
    path: functions/process-alerts
    environment_variables: {}
    handlers:
      - name: process
        method: POST
        api_path: /process
        request_schema: request_schema.json
        permissions: []
    language: python
    max_exec_duration_seconds: 30   # bound runaway executions

collections:
  - name: incident_data
    schema: collections/incident_data.json
    permissions: [ "myapp:access" ]   # without this, any CID user can read and write it
```

## Iframe Sandboxing for UI Extensions

The Falcon console renders pages and extensions in a sandboxed iframe that the app doesn't configure. The sandbox has no `allow-same-origin`, so web storage and cookies throw; `ui-development`'s sandboxed-iframe reference lists what that rules out.

## Common Security Antipatterns

**Avoid these patterns:**

```yaml
# Too broad OAuth scopes
auth:
  scopes: ["*:*", "alerts:*", "devices:*"]

# Wildcard CSP sources (under a page's content_security_policy)
content_security_policy:
  connect-src: ["*"]
  script-src: ["*"]

# No input validation
def process_data(user_input):
    return eval(user_input)  # NEVER DO THIS

# Hardcoded secrets
CLIENT_SECRET = "abc123..."

# Logging sensitive data
logger.info(f"Processing user {email} with token {api_token}")
```

**Secure alternatives shown throughout this file and the parent SKILL.md.**

## Performance Considerations

- **Input validation caching:** Cache validation results for repeated data
- **CSP optimization:** Use specific sources instead of wildcards
- **Sanitization efficiency:** Use efficient sanitization libraries
- **Collection queries:** Index security-relevant fields for fast filtering

## Integration with Foundry Skills

**When used with other skills:**
- **development-workflow:** Security validation in each phase
- **ui-development:** XSS and CSP enforcement
- **functions-development:** Secure coding patterns
- **collections-development:** Access controls and validation
- **workflows-development:** Secure automation patterns

**Security reviews required at:**
- Manifest finalization (OAuth scopes, CSP settings)
- Function implementation (input validation, error handling)
- UI component development (XSS prevention, sandboxing)
- Pre-deployment validation (security checklist completion)

## RBAC — Complete Manifest Wiring Example

End-to-end RBAC for an app with one page, one nav link, and one collection — the artifact-gate step from the RBAC section of the parent skill.

```yaml
# manifest.yml (relevant sections)
auth:
  scopes: []
  permissions:                     # written by `foundry auth permissions create`
    "myapp:access":
      id: "abc123..."              # CLI-written — do not hand-edit
      name: "My App Access"
      description: "Access to My App"   # ≤ 50 chars (enforced)
  roles:
    - id: "role-id..."
      name: "My App Operator"
      description: "My App operator role"
      permissions: [ "myapp:access" ]

ui:
  pages:
    dashboard:                     # a map keyed by page ID; path and entrypoint are CLI-written
      name: dashboard
      path: ui/pages/dashboard/src/dist
      entrypoint: ui/pages/dashboard/src/dist/index.html
      permissions: [ "myapp:access" ]   # blocks access to the page
  navigation:
    links:
      - path: /
        name: Dashboard
        permissions: [ "myapp:access" ]   # hides the menu entry
        ref: pages.dashboard

collections:
  - name: app_config
    schema: collections/app_config.json
    permissions: [ "myapp:access" ]   # without this, any CID user can CRUD the data
```

CLI sequence:

```bash
# 1. permission + role (colon key; ≤50-char description)
foundry auth permissions create --key "myapp:access" --name "My App Access" \
  --description "Access to My App" --role-name "My App Operator" \
  --role-description "My App operator role" --no-prompt
# 2. validate (free dry-run)      3. deploy (the gate isn't live until release + upgrade)
foundry apps validate --no-prompt && foundry apps deploy --change-type Minor --change-log "Add RBAC" --no-prompt
# 4. assign the role in the console to yourself and everyone who keeps access, before releasing
# 5. release (Minor reaches installed apps automatically), then confirm you can still open the app
foundry apps release --change-type Minor --deployment-id <deployment-id> --notes "Add RBAC" --no-prompt
```

Rollback (needs no app access). Do NOT `git checkout manifest.yml` — that discards the `app_id` and per-artifact IDs the deploy wrote back, and the next deploy fails with `an app with the provided name already exists`. Instead revert only the RBAC additions (remove the role from its users, delete the `auth.permissions` / `auth.roles` entries you added, and set each gated artifact back to `permissions: []`), leaving the deploy-written IDs in place:

```bash
# after reverting only the auth.permissions / auth.roles entries + artifact permissions: gates
foundry apps deploy --change-type Patch --change-log "Roll back RBAC" --no-prompt
foundry apps release --change-type Patch --deployment-id <deployment-id> --notes "Roll back RBAC" --no-prompt
```
