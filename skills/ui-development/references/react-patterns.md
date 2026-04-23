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

```tsx
import React, { useState, useEffect } from 'react';
import { useFoundry } from '@crowdstrike/foundry-js/react';
import {
  SlCard, SlAlert, SlSpinner, SlButton, SlBadge,
} from '@shoelace-style/shoelace/dist/react';
import type { Alert } from '../types';

interface AlertsDashboardProps {
  title?: string;
  limit?: number;
}

export const AlertsDashboard: React.FC<AlertsDashboardProps> = ({
  title = 'Security Alerts Dashboard',
  limit = 50,
}) => {
  const foundry = useFoundry();
  const [alerts, setAlerts] = useState<Alert[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const getSeverityVariant = (severity: number): 'danger' | 'warning' | 'neutral' => {
    if (severity >= 8) return 'danger';
    if (severity >= 5) return 'warning';
    return 'neutral';
  };

  const fetchAlerts = async () => {
    try {
      setError(null);
      const response = await foundry.api.get('/alerts', {
        params: { limit },
      });
      setAlerts(response.data.resources);
    } catch (err) {
      setError('Failed to fetch alerts. Please try again.');
      console.error('Alert fetch error:', err);
    }
  };

  const handleRefresh = async () => {
    setRefreshing(true);
    await fetchAlerts();
    setRefreshing(false);
  };

  useEffect(() => {
    fetchAlerts().finally(() => setLoading(false));
  }, []);

  return (
    <div className="foundry-page">
      <SlCard>
        <div slot="header">
          <h2>{title}</h2>
        </div>

        {error && (
          <SlAlert variant="danger" open>
            {error}
          </SlAlert>
        )}

        {loading ? (
          <SlSpinner />
        ) : (
          <div className="content">
            {alerts.length > 0 && (
              <table className="sl-table">
                <thead>
                  <tr>
                    <th>Severity</th>
                    <th>Hostname</th>
                    <th>Description</th>
                  </tr>
                </thead>
                <tbody>
                  {alerts.map((alert) => (
                    <tr key={alert.id}>
                      <td>
                        <SlBadge variant={getSeverityVariant(alert.severity)}>
                          {alert.severity}
                        </SlBadge>
                      </td>
                      <td>{alert.hostname}</td>
                      <td>{alert.description}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}

            <SlButton onClick={handleRefresh} loading={refreshing}>
              Refresh
            </SlButton>
          </div>
        )}
      </SlCard>
    </div>
  );
};
```

## Extension Component with Context Hook

```tsx
import React, { useState, useEffect } from 'react';
import { useFoundryExtension } from '@crowdstrike/foundry-js/react';
import { SlCard, SlDetails, SlTag, SlIcon } from '@shoelace-style/shoelace/dist/react';
import type { HostContext, HostData } from '../types';

export const HostDetailsExtension: React.FC = () => {
  const { context, onContextChange } = useFoundryExtension<HostContext>();
  const [hostData, setHostData] = useState<HostData | null>(null);
  const [loading, setLoading] = useState(true);

  const formatDate = (dateStr: string): string => {
    return new Date(dateStr).toLocaleString();
  };

  const fetchHostData = async (deviceId: string) => {
    setLoading(true);
    try {
      const response = await foundry.api.get(`/devices/${deviceId}`);
      setHostData(response.data);
    } catch (err) {
      console.error('Failed to fetch host data:', err);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    const unsubscribe = onContextChange((newContext) => {
      if (newContext?.device_id) {
        fetchHostData(newContext.device_id);
      }
    });

    if (context?.device_id) {
      fetchHostData(context.device_id);
    }

    return unsubscribe;
  }, []);

  return (
    <div className="extension-widget">
      <SlCard>
        <div slot="header">
          <SlIcon name="shield-check" />
          Host Details: {context?.hostname || 'Loading...'}
        </div>

        {hostData && (
          <div className="host-info">
            <SlDetails summary="System Information">
              <dl>
                <dt>Platform</dt>
                <dd>{hostData.platform_name}</dd>
                <dt>OS Version</dt>
                <dd>{hostData.os_version}</dd>
                <dt>Agent Version</dt>
                <dd>{hostData.agent_version}</dd>
                <dt>Last Seen</dt>
                <dd>{formatDate(hostData.last_seen)}</dd>
              </dl>
            </SlDetails>

            <SlDetails summary="Security Status">
              <SlTag variant={hostData.status === 'normal' ? 'success' : 'danger'}>
                {hostData.status}
              </SlTag>
            </SlDetails>
          </div>
        )}
      </SlCard>
    </div>
  );
};
```

## API Integration Component

Call third-party API integrations from React using `falcon.apiIntegration()`. Pattern from foundryjs-demo:

```tsx
import { useState } from 'react';
import { useFalconApiContext } from '../contexts/falcon-api-context';

function ApiIntegrationDemo() {
  const { falcon } = useFalconApiContext();
  const [loading, setLoading] = useState(false);
  const [results, setResults] = useState(null);
  const [error, setError] = useState(null);

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
          },
          // json: { ... },            // request body (POST/PUT)
          // headers: { ... },         // additional headers
        }
      });

      // Check for errors
      if (response.errors?.length > 0) {
        throw new Error(response.errors[0]?.message || 'Request failed');
      }

      const resource = response.resources?.[0];
      const body = resource?.response_body;
      const statusCode = resource?.status_code;

      if (statusCode >= 400) {
        throw new Error(`API returned ${statusCode}`);
      }

      setResults(body);
    } catch (err) {
      setError(err.message);
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
      <sl-input
        placeholder="Search users..."
        clearable
        value={search}
        onSlInput={(e) => setSearch(e.target.value)}
      >
        <sl-icon name="search" slot="prefix"></sl-icon>
      </sl-input>

      <p className="text-neutral mt-2">Showing {filtered.length} of {users.length} users</p>

      <table>
        <thead><tr><th>Name</th><th>Email</th><th>Status</th></tr></thead>
        <tbody>
          {filtered.map(u => (
            <tr key={u.id}>
              <td>{u.name}</td>
              <td>{u.email}</td>
              <td><sl-badge variant={u.status === 'ACTIVE' ? 'success' : 'neutral'}>{u.status}</sl-badge></td>
            </tr>
          ))}
        </tbody>
      </table>
    </>
  );
}
```

## Unit Testing with Vitest

```typescript
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { vi, describe, it, expect, beforeEach } from 'vitest';
import { AlertsDashboard } from '@/components/AlertsDashboard';
import { mockFoundry } from '../mocks/foundry';

vi.mock('@crowdstrike/foundry-js/react', () => ({
  useFoundry: () => mockFoundry,
}));

describe('AlertsDashboard', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('renders loading spinner initially', () => {
    render(<AlertsDashboard />);
    expect(screen.getByRole('status')).toBeInTheDocument();
  });

  it('displays alerts after loading', async () => {
    mockFoundry.api.get.mockResolvedValueOnce({
      data: {
        resources: [
          { id: '1', severity: 8, hostname: 'test-host', description: 'Test alert' },
        ],
      },
    });

    render(<AlertsDashboard />);

    await waitFor(() => {
      expect(screen.getByText('test-host')).toBeInTheDocument();
    });
  });

  it('handles refresh button click', async () => {
    const user = userEvent.setup();
    mockFoundry.api.get.mockResolvedValue({ data: { resources: [] } });

    render(<AlertsDashboard />);
    await waitFor(() => screen.getByRole('button', { name: /refresh/i }));

    await user.click(screen.getByRole('button', { name: /refresh/i }));

    expect(mockFoundry.api.get).toHaveBeenCalledTimes(2);
  });
});
```
