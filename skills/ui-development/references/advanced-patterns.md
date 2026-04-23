# Advanced UI Patterns

## Framework Selection

### When to Use Vue.js
- Simpler component structure preferred
- Team familiar with Vue ecosystem
- Smaller bundle size requirements
- Progressive enhancement patterns

### When to Use React
- Complex state management needs
- Team familiar with React ecosystem
- Integration with existing React libraries
- Advanced hook patterns required

**Both frameworks work equally well with Foundry.** Choose based on team expertise.

## UI Component Types

### UI Pages (Standalone Applications)
- Technology selection: Vue vs React guidance
- Shoelace design system integration
- Foundry-JS SDK authentication patterns
- Vite build system configuration

### UI Extensions (Console-Embedded Components)
- Extension point targeting
- Iframe communication patterns
- Context data integration from Falcon console
- Performance and size constraints

## Development Server Coordination

### Running foundry ui run

**CRITICAL:** `foundry ui run` serves UI assets locally but backend capabilities (API integrations, collections, functions) are resolved from the cloud. If your UI calls any of these, deploy the app first with `foundry apps deploy`.

**Always run `foundry apps deploy` from the project root directory.** Manifest paths for UI pages are relative to the project root. Running deploy from a subdirectory can cause path doubling errors like `/project/ui/pages/name/ui/pages/name/src/dist/index.html`.

```bash
# For apps with backend dependencies: deploy first, then iterate on UI
foundry apps deploy --change-type Patch --change-log "Initial deployment" --no-prompt
foundry ui run

# For pure UI work (no API integration/collection/function calls): no deploy needed
foundry ui run

# Expected output:
# ✓ Development server started
# ✓ Serving UI at http://localhost:3000
# ✓ Watching for changes...
```

**Pattern: Development Workflow**

```bash
# 1. Start the development server
foundry ui run --port 3000

# 2. In another terminal, run your build watcher
npm run dev

# 3. Enable development mode in Falcon console:
#    Settings → Foundry Apps → Enable Development Mode

# 4. Access your app in Falcon console
#    The console will serve your local build instead of deployed version
```

### Server State Management

**Pattern: Checking Server Status**

```bash
# Check if server is running
ps aux | grep "foundry ui"

# Check port availability
netstat -tlnp | grep :3000

# Restart server if needed
pkill -f "foundry ui" && foundry ui run
```

### Handling Permission Errors

When `foundry ui run` shows permission errors:

1. **Check manifest.yml OAuth scopes** - Ensure required permissions are declared
2. **Restart the server** - Manifest changes require server restart
3. **Verify authentication** - Run `foundry profile active`

```bash
# Common resolution
foundry ui run
```

## ExtensionMessaging Class

Full TypeScript class for secure parent-extension communication with postMessage origin validation, request/response tracking, and timeout handling:

```typescript
// extension/messaging.ts
interface FoundryMessage {
  type: 'CONTEXT_UPDATE' | 'ACTION_REQUEST' | 'DATA_RESPONSE';
  payload: unknown;
  requestId?: string;
}

class ExtensionMessaging {
  private allowedOrigins = [
    'https://falcon.crowdstrike.com',
    'https://falcon.eu-1.crowdstrike.com',
    'https://falcon.us-gov-1.crowdstrike.com',
  ];

  private pendingRequests = new Map<string, {
    resolve: (value: unknown) => void;
    reject: (reason: unknown) => void;
  }>();

  constructor() {
    window.addEventListener('message', this.handleMessage.bind(this));
  }

  private handleMessage(event: MessageEvent<FoundryMessage>) {
    // SECURITY: Validate origin
    if (!this.allowedOrigins.includes(event.origin)) {
      console.warn('Rejected message from unauthorized origin:', event.origin);
      return;
    }

    // SECURITY: Validate message structure
    if (!this.isValidMessage(event.data)) {
      console.warn('Rejected malformed message');
      return;
    }

    const { type, payload, requestId } = event.data;

    switch (type) {
      case 'CONTEXT_UPDATE':
        this.handleContextUpdate(payload);
        break;
      case 'DATA_RESPONSE':
        if (requestId && this.pendingRequests.has(requestId)) {
          const { resolve } = this.pendingRequests.get(requestId)!;
          this.pendingRequests.delete(requestId);
          resolve(payload);
        }
        break;
    }
  }

  private isValidMessage(data: unknown): data is FoundryMessage {
    return (
      typeof data === 'object' &&
      data !== null &&
      'type' in data &&
      typeof (data as FoundryMessage).type === 'string'
    );
  }

  async requestData<T>(action: string, params?: unknown): Promise<T> {
    const requestId = crypto.randomUUID();

    return new Promise((resolve, reject) => {
      this.pendingRequests.set(requestId, { resolve, reject });

      // Send to parent window
      window.parent.postMessage(
        { type: 'ACTION_REQUEST', payload: { action, params }, requestId },
        '*' // Parent origin validated on response
      );

      // Timeout after 30 seconds
      setTimeout(() => {
        if (this.pendingRequests.has(requestId)) {
          this.pendingRequests.delete(requestId);
          reject(new Error('Request timeout'));
        }
      }, 30000);
    });
  }
}
```

## E2E Testing with Playwright

**Pattern: Testing in Falcon Console Context**

```typescript
// e2e/alerts-dashboard.spec.ts
import { test, expect } from '@playwright/test';
import { loginToFalcon, navigateToApp } from './helpers/falcon-auth';

test.describe('Alerts Dashboard', () => {
  test.beforeEach(async ({ page }) => {
    await loginToFalcon(page);
    await navigateToApp(page, 'my-foundry-app');
  });

  test('displays alerts from API', async ({ page }) => {
    // Wait for data to load
    await expect(page.locator('sl-spinner')).not.toBeVisible({ timeout: 10000 });

    // Verify table is populated
    const rows = page.locator('tbody tr');
    await expect(rows).toHaveCount.greaterThan(0);
  });

  test('filters alerts by severity', async ({ page }) => {
    await page.selectOption('sl-select[name="severity"]', '8');
    await page.click('sl-button[type="submit"]');

    // Verify only high severity alerts shown
    const badges = page.locator('sl-badge');
    for (const badge of await badges.all()) {
      const text = await badge.textContent();
      expect(parseInt(text || '0')).toBeGreaterThanOrEqual(8);
    }
  });
});
```

## Extension Builder (No-Code)

The Extension Builder provides a drag-and-drop alternative to CLI-based UI development. Use it for simple extensions that display contextual data without custom logic.

### Extension Builder vs CLI Feature Comparison

| Feature | Extension Builder | CLI (Vue/React) |
|---------|------------------|-----------------|
| UI pages | No | Yes |
| UI extensions | Yes (single socket) | Yes (multiple sockets) |
| Action triggers | No | Yes |
| Dev mode preview | No | Yes |
| Dashboards/Charts | No | Yes |
| Queries/Collections | No | Yes |
| Import/Export | No | Yes |
| Custom JavaScript | No | Yes |
| Components | Container, Text, Label Value | Unlimited (Shoelace + custom) |

**When to use Extension Builder vs. CLI:**
- **Extension Builder**: Simple data display, contextual enrichment, no custom JavaScript needed
- **CLI (Vue/React)**: Complex interactions, custom state management, multiple views, shared components

> **Extension Builder limitation:** Only one socket per extension. CLI-based extensions support multiple sockets per extension.

**Extension Builder capabilities:**
- **Visual canvas**: Drag-and-drop Container, Text, and Label Value components
- **Contextual data binding**: Access detection/host data via `${contextual.device.external_ip}`, `${contextual.detection.severity}`, etc.
- **API integration**: Connect to CrowdStrike or third-party APIs directly from the builder
- **No deployment needed**: Extensions are live after saving in the Foundry UI

**Example: Binding contextual data**

When building an extension for the detection detail page, the builder provides contextual variables:
- `${contextual.device.external_ip}` - Device external IP
- `${contextual.device.hostname}` - Device hostname
- `${contextual.detection.severity}` - Detection severity score

These variables are passed as parameters to API integrations configured in the builder.

## CSP Configuration in Manifest

For UI pages that need to load external resources, configure Content Security Policy in the manifest:

```yaml
ui:
  pages:
    - name: my-page
      csp:
        connect_src:
          - "'self'"
          - "https://api.example.com"
        img_src:
          - "'self'"
          - "data:"
          - "https://images.example.com"
```

## Additional Reference Implementations

- **[foundry-sample-rapid-response](https://github.com/CrowdStrike/foundry-sample-rapid-response)**: Rapid response UI with TypeScript
- **[foundry-sample-category-blocking](https://github.com/CrowdStrike/foundry-sample-category-blocking)**: Category blocking UI (JavaScript)
- **[foundry-sample-charlotte-toolkit](https://github.com/CrowdStrike/foundry-sample-charlotte-toolkit)**: Charlotte AI toolkit UI
- See also: [Enrich Detections with Falcon Foundry Extension Builder](https://www.crowdstrike.com/tech-hub/ng-siem/enrich-detections-with-falcon-foundry-extension-builder/)

## Counter-Rationalizations Table

| Your Excuse | Reality |
|-------------|---------|
| "I can use raw HTML instead of Shoelace" | Shoelace ensures Falcon design consistency and accessibility |
| "I'll style components myself" | Custom styles break when Falcon updates; use design tokens |
| "foundry ui run is optional" | Dev server is REQUIRED for testing in console |
| "I can test API integration calls before deploying" | `foundry ui run` only serves UI locally — API integrations, collections, and functions must be deployed to the cloud first via `foundry apps deploy` |
| "I can test without mocking Foundry SDK" | Real API calls in tests are slow, flaky, and environment-dependent |
| "Iframe security is handled by the platform" | Extensions MUST validate message origins; platform provides the sandbox, you secure the communication |
| "React/Vue patterns are transferable" | Foundry-JS SDK and Shoelace have specific integration patterns |
| "I'll use the default Shoelace theme" | Vanilla Shoelace doesn't match Falcon console styling; `falcon-shoelace` is required for visual consistency and dark/light mode support |
| "Dark mode support can come later" | The Falcon console ships with dark mode. Users see broken styling on day one if you skip it |

## Red Flags - STOP Immediately

If you catch yourself:
- Removing `noAttr()` or `base: './'` from the scaffolded vite.config.js (causes blank page)
- Using raw `<button>` instead of `<sl-button>`
- Importing `@shoelace-style/shoelace/dist/themes/light.css` instead of `@crowdstrike/falcon-shoelace`
- Loading only light theme without dark theme support
- Hardcoding color values (e.g., `#ffffff`, `#1a1a1a`) instead of design tokens
- Skipping `foundry ui run` during development
- Running `foundry ui run` and expecting API integrations/collections/functions to work without deploying first (backend lives in the cloud)
- Not validating postMessage origins in extensions
- Hardcoding API endpoints instead of using Foundry SDK
- Testing without mocking the Foundry SDK

**STOP. Follow the patterns above. No shortcuts.**

## Integration with Other Skills

- **development-workflow:** UI is delegated from the orchestrator
- **collections-development:** UI consumes generated TypeScript types from schemas
- **functions-development:** UI calls function endpoints via Foundry SDK
- **security-patterns:** Apply XSS prevention and CSP patterns (see that skill)
- **debugging-workflows:** Use for `foundry ui run` startup issues
