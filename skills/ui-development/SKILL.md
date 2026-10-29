---
name: ui-development
description: Build UI pages and extensions for Falcon Foundry apps using React or Vue with the Shoelace design system and Foundry-JS. TRIGGER when user asks to "create a UI page", "build a UI extension", "add a Shoelace component", "call an API from the UI", runs `foundry ui pages create` or `foundry ui run`, or needs help with Vite config, Foundry-JS, or Falcon console theming. DO NOT TRIGGER for backend functions, workflow YAML, or collection schemas.
version: 1.6.0
updated: 2026-10-01
tags: [foundry, ui, react, vue, shoelace]
author: CrowdStrike
license: MIT
compatibility: Claude Code >=1.0
metadata:
  category: frontend
---

# Foundry UI Development

> Build UI with Shoelace components using the `falcon-shoelace` theme (not vanilla Shoelace or raw HTML), and load both the dark and light theme stylesheets so it matches the Falcon console. Use `foundry ui run` for live development, and apply the iframe security patterns to every extension.

> **Part of a suite.** If `development-workflow` has not already run, and this is a new app or its first capability, load the `development-workflow` skill first — it owns the CLI prerequisite check, scaffolding order, and manifest coordination.

Falcon Foundry UI pages and extensions use React or Vue with the Shoelace design system (Falcon-themed) and Foundry-JS for platform integration.

## Pages vs Extensions

If the user doesn't specify page or extension, **ask which they prefer** before scaffolding. Present this table to help them decide:

| | UI Pages | UI Extensions |
|---|---|---|
| **What** | Standalone applications | Console-embedded components |
| **Where** | Full-page view in Falcon console | Sidebar widget in detection/host/incident pages |
| **Sockets** | N/A | One per extension (see socket table below) |
| **Use when** | Complex interactions, multiple views, dashboards | Contextual enrichment, quick-glance data |
| **Framework** | Vue, React, or Vanilla JS | Vue, React, or Vanilla JS |

## CLI Scaffolding

```bash
# Create a React page
foundry ui pages create --name "my-page" --description "Page description" --from-template React --homepage --no-prompt

# Create a Vanilla JS page (no npm install or build step needed)
foundry ui pages create --name "my-page" --description "Page description" --from-template "Vanilla JS" --homepage --no-prompt

# Add navigation entry (separate step — --no-prompt skips this during page creation)
foundry ui navigation add --name "My Page" --path / --ref pages.my-page

# Create an extension targeting a console socket
# REQUIRED: --sockets must be specified — omitting it launches an interactive picker that hangs with Error: EOF
# REQUIRED: Use ONLY values from the Extension Socket Locations table below — do NOT guess socket IDs
foundry ui extensions create --name "my-ext" --description "Description" --from-template React --sockets "activity.detections.details" --no-prompt

# Create a Vanilla JS extension (no npm install or build step needed)
foundry ui extensions create --name "my-ext" --description "Description" --from-template "Vanilla JS" --sockets "activity.detections.details" --no-prompt
```

**Vanilla JS** needs no `npm install` or `npm run build`. The importmap loads foundry-js from CDN. Use it for simple extensions that display data or make API calls without complex state management. Deploy works with just the raw `src/` files.

> **`--homepage` / `homepage:` is not a navigation link.** It sets the app's root page only and doesn't add a side-menu entry. Only `ui.navigation.links` (via `foundry ui navigation add`) creates a menu item, so an app can be reachable at root yet absent from the menu. Add a nav link for every page you want listed.

The blueprint output is deterministic — see [references/blueprint-templates.md](references/blueprint-templates.md) for exact file contents, Shoelace import patterns, and API integration calling examples.

**Editing a React blueprint:** put the UI in `src/routes/home.jsx`, which gets `falcon` from `useContext(FalconApiContext)` (imported from `../contexts/falcon-api-context`). The other scaffolded files (`app.jsx`, `index.html`, the context, `package.json`, `vite.config.js`, `styles.css`, `routes/about.jsx`, the `components/`) work as generated, so you don't need to read them first. Import Shoelace React wrappers from `@shoelace-style/shoelace/dist/react` (for example, `import { SlButton, SlSpinner } from "@shoelace-style/shoelace/dist/react";`).

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
setBasePath('https://cdn.jsdelivr.net/npm/@shoelace-style/shoelace@2.20.1/cdn/'); // the version in package.json
```

Use design tokens instead of hardcoded colors so the UI follows the console's light and dark mode. Colors come from the Toucan tokens in `@crowdstrike/tailwind-toucan-base` (the React blueprint loads its `index.css`); falcon-shoelace defines `--sl-spacing-*` but no global `--sl-color-*` or `--sl-border-radius-*` tokens, so those resolve to nothing:

```css
.my-component {
  color: var(--titles-and-attributes);
  background: var(--surface-md);
  border: 1px solid var(--border-reg);
  padding: var(--sl-spacing-medium);
}
```

For extended Shoelace component catalog and CSS customization, see [references/shoelace-reference.md](references/shoelace-reference.md).

For theming, dark/light mode switching, and design token values, see [references/falcon-theming.md](references/falcon-theming.md).

## Foundry-JS

```javascript
import FalconApi from '@crowdstrike/foundry-js';

const falcon = new FalconApi();
await falcon.connect();   // MUST resolve before any SDK call; also applies the console theme
```

There is no `falcon.theme()` method. `connect()` puts `theme-light` or `theme-dark` on `<html>` (also in `falcon.data.theme`) and swaps it on every `data` message. `@crowdstrike/falcon-shoelace` styles off those same classes, so Shoelace components follow the console with no theme code; only your own CSS keyed off something else needs to react (listen for `falcon.events.on('data', …)` or a `MutationObserver` on the `<html>` class).

> **⚠️ `connect()` is async.** In React, call it inside a `useEffect`, gate child rendering on an `isInitialized` state (NOT `falcon.isConnected`, which isn't reactive), and access `falcon.navigation` only after it resolves. Full `FalconApiProvider` pattern: [references/react-patterns.md](references/react-patterns.md).

Per-API usage lives in [references/foundry-js.md](references/foundry-js.md): API integrations (+ the `got string want integer` parameter-type gotcha), collections CRUD, on-demand workflow execute/poll, cloud functions (invoke by `name` not `id`, so it survives a clone), LogScale, and events. Full component examples: [references/react-patterns.md](references/react-patterns.md) and [references/vue-patterns.md](references/vue-patterns.md).

## Development Servers

- **`foundry ui run`**: Serves only the UI in Falcon console dev mode (port 25678). Use during UI-focused development.
- **`foundry apps run`**: Starts the full app locally (validates manifest on startup). Use when testing UI + functions + integrations together.

**CRITICAL: Run from the app root directory.** Both `foundry ui run` and `foundry apps run` resolve manifest paths relative to `os.Getwd()`. After `cd`-ing into a UI page/extension directory for `npm install && npm run build`, always `cd` back to the app root before running any `foundry` app commands. Running from a subdirectory causes "file not found" or doubled-path errors.

If the UI calls API integrations, collections, or functions, deploy those backend capabilities first via `foundry apps deploy`. `foundry ui run` only serves UI assets locally — backend capabilities resolve from the cloud.

### Development Mode vs Preview Mode

Toggle via the **Developer tools** (`</>`) icon in the Falcon console toolbar:

| Feature | Development Mode | Preview Mode |
|---------|-----------------|--------------|
| Activation | `foundry ui run` + enable in Developer tools | Deploy, then enable in Developer tools |
| Source | Local build from your machine (polls localhost:25678) | Deployed build in the cloud |
| Purpose | Live UI iteration with hot reload | Test deployed UI before release |

Only one mode at a time. Disable one before enabling the other.

## Sandboxed Iframe Restrictions

Pages and extensions run in an iframe sandboxed with `allow-scripts allow-forms allow-downloads` only:

- **No `allow-same-origin`:** `localStorage`, `sessionStorage`, `document.cookie`, and `indexedDB` throw `SecurityError`. Keep state in memory or a collection.
- **No `allow-modals`:** `alert()`, `confirm()`, `prompt()`, and `beforeunload` prompts are silently ignored — `confirm()` returns `false`. Show errors inline and confirm with `<sl-dialog>`.
- **Page lifetime:** a loop over many items stops starting new calls when the user leaves. Save per item, make re-runs resume, or move the loop into a workflow.

See [references/sandboxed-iframe.md](references/sandboxed-iframe.md) for the errors, a storage fallback, and a resumable bulk-processing pattern.

## Iframe Communication

foundry-js owns the channel to the console: `connect()` records the console's origin and sends every later message there, never to `'*'`. Don't add your own `postMessage` calls or `message` listeners. Read console context with `falcon.events.on('data', …)` and talk to other extensions of the same app with `falcon.sendBroadcast()` plus `falcon.events.on('broadcast', …)` ([foundry-js.md](references/foundry-js.md#events-inter-extension-communication)).

## Extension Socket Locations

Run `foundry ui extensions list-sockets` to get the current list of available sockets. Use the **technical ID** (not human-readable name) with `--sockets`. The extension renders in the detail panel reached by the navigation below — open an individual record (detection, case, host, lead, or execution) to see it.

| Display Name | Technical ID for `--sockets` | Console Navigation |
|-------------|------------------------------|--------------------|
| Endpoint detection details | `activity.detections.details` | Endpoint security › Monitor › Endpoint detections |
| Identity detection details | `identity.detections.details` | Identity protection › Detections |
| Next-Gen SIEM cases panel | `xdr.cases.panel` | Next-Gen SIEM › Cases |
| Next-Gen SIEM cases details | `xdr.cases.details` | Next-Gen SIEM › Cases › open a case (details section; CLI 2.1.2+) |
| Next-Gen SIEM workbench details | `ngsiem.workbench.details` | Next-Gen SIEM › Cases › open a case › workbench graph canvas › click a node |
| Host management host details | `hosts.host.panel` | Host setup and management › Host management |
| Automated leads details | `automated-leads.leads.details` | Next-Gen SIEM › Automated leads |
| Workflow execution details | `workflows.executions.execution.details` | Fusion SOAR › Workflows › open an execution |

## Common Pitfalls

> **Note:** The first four pitfalls below, about the UI subdirectory, `npm install`, manifest paths, and `vite.config.js`, apply to the React template only. Vanilla JS extensions have no build step — deploy the raw `src/` files directly.

- **Running `foundry` commands from a UI subdirectory.** After `cd ui/extensions/my-ext && npm install && npm run build`, you MUST `cd` back to the app root before running `foundry apps validate`, `foundry apps deploy`, or `foundry ui run`. The CLI resolves manifest paths relative to cwd — running from a subdirectory produces doubled paths like `ui/extensions/my-ext/ui/extensions/my-ext/src/dist/index.html`.
- **`npm install` fails `E401`.** The registry npm is pointed at needs credentials. Configure the registry and its auth token in the page's `.npmrc` (or run `npm config set registry <url>` and log in), then rerun `npm install`.
- **NEVER edit manifest.yml `path` or `entrypoint` values.** The CLI sets these correctly. The format `ui/extensions/my-ext/src/dist/index.html` is NOT a doubled path — it is correct. If you see a deploy path error, you likely changed `vite.config.js` — revert your changes.
- **NEVER modify `vite.config.js`.** The blueprint is turnkey. Do not change `base: './'` to `''` or anything else. Do not change `root: 'src'`. Do not remove `noAttr()`. Just edit your React/JS code and deploy.
- **Hardcoding page or function IDs.** After an app clone Foundry re-mints every page/function id, so hardcoded `cloudFunction({id})` or `SETTINGS_PAGE_ID`/`DASH_PAGE_ID` constants silently target the ORIGINAL app — function probes return `error`/`[object Object]`, nav buttons jump to the old app. Invoke functions by `name`, and open modals by `name` with `falcon.ui.openModal({ type: 'page', name }, title)`. Navigation paths still need a page ID (`/foundry/page/<id>`), and foundry-js has no call that looks one up by name, so keep those IDs in one constants file and update it from the new `manifest.yml` after a clone.
- **Cross-page navigation with `type: 'internal'`.** Each Foundry page is a separate SPA; `navigation.navigateTo({ type: 'internal' })` routes WITHIN the current SPA and silently falls back to its home (the "Settings button just reloads the dashboard" bug). Use `type: 'falcon'` with a RELATIVE path (`/foundry/page/<id>`). The console's `new URL(path)` throws `Invalid URL` on a relative path — but navigation still works, so that console error is cosmetic; do NOT "fix" it by passing an absolute URL, which forces the page to open in a NEW TAB (worse UX).
- **Omitting `--sockets` on extension create.** This launches an interactive picker that hangs with `Error: EOF`. Always provide `--sockets "socket.id"` on the command line. Run `foundry ui extensions list-sockets` to see available sockets — do not guess or fabricate socket names.
- **Importing vanilla Shoelace themes.** Use `@crowdstrike/falcon-shoelace` for Falcon console styling.
- **Loading only light theme.** The Falcon console supports dark mode — users see broken styling without both themes.
- **Hardcoding colors.** Use Toucan tokens (`var(--titles-and-attributes)`, `var(--critical)`) so the UI adapts to theme changes. falcon-shoelace defines no global `--sl-color-*` tokens.
- **Expecting backend to work with `foundry ui run`.** The dev server only serves UI — deploy backend capabilities first.
- **Using `sl-badge` or `sl-tag` for status.** falcon-shoelace doesn't style them, so every variant looks the same. Also: `sl-option` values can't hold spaces, `sl-radio-group` gets two tab stops, and dialog events bubble from children. See [shoelace-reference](references/shoelace-reference.md#components-falcon-shoelace-doesnt-style).
- **Using Tailwind arbitrary values with prebuilt toucan CSS.** Values like `max-h-[400px]` require JIT compilation. Use inline styles instead when using the prebuilt `tailwind-toucan-base/index.css`.
- **Quoting numeric query parameters.** `execute()` accepts `Record<string, unknown>`, so `limit: '25'` passes type-checking and fails server-side with `got string want integer`. Match the `schema.type` declared in the OpenAPI spec — the extension still renders, so this reads as an API error rather than a code bug.
- **Reading `localStorage` or `sessionStorage`.** The sandbox lacks `allow-same-origin`, so any access throws a `SecurityError` (see [Sandboxed Iframe Restrictions](#sandboxed-iframe-restrictions)). Use in-memory state or a collection; wrap legacy calls in `try/catch`.
- **Reporting errors with `alert()` or guarding actions with `confirm()`.** The sandbox lacks `allow-modals`, so both are silently ignored: errors vanish and `confirm()`-guarded actions never run. Use inline errors and `<sl-dialog>`.
- **Serving icons from `dist/`.** The default CSP already allows `cdn.jsdelivr.net` and `data:`, so the `setBasePath()` above needs no manifest change. Deploy drops `.svg` files and `connect-src` blocks the app's own host, so a local icon path fails. Inline custom SVGs ([falcon-theming](references/falcon-theming.md#shoelace-icons-and-the-csp)).

## Reading Guide

| Task | Reference |
|------|-----------|
| Blueprint file contents, editing strategy | [references/blueprint-templates.md](references/blueprint-templates.md) |
| Shoelace component catalog, CSS customization | [references/shoelace-reference.md](references/shoelace-reference.md) |
| Dark/light theming, design tokens | [references/falcon-theming.md](references/falcon-theming.md) |
| React component examples | [references/react-patterns.md](references/react-patterns.md) |
| Vue component examples | [references/vue-patterns.md](references/vue-patterns.md) |
| Foundry-JS: workflows, LogScale, cloud functions, collections CRUD | [references/foundry-js.md](references/foundry-js.md) |
| Sandbox restrictions (storage, modals), long-running page loops | [references/sandboxed-iframe.md](references/sandboxed-iframe.md) |
| Framework selection, console messaging, Extension Builder, CSP, dev server coordination | [references/advanced-patterns.md](references/advanced-patterns.md) |

## Use Cases

For real-world implementation patterns, see:
- `use-cases/detection-enrichment.md` — UI extensions for detection enrichment
- `use-cases/first-app.md` — Getting started with Foundry apps

## Reference Implementations

- **[foundry-sample-foundryjs-demo](https://github.com/CrowdStrike/foundry-sample-foundryjs-demo)**: Comprehensive Foundry-JS demo (API integrations, collections, workflows, LogScale, cloud functions, events, navigation, modals)
- **[foundry-sample-mitre](https://github.com/CrowdStrike/foundry-sample-mitre)**: Vue shared components, multi-view app
- **[foundry-sample-collections-toolkit](https://github.com/CrowdStrike/foundry-sample-collections-toolkit)**: UI for collections
- **[foundry-sample-functions-python](https://github.com/CrowdStrike/foundry-sample-functions-python)**: UI calling functions
- **[foundry-sample-logscale](https://github.com/CrowdStrike/foundry-sample-logscale)**: Vanilla JS + foundry-js page
- **[foundry-sample-detection-translation](https://github.com/CrowdStrike/foundry-sample-detection-translation)**: Detection context UI extension
