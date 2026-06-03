# Foundry-JS Operations

Patterns for `@crowdstrike/foundry-js` beyond the React context/navigation covered in `react-patterns.md`. Source: [Getting Started with foundry-js](https://www.crowdstrike.com/tech-hub/ng-siem/getting-started-with-foundry-js-using-the-foundry-js-demo-app/).

## Connection (Required First)

```typescript
import FalconApi from '@crowdstrike/foundry-js';

const falcon = new FalconApi();
await falcon.connect(); // MUST complete before any SDK calls
```

`connect()` also auto-applies theme class (`theme-dark` or `theme-light`) to `<html>`.

## Collections CRUD

```typescript
// Create a reference (reusable)
const collection = falcon.collection({ collection: 'demo_items' });

// Write
await collection.write({ key: 'item-1', data: { name: 'Test', value: 42 } });

// Read
const item = await collection.read({ key: 'item-1' });

// List/Search with FQL
const results = await collection.search({ filter: "name:'Test'" });

// Delete
await collection.delete({ key: 'item-1' });
```

**Gotcha:** Add 50ms delays between sequential reads to avoid rate limiting in rapid operations.

## API Integrations

Call external APIs configured as API integrations in your app's manifest:

```typescript
const apiIntegration = falcon.apiIntegration({
  definitionId: 'Okta',        // Matches the API integration name in manifest.yml
  operationId: 'listUsers'     // Matches the operationId in the OpenAPI spec
});

const response = await apiIntegration.execute({
  request: { params: {} }      // Pass query/path parameters here
});

// Response structure
const resource = response.resources?.[0];
const statusCode = resource?.status_code;    // HTTP status from the external API
const body = resource?.response_body;         // Parsed response body
```

UI extensions run in sandboxed iframes and cannot make arbitrary HTTP requests. All external API calls must go through `falcon.apiIntegration()`. See [calling-patterns.md](../../api-integrations/references/calling-patterns.md) for calling API integrations from Python and Go functions.

## Workflow Execution (Async Polling)

Workflows are asynchronous — trigger then poll for completion:

```typescript
async function executeWorkflow(falcon: FalconApi, workflowId: string, input: object) {
  // Trigger
  const trigger = await falcon.workflow({ id: workflowId }).execute({ body: input });
  const executionId = trigger.execution_id;

  // Poll (up to 20 attempts, ~1s intervals)
  for (let i = 0; i < 20; i++) {
    await new Promise(resolve => setTimeout(resolve, 1000));
    const status = await falcon.workflow({ id: workflowId }).status({ executionId });

    if (status.state === 'Completed') return status.result;
    if (status.state === 'Failed' || status.state === 'Cancelled') {
      throw new Error(`Workflow ${status.state}: ${status.error || 'unknown'}`);
    }
  }
  throw new Error('Workflow timed out after 20 attempts');
}
```

## LogScale Operations

```typescript
// Write events
await falcon.logscale.write({
  data: [{ message: 'User logged in', userId: '123', timestamp: Date.now() }]
});

// Dynamic query
const results = await falcon.logscale.query({
  query: '#event_simpleName=ProcessRollup2 | count()',
  start: '-1h',
  end: 'now'
});

// Execute saved query by ID
const saved = await falcon.logscale.savedQuery({ id: 'saved-query-id' });
```

**Scopes:** `humio-auth-proxy:read` for queries, `humio-auth-proxy:write` for writing events.

## Cloud Functions

Call serverless functions deployed with your app:

```typescript
const response = await falcon.cloudFunction()
  .path('/my-endpoint')
  .post({ key: 'value' });

// GET with query params
const data = await falcon.cloudFunction()
  .path('/items')
  .query({ limit: '10', offset: '0' })
  .get();
```

Use cloud functions as an escape hatch when you need to call Falcon API endpoints outside the allowlisted `falcon.api` namespaces.

## Events (Inter-Extension Communication)

```typescript
// Listen for console context changes (e.g., detection selected)
const handler = (data: any) => { console.log('Context:', data); };
falcon.events.on('data', handler);

// Broadcast between extensions on the same page
falcon.events.broadcast({ type: 'refresh', payload: { id: '123' } });

// Always clean up listeners
falcon.events.off('data', handler);
```

## Navigation Gotchas

### Use HashRouter

Standard `BrowserRouter` breaks inside the Falcon console iframe. Always use `HashRouter`:

```tsx
import { HashRouter, Routes, Route } from 'react-router-dom';

function App() {
  return (
    <HashRouter>
      <Routes>
        <Route path="/" element={<Home />} />
        <Route path="/settings" element={<Settings />} />
      </Routes>
    </HashRouter>
  );
}
```

### External Links Use navigateTo

Links that navigate outside your app use `falcon.navigation.navigateTo()`. The `target` option controls where the link opens:

- `target: "_blank"` — opens in a new browser tab
- `target: "_self"` (default) — navigates the Falcon console in the same tab

When `target` is omitted, it defaults to `_self`.

```tsx
function ExternalLink({ href, children, newTab = true }) {
  const { falcon } = useFalconApiContext();

  const handleClick = (e: React.MouseEvent) => {
    e.preventDefault();
    if (falcon?.navigation?.navigateTo) {
      falcon.navigation.navigateTo({
        path: e.currentTarget.href,
        target: newTab ? '_blank' : '_self',
      });
    } else {
      window.open(href, '_blank');
    }
  };

  return <a href={href} onClick={handleClick}>{children}</a>;
}
```

**Note:** `falcon.navigation.onClick(event.nativeEvent)` is deprecated. Use `navigateTo({ path })` instead — it accepts a URL string directly, no native event required.

## Modal Page IDs

When opening modals, you need the **auto-generated 32-character hex ID** from the deployed manifest, not the page key from your source manifest:

```typescript
// Wrong — this is your source manifest key
falcon.navigation.openModal({ pageId: 'my-modal-page' });

// Correct — use the hex ID from the exported/deployed manifest
falcon.navigation.openModal({ pageId: 'a1b2c3d4e5f6...' });
```

**How to find it:** Export the deployed manifest or check the `app_id`-suffixed page entries after deploy.

## Theme Best Practices

- **Don't set `theme-dark`/`theme-light` on `<body>`** — foundry-js sets it on `<html>`. Putting it on body causes CSS specificity conflicts.
- Use `@crowdstrike/tailwind-toucan-base` design tokens for automatic theme adaptation:
  - `var(--critical)` for error states
  - `var(--link-color)` for links
  - `var(--surface-md)` for card backgrounds
- foundry-js handles theme switching automatically when users toggle dark/light mode in the Falcon console.
