# Security Code Examples Reference

> Parent skill: [security-patterns](../SKILL.md)

## API Response Sanitization (Python)

```python
import re
from typing import Dict, Any

def sanitize_api_response(data: Dict[str, Any]) -> Dict[str, Any]:
    """Sanitize CrowdStrike API response before storing in Collections"""

    # Remove sensitive fields
    sensitive_fields = ['raw_log', 'internal_id', 'system_metadata']
    for field in sensitive_fields:
        data.pop(field, None)

    # Sanitize string fields
    for key, value in data.items():
        if isinstance(value, str):
            # Remove potential script injection
            value = re.sub(r'<script[^>]*>.*?</script>', '', value, flags=re.IGNORECASE | re.DOTALL)
            # Escape HTML entities
            value = value.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
            # Truncate long strings
            data[key] = value[:1000]

    return data
```

## Command Injection Prevention (Python)

```python
import subprocess
import shlex

def safe_command_execution(user_input: str) -> str:
    """Safe execution avoiding command injection"""

    # Whitelist approach - only allow specific commands
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

## Secure Postmessage Communication

```typescript
class SecureConsoleMessaging {
  private allowedOrigins = [
    'https://falcon.crowdstrike.com',
    'https://falcon.eu-1.crowdstrike.com',
    'https://falcon.us-gov.crowdstrike.com'
  ];

  setupMessageHandler() {
    window.addEventListener('message', (event) => {
      if (!this.allowedOrigins.includes(event.origin)) {
        console.warn('Rejected message from unauthorized origin:', event.origin);
        return;
      }

      if (!this.isValidMessage(event.data)) {
        console.warn('Rejected invalid message structure');
        return;
      }

      this.handleSecureMessage(event.data);
    });
  }

  private isValidMessage(data: any): boolean {
    return (
      data &&
      typeof data.type === 'string' &&
      data.type.length < 50 &&
      typeof data.payload === 'object'
    );
  }
}
```

## Secure Function Structure (Python)

```python
import os
import json
from typing import Dict, Any

def validate_environment():
    """Validate runtime environment security"""
    required_vars = ['FALCON_CLIENT_ID', 'FOUNDRY_FUNCTION_ID']
    missing = [var for var in required_vars if not os.environ.get(var)]

    if missing:
        raise RuntimeError(f"Missing required environment variables: {missing}")

def main(event: Dict[str, Any]) -> Dict[str, Any]:
    """Main function handler with security controls"""

    try:
        validate_environment()

        if not isinstance(event, dict):
            return {"error": "Invalid input format", "status": 400}

        if len(str(event)) > 10000:  # 10KB limit
            return {"error": "Input too large", "status": 413}

        result = process_event_safely(event)
        return {"data": result, "status": 200}

    except Exception as e:
        print(f"Function error: {type(e).__name__}")
        return {"error": "Internal error", "status": 500}
```

## Role-Based Collection Access (Python)

```python
from typing import List, Dict, Optional, Any

class SecureCollectionAccess:
    def __init__(self, user_context: Dict[str, Any]):
        self.user_id = user_context.get('user_id')
        self.roles = user_context.get('roles', [])

    def read_incidents(self, filters: Optional[Dict] = None) -> List[Dict]:
        """Read incidents with role-based filtering"""
        if 'incident_reader' not in self.roles:
            raise PermissionError("Insufficient permissions for incident data")

        security_filters = self._get_security_filters()
        if filters:
            filters.update(security_filters)
        else:
            filters = security_filters

        results = self.collection.query(filters, limit=100)
        return self._sanitize_results(results)

    def _get_security_filters(self) -> Dict[str, Any]:
        if 'admin' in self.roles:
            return {}
        elif 'analyst' in self.roles:
            return {'severity': {'$gte': 3}}
        else:
            return {'severity': {'$gte': 5}}
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

## Token Lifecycle Management (Python)

```python
import os
from falconpy import OAuth2

def get_secure_client():
    # Environment-based credentials (NEVER hardcode)
    client_id = os.environ.get('FALCON_CLIENT_ID')
    client_secret = os.environ.get('FALCON_CLIENT_SECRET')

    if not client_id or not client_secret:
        raise ValueError("Missing required OAuth credentials")

    # Auto-detect cloud region
    auth = OAuth2(
        client_id=client_id,
        client_secret=client_secret
    )

    # Validate token before use
    if not auth.token():
        raise RuntimeError("Failed to authenticate with Falcon API")

    return auth
```

## Multi-Environment Security

```yaml
# manifest.yml - Environment-specific configurations
environments:
  development:
    oauth_scopes: ["alerts:read", "hosts:read"]  # Read-only for dev
  production:
    oauth_scopes: ["alerts:read", "alerts:write", "hosts:read"]  # Minimal required
```

## Local Development Security

```bash
# .env.development - Local security practices
# Use separate dev credentials (limited scope)
FALCON_CLIENT_ID=<API_CLIENT_ID>
FALCON_CLIENT_SECRET=<API_CLIENT_SECRET>

# Local server security
FOUNDRY_UI_HOST=localhost
FOUNDRY_UI_PORT=3000
FOUNDRY_UI_HTTPS=true  # Always use HTTPS locally

# Database security
DB_CONNECTION_TIMEOUT=5000
DB_MAX_CONNECTIONS=10

# Logging security (no sensitive data)
LOG_LEVEL=INFO
LOG_SENSITIVE_DATA=false
```

## CSP Headers for UI Pages (Supplementary TypeScript)

```typescript
// Vue/React app security headers
const securityHeaders = {
  'Content-Security-Policy': [
    "default-src 'self'",
    "script-src 'self' 'unsafe-inline'",  // Avoid if possible
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' data: https:",
    "connect-src 'self' https://api.crowdstrike.com",
    "frame-ancestors 'self' https://falcon.crowdstrike.com"
  ].join('; '),
  'X-Frame-Options': 'SAMEORIGIN',
  'X-Content-Type-Options': 'nosniff'
};
```

## Secure Manifest Settings (Full Example)

```yaml
# manifest.yml - Security-first configuration
app:
  name: "my-security-app"
  version: "1.0.0"

# Minimal OAuth scopes
oauth_scopes:
  - "alerts:read"
  - "hosts:read"

# UI Security settings
ui:
  pages:
    - path: "/dashboard"
      csp:
        default_src: "'self'"
        script_src: "'self'"
        connect_src: "'self' https://api.crowdstrike.com"

  extensions:
    - name: "alert-widget"
      sandbox: "allow-scripts allow-same-origin"

# Function runtime constraints
functions:
  - name: "process-alerts"
    language: "python"
    path: "functions/process-alerts"
    max_exec_duration_seconds: 30  # Prevent DoS
    max_exec_memory_mb: 128        # Limit resource usage
    environment_variables:
      PYTHON_PATH: "/opt/app"      # Restricted paths
    handlers:
      - name: process
        method: POST
        path: "/api/alerts/process"

# Collection access controls
collections:
  - name: "incident-data"
    read_only: true  # Prevent accidental writes
    ttl: 86400      # Auto-expire sensitive data
```

## Iframe Sandboxing for UI Extensions

```html
<!-- UI Extension - Secure iframe setup -->
<iframe
    src="https://your-extension.com"
    sandbox="allow-scripts allow-same-origin"
    allow="clipboard-read; clipboard-write"
    referrerpolicy="strict-origin-when-cross-origin"
    loading="lazy">
</iframe>
```

## Common Security Antipatterns

**Avoid these patterns:**

```yaml
# Too broad OAuth scopes
oauth_scopes: ["*:*", "alerts:*", "hosts:*"]

# Insecure CSP
csp: "default-src *; script-src * 'unsafe-eval' 'unsafe-inline'"

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

- **OAuth token caching:** Cache tokens securely to reduce API calls
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
