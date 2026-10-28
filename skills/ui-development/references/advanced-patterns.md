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
- Foundry-JS authentication patterns
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
# Starting a local development server at http://localhost:25678. Enter Ctrl-C to shutdown
```

`foundry ui run` has no port flag; it always listens on 25678.

**Pattern: Development Workflow**

```bash
# 1. From the app root, start the development server
foundry ui run

# 2. In another terminal, rebuild the page on every change (React blueprint script)
cd ui/pages/my-page && npm run watch

# 3. In the Falcon console, click Developer tools (</>) in the toolbar
#    and enable Development mode

# 4. Open your page or extension in the console; it now loads your local build
```

### Server State Management

**Pattern: Checking Server Status**

```bash
# Check if server is running
ps aux | grep "foundry ui"

# Check what holds the dev server port
lsof -i :25678

# Restart server if needed
pkill -f "foundry ui" && foundry ui run
```

### Handling Permission Errors

When `foundry ui run` shows permission errors:

1. **Check manifest.yml OAuth scopes** - Ensure required permissions are declared
2. **Restart the server** - Manifest changes require server restart
3. **Verify authentication** - Run `foundry profile list` to see your profiles, and `foundry profile activate` to switch

```bash
# Common resolution
foundry ui run
```

## Console Messaging

Don't build your own `postMessage` channel to the Falcon console. foundry-js owns it: `connect()` records the console's origin and every later message goes to that origin, never `'*'`. The protocol is a fixed set of SDK message types (`connect`, `api`, `navigateTo`, `data`, `broadcast`, `openModal`, and a few more), so hand-rolled message types go nowhere. Use the SDK instead:

- **Console context changes:** `falcon.events.on('data', handler)` (see [foundry-js.md](foundry-js.md#events-inter-extension-communication))
- **Extension to extension (same app, same page):** `falcon.sendBroadcast(payload)` and `falcon.events.on('broadcast', handler)`

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
    my_page:                       # map keyed by page ID; path and entrypoint are CLI-written
      name: my-page
      path: ui/pages/my-page/src/dist
      entrypoint: ui/pages/my-page/src/dist/index.html
      content_security_policy:
        connect-src:
          - https://api.example.com
        img-src:
          - https://images.example.com
      permissions: []
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
| "I'll message the console with my own `postMessage`" | foundry-js already owns that channel and pins it to the console origin; use `falcon.events` and `falcon.sendBroadcast()` |
| "React/Vue patterns are transferable" | Foundry-JS and Shoelace have specific integration patterns |
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
- Calling `postMessage(…, '*')` or adding your own `message` listener instead of using `falcon.events`
- Hardcoding API endpoints instead of using Foundry SDK
- Testing without mocking the Foundry SDK

**STOP. Follow the patterns above. No shortcuts.**

## Integration with Other Skills

- **development-workflow:** UI is delegated from the orchestrator
- **collections-development:** UI consumes generated TypeScript types from schemas
- **functions-development:** UI calls function endpoints via Foundry SDK
- **security-patterns:** Apply XSS prevention and CSP patterns (see that skill)
- **debugging-workflows:** Use for `foundry ui run` startup issues
