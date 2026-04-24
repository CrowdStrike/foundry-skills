# Vue Patterns for Foundry UI

## Page Component (Full Example)

Vue 3 Composition API with Foundry-JS SDK:

```vue
<template>
  <div class="foundry-page">
    <sl-card>
      <div slot="header">
        <h2>{{ title }}</h2>
      </div>

      <sl-alert v-if="error" variant="danger" open>
        {{ error }}
      </sl-alert>

      <sl-spinner v-if="loading"></sl-spinner>

      <div v-else class="content">
        <sl-table v-if="alerts.length">
          <thead>
            <tr>
              <th>Severity</th>
              <th>Hostname</th>
              <th>Description</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="alert in alerts" :key="alert.id">
              <td>
                <sl-badge :variant="getSeverityVariant(alert.severity)">
                  {{ alert.severity }}
                </sl-badge>
              </td>
              <td>{{ alert.hostname }}</td>
              <td>{{ alert.description }}</td>
            </tr>
          </tbody>
        </sl-table>

        <sl-button @click="refreshData" :loading="refreshing">
          Refresh
        </sl-button>
      </div>
    </sl-card>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue';
import { useFoundry } from '@crowdstrike/foundry-js';
import type { Alert } from '../types';

const foundry = useFoundry();

const title = ref('Security Alerts Dashboard');
const alerts = ref<Alert[]>([]);
const loading = ref(true);
const refreshing = ref(false);
const error = ref<string | null>(null);

const getSeverityVariant = (severity: number): string => {
  if (severity >= 8) return 'danger';
  if (severity >= 5) return 'warning';
  return 'neutral';
};

const fetchAlerts = async () => {
  try {
    const response = await foundry.api.get('/alerts', {
      params: { limit: 50 }
    });
    alerts.value = response.data.resources;
  } catch (err) {
    error.value = 'Failed to fetch alerts. Please try again.';
    console.error('Alert fetch error:', err);
  }
};

const refreshData = async () => {
  refreshing.value = true;
  await fetchAlerts();
  refreshing.value = false;
};

onMounted(async () => {
  await fetchAlerts();
  loading.value = false;
});
</script>

<style scoped>
.foundry-page {
  padding: var(--sl-spacing-large);
  max-width: 1200px;
  margin: 0 auto;
}

.content {
  display: flex;
  flex-direction: column;
  gap: var(--sl-spacing-medium);
}
</style>
```

## Extension Component with Context

Console-embedded extension that reacts to Falcon console context changes:

```vue
<template>
  <div class="extension-widget">
    <sl-card>
      <div slot="header">
        <sl-icon name="shield-check"></sl-icon>
        Host Details: {{ context?.hostname || 'Loading...' }}
      </div>

      <div v-if="hostData" class="host-info">
        <sl-details summary="System Information">
          <dl>
            <dt>Platform</dt>
            <dd>{{ hostData.platform_name }}</dd>
            <dt>OS Version</dt>
            <dd>{{ hostData.os_version }}</dd>
            <dt>Agent Version</dt>
            <dd>{{ hostData.agent_version }}</dd>
            <dt>Last Seen</dt>
            <dd>{{ formatDate(hostData.last_seen) }}</dd>
          </dl>
        </sl-details>

        <sl-details summary="Security Status">
          <sl-tag :variant="hostData.status === 'normal' ? 'success' : 'danger'">
            {{ hostData.status }}
          </sl-tag>
        </sl-details>
      </div>
    </sl-card>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, watch } from 'vue';
import { useFoundryExtension } from '@crowdstrike/foundry-js';
import type { HostContext, HostData } from '../types';

const { context, onContextChange } = useFoundryExtension<HostContext>();

const hostData = ref<HostData | null>(null);

const formatDate = (dateStr: string): string => {
  return new Date(dateStr).toLocaleString();
};

const fetchHostData = async (deviceId: string) => {
  try {
    const response = await foundry.api.get(`/devices/${deviceId}`);
    hostData.value = response.data;
  } catch (err) {
    console.error('Failed to fetch host data:', err);
  }
};

// React to context changes from Falcon console
onContextChange((newContext) => {
  if (newContext?.device_id) {
    fetchHostData(newContext.device_id);
  }
});

onMounted(() => {
  if (context.value?.device_id) {
    fetchHostData(context.value.device_id);
  }
});
</script>
```

## Shoelace Component Registration in Vue

```typescript
// main.ts - Vue.js setup with Falcon theming
import { createApp } from 'vue';
import App from './App.vue';

// REQUIRED: Import Falcon-themed Shoelace (NOT vanilla Shoelace themes)
import '@crowdstrike/falcon-shoelace/dist/themes/light.css';
import '@crowdstrike/falcon-shoelace/dist/themes/dark.css';
import { setBasePath } from '@shoelace-style/shoelace/dist/utilities/base-path';

// Point to Shoelace assets
setBasePath('https://cdn.jsdelivr.net/npm/@shoelace-style/shoelace@2.x/dist/');

// Import specific components used
import '@shoelace-style/shoelace/dist/components/button/button.js';
import '@shoelace-style/shoelace/dist/components/card/card.js';
import '@shoelace-style/shoelace/dist/components/alert/alert.js';
import '@shoelace-style/shoelace/dist/components/spinner/spinner.js';
import '@shoelace-style/shoelace/dist/components/badge/badge.js';
import '@shoelace-style/shoelace/dist/components/details/details.js';
import '@shoelace-style/shoelace/dist/components/tag/tag.js';
import '@shoelace-style/shoelace/dist/components/icon/icon.js';

createApp(App).mount('#app');
```

## Form Handling with Validation

```vue
<template>
  <sl-form @sl-submit="handleSubmit">
    <sl-input
      name="hostname"
      label="Hostname Filter"
      placeholder="Enter hostname pattern"
      :value="filters.hostname"
      @sl-change="(e) => filters.hostname = e.target.value"
      clearable
    >
      <sl-icon name="search" slot="prefix"></sl-icon>
    </sl-input>

    <sl-select
      name="severity"
      label="Minimum Severity"
      :value="filters.severity"
      @sl-change="(e) => filters.severity = e.target.value"
    >
      <sl-option value="1">Low (1+)</sl-option>
      <sl-option value="5">Medium (5+)</sl-option>
      <sl-option value="8">High (8+)</sl-option>
    </sl-select>

    <sl-button type="submit" variant="primary">
      Apply Filters
    </sl-button>
  </sl-form>
</template>
```

## Unit Testing Vue Components

```typescript
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { mount, flushPromises } from '@vue/test-utils';
import AlertsDashboard from '@/components/AlertsDashboard.vue';
import { mockFoundry } from '../mocks/foundry';

vi.mock('@crowdstrike/foundry-js', () => ({
  useFoundry: () => mockFoundry,
}));

describe('AlertsDashboard', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('renders loading state initially', () => {
    const wrapper = mount(AlertsDashboard);
    expect(wrapper.find('sl-spinner').exists()).toBe(true);
  });

  it('displays alerts after loading', async () => {
    mockFoundry.api.get.mockResolvedValueOnce({
      data: {
        resources: [
          { id: '1', severity: 8, hostname: 'test-host', description: 'Test alert' },
        ],
      },
    });

    const wrapper = mount(AlertsDashboard);
    await flushPromises();

    expect(wrapper.find('sl-spinner').exists()).toBe(false);
    expect(wrapper.text()).toContain('test-host');
    expect(wrapper.find('sl-badge').text()).toContain('8');
  });

  it('shows error message on API failure', async () => {
    mockFoundry.api.get.mockRejectedValueOnce(new Error('API Error'));

    const wrapper = mount(AlertsDashboard);
    await flushPromises();

    expect(wrapper.find('sl-alert[variant="danger"]').exists()).toBe(true);
    expect(wrapper.text()).toContain('Failed to fetch alerts');
  });
});
```
