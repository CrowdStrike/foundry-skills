# React Patterns for Foundry UI

## FalconApi Context Provider

Share a single FalconApi instance across React components. Pattern from [foundry-sample-foundryjs-demo](https://github.com/CrowdStrike/foundry-sample-foundryjs-demo):

```tsx
// contexts/falcon-api-context.tsx
import { createContext, useContext, useEffect, useMemo, useState, ReactNode } from 'react';
import FalconApi from '@crowdstrike/foundry-js';

interface FalconApiContextType {
  falcon: FalconApi;
  navigation: any;
  isInitialized: boolean;
}

const FalconApiContext = createContext<FalconApiContextType | null>(null);

function FalconApiProvider({ children }: { children: ReactNode }) {
  const [isInitialized, setIsInitialized] = useState(false);
  const falcon = useMemo(() => new FalconApi(), []);
  const navigation = useMemo(() => {
    return falcon.isConnected ? falcon.navigation : undefined;
  }, [falcon.isConnected]);

  useEffect(() => {
    (async () => {
      try {
        await falcon.connect();
        setIsInitialized(true);
      } catch (error) {
        console.error('Failed to connect to Falcon API:', error);
        setIsInitialized(true); // Still render app to show error state
      }
    })();
  }, [falcon]);

  return (
    <FalconApiContext.Provider value={{ falcon, navigation, isInitialized }}>
      {children}
    </FalconApiContext.Provider>
  );
}

function useFalconApiContext() {
  const context = useContext(FalconApiContext);
  if (!context) {
    throw new Error('useFalconApiContext must be used within a FalconApiProvider');
  }
  return context;
}

export { useFalconApiContext, FalconApiContext, FalconApiProvider };
```

```tsx
// app.tsx — gate rendering on isInitialized
import { FalconApiProvider, useFalconApiContext } from './contexts/falcon-api-context';

function AppContent() {
  const { isInitialized } = useFalconApiContext();
  if (!isInitialized) {
    return <div>Initializing Falcon API...</div>;
  }
  return <HashRouter><Routes>...</Routes></HashRouter>;
}

function App() {
  return (
    <FalconApiProvider>
      <AppContent />
    </FalconApiProvider>
  );
}
```

The examples below use this provider's `useFalconApiContext()`. The React blueprint ships a different `falcon-api-context.js`: there, `useFalconApiContext()` creates a new `FalconApi` and connects it, `app.jsx` calls it once, and components read the shared instance with `useContext(FalconApiContext)`. In a blueprint scaffold, either switch to the provider above or read with `useContext(FalconApiContext)`. Calling the blueprint's hook in a component opens a second connection.

## Mock Context for Unit Testing

Create a mock FalconApi for local development and unit tests:

```tsx
// contexts/falcon-api-context-mock.tsx
class MockFalconApi {
  isConnected = true;
  navigation = {
    navigateTo: (options) => console.log('[Mock] Navigate to:', options)
  };
  events = {
    on: (event, _handler) => console.log('[Mock] Register:', event),
    off: (event, _handler) => console.log('[Mock] Remove:', event)
  };
  async connect() { return Promise.resolve(); }
}

// Use in tests or local dev by swapping the import:
// import { FalconApiProvider } from './contexts/falcon-api-context-mock';
```

## Navigation with Deep Linking

Handle deep linking and URL sync with the Falcon console:

```tsx
function TabNavigation({ children }) {
  const navigate = useNavigate();
  const location = useLocation();
  const { falcon } = useFalconApiContext();

  // Deep link: navigate to initial path from URL hash on mount
  useEffect(() => {
    const initialPath = document.location.hash.replace(/^#./, '');
    if (initialPath && initialPath !== '/') {
      navigate(initialPath, { replace: true });
    }
  }, [navigate]);

  // Sync parent URL on navigation
  const handleNavigate = (path: string) => {
    navigate(path);
    if (falcon?.isConnected && falcon?.navigation?.navigateTo) {
      falcon.navigation.navigateTo({ path, type: 'internal', target: '_self' });
    }
  };

  return <Nav currentPath={location.pathname} onNavigate={handleNavigate}>{children}</Nav>;
}
```

## Page Component (Full Example)

Falcon APIs live under `falcon.api.<namespace>.<method>()`, one method per API operation. Each call resolves to `{ resources, errors }`. This page lists recent alerts: a query call returns IDs, then an entities call returns the details.

```tsx
import { useCallback, useEffect, useState } from 'react';
import { SlAlert, SlButton, SlCard, SlSpinner } from '@shoelace-style/shoelace/dist/react';
import { useFalconApiContext } from '../contexts/falcon-api-context';

interface Alert {
  composite_id: string;
  display_name?: string;
  severity?: number;
}

export function AlertsDashboard({ limit = 50 }: { limit?: number }) {
  const { falcon } = useFalconApiContext();
  const [alerts, setAlerts] = useState<Alert[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchAlerts = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const query = await falcon.api.alerts.getQueriesAlertsV2({ limit });
      const ids = (query.resources ?? []) as string[];
      if (ids.length === 0) {
        setAlerts([]);
        return;
      }
      // The generated body type is Record<string, never>, so cast the body.
      const body: Record<string, unknown> = { composite_ids: ids };
      const details = await falcon.api.alerts.postEntitiesAlertsV2(body as Record<string, never>);
      if (details.errors && details.errors.length > 0) {
        throw new Error(details.errors[0]?.message || 'Request failed');
      }
      setAlerts((details.resources ?? []) as Alert[]);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch alerts');
    } finally {
      setLoading(false);
    }
  }, [falcon, limit]);

  useEffect(() => {
    fetchAlerts();
  }, [fetchAlerts]);

  return (
    <SlCard>
      <div slot="header">Recent alerts</div>
      {error && <SlAlert variant="danger" open>{error}</SlAlert>}
      {loading ? (
        <SlSpinner />
      ) : (
        <table>
          <thead><tr><th>Severity</th><th>Alert</th></tr></thead>
          <tbody>
            {alerts.map((alert) => (
              <tr key={alert.composite_id}>
                <td>{alert.severity}</td>
                <td>{alert.display_name}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
      <SlButton onClick={fetchAlerts} loading={loading}>Refresh</SlButton>
    </SlCard>
  );
}
```

Each `falcon.api` namespace needs its scope in `manifest.yml` (`alerts:read` here).

## Extension Component with Console Context

An extension reads its socket's context from `falcon.data` and hears about changes through `falcon.events.on('data', …)`. On `activity.detections.details` the selected detection arrives as `detectionId` (the pattern from [foundry-sample-mitre](https://github.com/CrowdStrike/foundry-sample-mitre) and [foundry-sample-detection-translation](https://github.com/CrowdStrike/foundry-sample-detection-translation)):

```tsx
import { useEffect, useState } from 'react';
import { SlCard, SlSpinner } from '@shoelace-style/shoelace/dist/react';
import { useFalconApiContext } from '../contexts/falcon-api-context';

interface Detection {
  composite_id: string;
  display_name?: string;
  severity?: number;
}

export function DetectionSummary() {
  const { falcon } = useFalconApiContext();
  const [detectionId, setDetectionId] = useState(falcon.data?.detectionId as string | undefined);
  const [detection, setDetection] = useState<Detection | undefined>();

  // Follow the console as the user selects another detection
  useEffect(() => {
    const onData = (data: Record<string, unknown>) => setDetectionId(data.detectionId as string | undefined);
    falcon.events.on('data', onData);
    return () => falcon.events.off('data', onData);
  }, [falcon]);

  useEffect(() => {
    if (!detectionId) return;
    (async () => {
      const body: Record<string, unknown> = { composite_ids: [detectionId] };
      const response = await falcon.api.alerts.postEntitiesAlertsV2(body as Record<string, never>);
      setDetection(response.resources?.[0] as Detection | undefined);
    })();
  }, [falcon, detectionId]);

  return (
    <SlCard>
      {detection ? `${detection.display_name} (severity ${detection.severity})` : <SlSpinner />}
    </SlCard>
  );
}
```

## API Integration Component

Call third-party API integrations from React using `falcon.apiIntegration()`. Pattern from foundryjs-demo:

```tsx
import { useState } from 'react';
import { useFalconApiContext } from '../contexts/falcon-api-context';

function ApiIntegrationDemo() {
  const { falcon } = useFalconApiContext();
  const [loading, setLoading] = useState(false);
  const [results, setResults] = useState<unknown>(null);
  const [error, setError] = useState<string | null>(null);

  const executeIntegration = async () => {
    setLoading(true);
    setError(null);
    try {
      const apiIntegration = falcon.apiIntegration({
        definitionId: 'Okta',        // Must match name in manifest.yml api_integrations
        operationId: 'listUsers'     // Must match operationId in OpenAPI spec
      });

      const response = await apiIntegration.execute({
        request: {
          params: {
            // path: { id: '123' },    // path parameters
            // query: { limit: 10 },   // query parameters
            // header: { ... },        // additional headers
          },
          // json: { ... },            // request body (POST/PUT)
        }
      });

      // Check for errors
      if (response.errors && response.errors.length > 0) {
        throw new Error(response.errors[0]?.message || 'Request failed');
      }

      // resources is typed unknown[]; cast to the fields you read
      const resource = response.resources?.[0] as { status_code?: number; response_body?: unknown } | undefined;
      const body = resource?.response_body;
      const statusCode = resource?.status_code;

      if (statusCode && statusCode >= 400) {
        throw new Error(`API returned ${statusCode}`);
      }

      setResults(body);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Request failed');
    } finally {
      setLoading(false);
    }
  };

  // ... render UI
}
```

## Search/Filter List Pattern

```jsx
import { useState, useMemo } from 'react';
import { SlIcon, SlInput } from '@shoelace-style/shoelace/dist/react';

function UserList({ users }) {
  const [search, setSearch] = useState('');

  const filtered = useMemo(() => {
    if (!search) return users;
    const term = search.toLowerCase();
    return users.filter(u =>
      u.name?.toLowerCase().includes(term) ||
      u.email?.toLowerCase().includes(term) ||
      u.status?.toLowerCase().includes(term)
    );
  }, [users, search]);

  return (
    <>
      <SlInput
        placeholder="Search users..."
        clearable
        value={search}
        onSlInput={(e) => setSearch(e.target.value)}
      >
        <SlIcon name="search" slot="prefix" />
      </SlInput>

      <p className="text-neutral mt-2">Showing {filtered.length} of {users.length} users</p>

      <table>
        <thead><tr><th>Name</th><th>Email</th><th>Status</th></tr></thead>
        <tbody>
          {filtered.map(u => (
            <tr key={u.id}>
              <td>{u.name}</td>
              <td>{u.email}</td>
              <td><span className={`status status--${u.status === 'ACTIVE' ? 'success' : 'neutral'}`}>{u.status}</span></td>
            </tr>
          ))}
        </tbody>
      </table>
    </>
  );
}
```

## Unit Testing with Vitest

Mock the `@crowdstrike/foundry-js` default export and render inside the real `FalconApiProvider`, as the foundryjs-demo tests do. Only the API methods the component calls need stubs:

```tsx
import { render, screen, waitFor } from '@testing-library/react';
import { vi, describe, it, expect, beforeEach } from 'vitest';
import { FalconApiProvider } from '../contexts/falcon-api-context';
import { AlertsDashboard } from '../components/alerts-dashboard';

// vi.mock is hoisted above imports, so create the mocks with vi.hoisted
const { getQueriesAlertsV2, postEntitiesAlertsV2 } = vi.hoisted(() => ({
  getQueriesAlertsV2: vi.fn(),
  postEntitiesAlertsV2: vi.fn(),
}));

vi.mock('@crowdstrike/foundry-js', () => ({
  default: class FalconApi {
    connect = vi.fn().mockResolvedValue(undefined);
    isConnected = true;
    api = { alerts: { getQueriesAlertsV2, postEntitiesAlertsV2 } };
    events = { on: vi.fn(), off: vi.fn() };
  },
}));

describe('AlertsDashboard', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('shows alerts returned by the API', async () => {
    getQueriesAlertsV2.mockResolvedValueOnce({ resources: ['id-1'] });
    postEntitiesAlertsV2.mockResolvedValueOnce({
      resources: [{ composite_id: 'id-1', display_name: 'Test alert', severity: 70 }],
    });

    render(<FalconApiProvider><AlertsDashboard /></FalconApiProvider>);

    await waitFor(() => expect(screen.getByText('Test alert')).toBeInTheDocument());
    expect(postEntitiesAlertsV2).toHaveBeenCalledWith({ composite_ids: ['id-1'] });
  });
});
```
