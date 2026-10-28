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

// Write (creates or overwrites the object at this key).
// The SDK types write() as Promise<void>, but it resolves to the API envelope.
const result = (await collection.write('item-1', { name: 'Test', value: 42 })) as unknown as
  { errors?: { message?: string }[] } | undefined;

// Read
const item = await collection.read('item-1');

// Search with FQL (indexable fields only)
const results = await collection.search({ filter: "name:'Test'", sort: 'name|asc', limit: 50, offset: '0' });

// Delete
await collection.delete('item-1');
```

`write`, `read`, and `delete` take the key as a plain string. The SDK doesn't throw on a validation failure, so check `result?.errors?.length` after a write (the cast above makes that compile). See `collections-development` for the not-found envelope `read` returns for a missing key.

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

// Response structure: resources is typed unknown[], so cast to the fields you read
const resource = response.resources?.[0] as { status_code?: number; response_body?: unknown } | undefined;
const statusCode = resource?.status_code;    // HTTP status from the external API
const body = resource?.response_body;         // Parsed response body
```

**Gotcha — parameter types must match the OpenAPI spec.** `execute()` types params as `Record<string, unknown>`, so a quoted number compiles and ships, then fails server-side at runtime with `got string want integer`; the extension still renders, so it reads as an API/credential error, not a code bug. Check each parameter's `schema.type` — numbers and booleans unquoted, only `type: string` takes quotes (`{ query: { limit: 25 } }` ✅, `{ query: { limit: '25' } }` ❌).

UI extensions run in sandboxed iframes and cannot make arbitrary HTTP requests. All external API calls must go through `falcon.apiIntegration()`. See [calling-patterns.md](../../api-integrations/references/calling-patterns.md) for calling API integrations from Python and Go functions.

## Workflow Execution (Async Polling)

Workflows are asynchronous. Trigger an on-demand workflow by name through `falcon.api.workflows`, then poll for the result:

```typescript
async function executeWorkflow(falcon: FalconApi, name: string, input: Record<string, unknown>) {
  // The SDK's generated body type is Record<string, never>, so cast the input.
  const trigger = await falcon.api.workflows.postEntitiesExecuteV1(input as Record<string, never>, { name, depth: 0 });
  const executionId = trigger.resources?.[0] as string | undefined;
  if (!executionId) throw new Error('No execution ID returned');

  for (let i = 0; i < 20; i++) {
    await new Promise(resolve => setTimeout(resolve, 1000));
    const result = await falcon.api.workflows.getEntitiesExecutionResultsV1({ ids: [executionId] });
    const status = result.resources?.[0]?.status;
    if (status === 'Completed') return result.resources[0];
    if (status === 'Failed' || status === 'Cancelled') throw new Error(`Workflow ${status}`);
  }
  throw new Error('Workflow timed out after 20 attempts');
}
```

The workflow name must match exactly; names are unique per CID. Each activity's output is in the `resources[0].activities` array; find one by its `node_id`.

## LogScale Operations

The SDK types `logscale.write` with a second `properties` argument and marks its shape as unsettled; the foundryjs-demo sample calls it with the event alone, as below.

<!-- snippet-check: skip -->
```typescript
// Write an event; the response reports resources[0].rows_written
await falcon.logscale.write({ message: 'User logged in', userId: '123' });

// Dynamic query
const results = await falcon.logscale.query({
  name: 'LogScaleRepo',
  search_query: '#event_simpleName=ProcessRollup2 | count()',
  start: '1h',
  end: 'now',
});

// Saved query by ID
const saved = await falcon.logscale.savedQuery({ id: 'saved-query-id', start: '7d', mode: 'sync', parameters: {} });
```

**Scopes:** `app-logs:read` for queries, `app-logs:write` for writing events, as the foundryjs-demo and foundry-sample-logscale manifests declare.

## Cloud Functions

Call serverless functions deployed with your app. `cloudFunction()` requires a definition, `{ name }` or `{ id }`, with an optional `version`:

```typescript
const fn = falcon.cloudFunction({ name: 'my-function' });

const response = await fn.path('/my-endpoint').post({ key: 'value' });

// Query parameters go in the path
const data = await fn.path('/items?limit=10&offset=0').get();
```

`path()` returns `get`, `post`, `put`, `patch`, and `delete`.

Use cloud functions as an escape hatch when you need to call Falcon API endpoints outside the allowlisted `falcon.api` namespaces.

**Invoke by `name`, not `id` — clone-portable.** `falcon.cloudFunction({ name })` resolves at runtime and survives an app clone; a hardcoded `id` (and any hardcoded page-ID constants used for cross-page nav) point at the ORIGINAL app's IDs after a clone, because Falcon Foundry gives a cloned app new IDs.

## Events (Inter-Extension Communication)

```typescript
// Listen for console context changes (e.g., detection selected)
const onData = (data: any) => { console.log('Context:', data); };
falcon.events.on('data', onData);

// Broadcast to other extensions on the same page, and listen for theirs
falcon.sendBroadcast({ type: 'refresh', payload: { id: '123' } });
const onBroadcast = (payload: unknown) => { console.log('Broadcast:', payload); };
falcon.events.on('broadcast', onBroadcast);

// Always clean up listeners
falcon.events.off('data', onData);
falcon.events.off('broadcast', onBroadcast);
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

## Modals

Open a page or extension as a modal with `falcon.ui.openModal`, identifying it by `name` (or `id`) and its type:

```typescript
const result = await falcon.ui.openModal({ type: 'page', name: 'my-modal-page' }, 'Edit settings', { size: 'lg' });

// Inside the modal, return a value to the opener
falcon.ui.closeModal({ saved: true });
```

Opening by `name` survives an app clone, like `cloudFunction({ name })`.

## Theme Best Practices

- **Don't set `theme-dark`/`theme-light` on `<body>`** — foundry-js sets it on `<html>`. Putting it on body causes CSS specificity conflicts.
- Use `@crowdstrike/tailwind-toucan-base` design tokens for automatic theme adaptation:
  - `var(--critical)` for error states
  - `var(--titles-and-attributes)` for headings and values
  - `var(--surface-md)` for card backgrounds
- foundry-js handles theme switching automatically when users toggle dark/light mode in the Falcon console.
