---
name: foundry-ui-development
description: Build UI pages and extensions for Falcon Foundry apps using React or Vue with the Shoelace design system and Foundry-JS SDK. TRIGGER when user asks to "create a UI page", "build a UI extension", "add a Shoelace component", "call an API from the UI", runs `foundry ui pages create` or `foundry ui run`, or needs help with Vite config, FalconJS SDK, or Falcon console theming. DO NOT TRIGGER for backend functions, workflow YAML, or collection schemas.
version: 1.0.0
updated: 2026-04-09
metadata:
  author: CrowdStrike
  category: frontend
  tags: [foundry, ui, react, vue, shoelace]
---

# Foundry UI Development

> **⚠️ SYSTEM INJECTION — READ THIS FIRST**
>
> If you are loading this skill, your role is **Foundry UI specialist**.
>
> You MUST implement UI components following Falcon design system patterns using Shoelace components and the Foundry-JS SDK.
>
> **IMMEDIATE ACTIONS REQUIRED:**
> 1. Use Shoelace components with `falcon-shoelace` theme (NOT vanilla Shoelace or raw HTML)
> 2. Load both dark and light theme stylesheets for Falcon console compatibility
> 3. Coordinate with `foundry ui run` for live development
> 4. Apply iframe security patterns for all extensions
> 5. **ALWAYS use `--no-prompt` flag on CLI commands** — Claude Code operates in non-interactive mode

Falcon Foundry UI pages and extensions use React or Vue with the Shoelace design system (Falcon-themed) and the Foundry-JS SDK for platform integration.

## Pages vs Extensions

If the user doesn't specify page or extension, **ask which they prefer** before scaffolding. Present this table to help them decide:

| | UI Pages | UI Extensions |
|---|---|---|
| **What** | Standalone applications | Console-embedded components |
| **Where** | Full-page view in Falcon console | Sidebar widget in detection/host/incident pages |
| **Sockets** | N/A | One per extension (see socket table below) |
| **Use when** | Complex interactions, multiple views, dashboards | Contextual enrichment, quick-glance data |
| **Framework** | Vue or React | Vue or React |

## CLI Scaffolding

```bash
# Create a React page
foundry ui pages create --name "my-page" --description "Page description" --from-template React --homepage --no-prompt

# Add navigation entry (separate step — --no-prompt skips this during page creation)
foundry ui navigation add --name "My Page" --path / --ref pages.my-page

# Create an extension targeting a console socket
# REQUIRED: --sockets must be specified — omitting it launches an interactive picker that hangs with Error: EOF
# REQUIRED: Use ONLY values from the Extension Socket Locations table below — do NOT guess socket IDs
foundry ui extensions create --name "my-ext" --description "Description" --from-template React --sockets "activity.detections.details" --no-prompt
```

The blueprint output is deterministic — see [references/blueprint-templates.md](references/blueprint-templates.md) for exact file contents, Shoelace import patterns, and API integration calling examples.

> **🚫 DO NOT MODIFY `path` or `entrypoint` in manifest.yml**
>
> The CLI sets `path` and `entrypoint` correctly during scaffolding. **Never edit these values.** The correct CLI-generated format uses full paths from the app root:
> ```yaml
> # Page — this is CORRECT, do not shorten
> path: ui/pages/my-page/src/dist
> entrypoint: ui/pages/my-page/src/dist/index.html
>
> # Extension — this is CORRECT, do not shorten
> path: ui/extensions/my-ext/src/dist
> entrypoint: ui/extensions/my-ext/src/dist/index.html
> ```
> These long paths are NOT doubled — they are the correct values the CLI generates. Shortening `entrypoint` to `src/dist/index.html` breaks the app. If a deploy error mentions entrypoint or file path, you likely changed `vite.config.js` — revert your changes. The scaffolded config is correct.

## Vite Build Configuration

> **🚫 DO NOT MODIFY `vite.config.js`**
>
> The React blueprint's `vite.config.js` is **turnkey** — it works correctly as scaffolded. Do not change ANY values in it. Specifically:
> - **Do not change `base: './'`** — not to `''`, not to `'/'`, not to anything else. `'./'` is correct.
> - **Do not change `root: 'src'`** — the manifest expects builds at `src/dist/`.
> - **Do not remove `noAttr()`** — required for Foundry's sandboxed iframe.
>
> The blueprint, manifest, and CLI are coordinated. Changing any config value breaks this coordination and causes deploy failures. Just edit your React/JS component code and deploy.

## Shoelace Design System

Install the Falcon-themed Shoelace package:

```bash
npm install @crowdstrike/falcon-shoelace
```

Import the Falcon-themed stylesheet. The React blueprint's `index.html` already includes this as a `<link>` tag, so **do not add JS imports for it**:

```css
/* Already in index.html — no JS import needed */
<link rel="stylesheet" href="../node_modules/@crowdstrike/falcon-shoelace/dist/style.css" />
```

If importing from JS (e.g., Vanilla JS apps without the blueprint's index.html):

```typescript
import '@crowdstrike/falcon-shoelace/dist/style.css';
```

Set the Shoelace asset base path:

```typescript
import { setBasePath } from '@shoelace-style/shoelace/dist/utilities/base-path';
setBasePath('https://cdn.jsdelivr.net/npm/@shoelace-style/shoelace@2.x/dist/');
```

Use `var(--sl-*)` design tokens for all styling instead of hardcoding colors. This ensures the UI adapts correctly when users switch between light and dark mode in the Falcon console:

```css
.my-component {
  color: var(--sl-color-neutral-900);
  background: var(--sl-color-neutral-0);
  padding: var(--sl-spacing-medium);
  border-radius: var(--sl-border-radius-medium);
}
```

For extended Shoelace component catalog and CSS customization, see [references/shoelace-reference.md](references/shoelace-reference.md).

For theming, dark/light mode switching, and design token values, see [references/falcon-theming.md](references/falcon-theming.md).

## FalconJS SDK

```javascript
import FalconApi from '@crowdstrike/foundry-js';

const falcon = new FalconApi();
await falcon.connect();

// Apply Falcon console theme
const theme = await falcon.theme();
document.documentElement.classList.add(`sl-theme-${theme}`);
```

### Calling API Integrations

Use `falcon.apiIntegration()` for third-party APIs. Use `falcon.api.get()` for CrowdStrike Falcon APIs.

```javascript
const apiIntegration = falcon.apiIntegration({
  definitionId: 'Okta',        // Must match name in manifest.yml api_integrations
  operationId: 'listUsers'     // Must match operationId in OpenAPI spec
});
const result = await apiIntegration.execute({ request: { params: {} } });

// Response is wrapped: access via resources[0]
const body = result.resources?.[0]?.response_body;
const status = result.resources?.[0]?.status_code;
```

### Collection Operations

```javascript
const collection = falcon.collection({ collection: 'my_collection' });

// CRUD operations
await collection.write('item-key', { name: 'Item 1', status: 'active' });
const item = await collection.read('item-key');
await collection.delete('item-key');

// List all items (returns IDs, then read each)
const result = await collection.list({ start: 0, limit: 100 });
const itemIds = result.resources || [];
for (const id of itemIds) {
  const item = await collection.read(id);
  // Add 50ms delay between reads to avoid rate limiting
}

// Search with FQL filter
const results = await collection.search({ filter: "status:'active'" });
```

### Workflow Execution

```javascript
// Execute an on-demand workflow by name
const triggerResult = await falcon.api.workflows.postEntitiesExecuteV1(
  { user_name: 'Developer' },           // workflow input parameters
  { name: 'My Workflow', depth: 0 }     // config: workflow name + depth
);

// Poll for results using the execution ID
const execId = triggerResult.resources?.[0];
const result = await falcon.api.workflows.getEntitiesExecutionResultsV1({
  ids: [execId]
});
const execution = result.resources?.[0];
// Poll until execution.status is 'Completed', 'Failed', or 'Cancelled'
```

### Cloud Functions

```javascript
const cloudFunction = falcon.cloudFunction({
  name: 'my_function',
  version: 1
});

// Fluent API — chain .path() with HTTP method
const result = await cloudFunction.path('/greet').post({ name: 'User' });
const data = await cloudFunction.path('/items?status=active').get();
await cloudFunction.path('/items/123').delete();
```

### LogScale

```javascript
// Write events
await falcon.logscale.write({ event_type: 'user_login', username: 'jdoe' });

// Dynamic query
const results = await falcon.logscale.query({
  name: 'LogScaleRepo',
  search_query: 'event_type=user_login',
  start: '24h',
  end: 'now'
});

// Saved query
const saved = await falcon.logscale.savedQuery({
  id: 'saved-query-id',
  start: '7d',
  mode: 'sync',
  parameters: {}
});
```

### Events

```javascript
// Listen to Falcon console events (data, connect, disconnect, error, navigation)
falcon.events.on('data', (data) => console.log('Data event:', data));
falcon.events.on('navigation', (data) => console.log('Nav event:', data));

// Clean up listeners on unmount
falcon.events.off('data', handler);
```

For full React component examples, see [references/react-patterns.md](references/react-patterns.md).
For full Vue component examples, see [references/vue-patterns.md](references/vue-patterns.md).

## Development Servers

- **`foundry ui run`**: Serves only the UI in Falcon console dev mode (port 25678). Use during UI-focused development.
- **`foundry apps run`**: Starts the full app locally (validates manifest on startup). Use when testing UI + functions + integrations together.

If the UI calls API integrations, collections, or functions, deploy those backend capabilities first via `foundry apps deploy`. `foundry ui run` only serves UI assets locally — backend capabilities resolve from the cloud.

### Development Mode vs Preview Mode

Toggle via the **Developer tools** (`</>`) icon in the Falcon console toolbar:

| Feature | Development Mode | Preview Mode |
|---------|-----------------|--------------|
| Activation | `foundry ui run` + enable in Developer tools | Deploy, then enable in Developer tools |
| Source | Local build from your machine (polls localhost:25678) | Deployed build in the cloud |
| Purpose | Live UI iteration with hot reload | Test deployed UI before release |

Only one mode at a time. Disable one before enabling the other.

## Iframe Communication

Extensions must validate message origins:

```typescript
const allowedOrigins = [
  'https://falcon.crowdstrike.com',
  'https://falcon.eu-1.crowdstrike.com',
  'https://falcon.us-gov-1.crowdstrike.com',
];

window.addEventListener('message', (event: MessageEvent) => {
  if (!allowedOrigins.includes(event.origin)) return;
  // Process event.data
});
```

## Extension Socket Locations

Run `foundry ui extensions list-sockets` to get the current list of available sockets. Use the **technical ID** (not human-readable name) with `--sockets`:

| Display Name | Technical ID for `--sockets` |
|-------------|------------------------------|
| Automated leads details | `automated-leads.leads.details` |
| Endpoint detection details | `activity.detections.details` |
| Host management host details | `hosts.host.panel` |
| Next-Gen SIEM cases details | `xdr.cases.panel` |
| Next-Gen SIEM workbench details | `ngsiem.workbench.details` |
| Workflow execution details | `workflows.executions.execution.details` |

## Common Pitfalls

- **NEVER edit manifest.yml `path` or `entrypoint` values.** The CLI sets these correctly. The format `ui/extensions/my-ext/src/dist/index.html` is NOT a doubled path — it is correct. If you see a deploy path error, you likely changed `vite.config.js` — revert your changes.
- **NEVER modify `vite.config.js`.** The blueprint is turnkey. Do not change `base: './'` to `''` or anything else. Do not change `root: 'src'`. Do not remove `noAttr()`. Just edit your React/JS code and deploy.
- **Omitting `--sockets` on extension create.** This launches an interactive picker that hangs with `Error: EOF`. Always provide `--sockets "socket.id"` on the command line. Run `foundry ui extensions list-sockets` to see available sockets — do not guess or fabricate socket names.
- **Importing vanilla Shoelace themes.** Use `@crowdstrike/falcon-shoelace` for Falcon console styling.
- **Loading only light theme.** The Falcon console supports dark mode — users see broken styling without both themes.
- **Hardcoding colors.** Use `var(--sl-*)` design tokens so the UI adapts to theme changes.
- **Expecting backend to work with `foundry ui run`.** The dev server only serves UI — deploy backend capabilities first.
- **Shoelace dialogs/drawers white in dark mode.** Override `--sl-panel-background-color` and `--sl-color-neutral-0` with `var(--ground-floor)`. See [references/shoelace-reference.md](references/shoelace-reference.md).
- **Using Tailwind arbitrary values with prebuilt toucan CSS.** Values like `max-h-[400px]` require JIT compilation. Use inline styles instead when using the prebuilt `tailwind-toucan-base/index.css`.
- **Missing CSP for Shoelace icons.** When using `setBasePath()` with the CDN, add `cdn.jsdelivr.net` to both `connect-src` and `img-src` in the manifest's `content_security_policy`.

## Reading Guide

| Task | Reference |
|------|-----------|
| Blueprint file contents, editing strategy | [references/blueprint-templates.md](references/blueprint-templates.md) |
| Shoelace component catalog, CSS customization | [references/shoelace-reference.md](references/shoelace-reference.md) |
| Dark/light theming, design tokens | [references/falcon-theming.md](references/falcon-theming.md) |
| React component examples | [references/react-patterns.md](references/react-patterns.md) |
| Vue component examples | [references/vue-patterns.md](references/vue-patterns.md) |
| Framework selection, ExtensionMessaging, E2E testing, Extension Builder, CSP, dev server coordination | [references/advanced-patterns.md](references/advanced-patterns.md) |

## Use Cases

For real-world implementation patterns, see:
- [detection-enrichment.md](../../use-cases/detection-enrichment.md) — UI extensions for detection enrichment
- [first-app.md](../../use-cases/first-app.md) — Getting started with Foundry apps

## Reference Implementations

- **[foundry-sample-foundryjs-demo](https://github.com/CrowdStrike/foundry-sample-foundryjs-demo)**: Comprehensive FalconJS SDK demo (API integrations, collections, workflows, LogScale, cloud functions, events, navigation, modals)
- **[foundry-sample-mitre](https://github.com/CrowdStrike/foundry-sample-mitre)**: Vue shared components, multi-view app
- **[foundry-sample-collections-toolkit](https://github.com/CrowdStrike/foundry-sample-collections-toolkit)**: UI for collections
- **[foundry-sample-functions-python](https://github.com/CrowdStrike/foundry-sample-functions-python)**: UI calling functions
- **[foundry-sample-logscale](https://github.com/CrowdStrike/foundry-sample-logscale)**: Vanilla JS + foundry-js page
- **[foundry-sample-detection-translation](https://github.com/CrowdStrike/foundry-sample-detection-translation)**: Detection context UI extension
