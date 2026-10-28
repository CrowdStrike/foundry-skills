# Vue Patterns for Foundry UI

There is no Vue blueprint, so these patterns follow [foundry-sample-mitre](https://github.com/CrowdStrike/foundry-sample-mitre) (`ui/pages/chart-vue` and its shared `falcon-api` plugin): create one `FalconApi`, `provide` it to the app, connect before mounting, and `inject` it in components.

## FalconApi Plugin and main.ts

```typescript
// plugins/falcon-api.ts
import type { App, InjectionKey } from 'vue';
import FalconApi from '@crowdstrike/foundry-js';

export const FALCON_API: InjectionKey<FalconApi> = Symbol('falconApi');

export function createFalconApi() {
  const falcon = new FalconApi();
  return {
    falcon,
    install(app: App) {
      app.provide(FALCON_API, falcon);
    },
    async connect() {
      try {
        await falcon.connect();
      } catch (error) {
        console.error('Failed to connect to Falcon API:', error);
      }
    },
  };
}
```

Add `@crowdstrike/tailwind-toucan-base`, `@crowdstrike/falcon-shoelace`, and `@shoelace-style/shoelace` to `package.json` (the React blueprint pins 5.0.0, 0.4.0, and 2.20.1).

```typescript
// main.ts
import '@crowdstrike/tailwind-toucan-base/index.css';  // defines the Toucan color tokens (--surface-md, ...)
import '@crowdstrike/falcon-shoelace/dist/style.css';  // one stylesheet, both themes
import { setBasePath } from '@shoelace-style/shoelace/dist/utilities/base-path.js';

// Pin the version installed in package.json
setBasePath('https://cdn.jsdelivr.net/npm/@shoelace-style/shoelace@2.20.1/cdn/');

// Import only the components you use
import '@shoelace-style/shoelace/dist/components/alert/alert.js';
import '@shoelace-style/shoelace/dist/components/button/button.js';
import '@shoelace-style/shoelace/dist/components/card/card.js';
import '@shoelace-style/shoelace/dist/components/icon/icon.js';
import '@shoelace-style/shoelace/dist/components/input/input.js';
import '@shoelace-style/shoelace/dist/components/option/option.js';
import '@shoelace-style/shoelace/dist/components/select/select.js';
import '@shoelace-style/shoelace/dist/components/spinner/spinner.js';

import { createApp } from 'vue';
import App from './App.vue';
import { createFalconApi } from './plugins/falcon-api';

(async () => {
  const app = createApp(App);
  app.config.compilerOptions.isCustomElement = (tag) => tag.startsWith('sl-');

  const falconApi = createFalconApi();
  app.use(falconApi);
  await falconApi.connect();  // connect before mount so components can call the SDK

  app.mount('#app');
})();
```

`app.config.compilerOptions` only covers templates compiled in the browser. Vite compiles single-file components, so also tell `@vitejs/plugin-vue` that `sl-` tags are custom elements, as mitre's `vite.config.ts` does. Without it, Vue tries to resolve every `sl-` tag as a Vue component and warns `Failed to resolve component`:

```typescript
// vite.config.ts (keep the scaffold's other settings, such as noAttr())
import vue from '@vitejs/plugin-vue';
import { defineConfig } from 'vite';

export default defineConfig({
  plugins: [
    vue({
      template: {
        compilerOptions: {
          isCustomElement: (tag) => tag.startsWith('sl-'),
        },
      },
    }),
  ],
});
```

## Page Component (Full Example)

Falcon APIs live under `falcon.api.<namespace>.<method>()` and resolve to `{ resources, errors }`. A query call returns IDs, then an entities call returns the details:

```vue
<template>
  <sl-card>
    <div slot="header">Recent alerts</div>
    <sl-alert v-if="error" variant="danger" open>{{ error }}</sl-alert>
    <sl-spinner v-if="loading"></sl-spinner>
    <table v-else>
      <thead><tr><th>Severity</th><th>Alert</th></tr></thead>
      <tbody>
        <tr v-for="alert in alerts" :key="alert.composite_id">
          <td>{{ alert.severity }}</td>
          <td>{{ alert.display_name }}</td>
        </tr>
      </tbody>
    </table>
    <sl-button :loading="loading" @click="fetchAlerts">Refresh</sl-button>
  </sl-card>
</template>

<script setup lang="ts">
import { inject, onMounted, ref } from 'vue';
import type FalconApi from '@crowdstrike/foundry-js';
import { FALCON_API } from '../plugins/falcon-api';

interface Alert {
  composite_id: string;
  display_name?: string;
  severity?: number;
}

const falcon = inject(FALCON_API) as FalconApi;
const alerts = ref<Alert[]>([]);
const loading = ref(true);
const error = ref<string | null>(null);

async function fetchAlerts() {
  loading.value = true;
  error.value = null;
  try {
    const query = await falcon.api.alerts.getQueriesAlertsV2({ limit: 50 });
    const ids = (query.resources ?? []) as string[];
    if (ids.length === 0) {
      alerts.value = [];
      return;
    }
    // The generated body type is Record<string, never>, so cast the body.
    const body: Record<string, unknown> = { composite_ids: ids };
    const details = await falcon.api.alerts.postEntitiesAlertsV2(body as Record<string, never>);
    // foundry-js resolves with errors instead of rejecting
    if (details.errors?.length) throw new Error(details.errors[0].message);
    alerts.value = (details.resources ?? []) as Alert[];
  } catch (err) {
    error.value = err instanceof Error ? err.message : 'Failed to fetch alerts';
  } finally {
    loading.value = false;
  }
}

onMounted(fetchAlerts);
</script>
```

Each `falcon.api` namespace needs its scope in `manifest.yml` (`alerts:read` here).

## Extension Component with Console Context

An extension reads its socket's context from `falcon.data` and hears about changes through `falcon.events.on('data', …)`. On `activity.detections.details` the selected detection arrives as `detectionId`, which is how mitre's remediations extension follows the console:

```vue
<template>
  <sl-card>
    <span v-if="detection">{{ detection.display_name }} (severity {{ detection.severity }})</span>
    <sl-spinner v-else></sl-spinner>
  </sl-card>
</template>

<script setup lang="ts">
import { inject, onUnmounted, ref, watchEffect } from 'vue';
import type FalconApi from '@crowdstrike/foundry-js';
import { FALCON_API } from '../plugins/falcon-api';

interface Detection {
  composite_id: string;
  display_name?: string;
  severity?: number;
}

const falcon = inject(FALCON_API) as FalconApi;
const detectionId = ref(falcon.data?.detectionId as string | undefined);
const detection = ref<Detection>();

const onData = (data: Record<string, unknown>) => {
  detectionId.value = data.detectionId as string | undefined;
};
falcon.events.on('data', onData);
onUnmounted(() => falcon.events.off('data', onData));

watchEffect(async () => {
  if (!detectionId.value) return;
  const body: Record<string, unknown> = { composite_ids: [detectionId.value] };
  const response = await falcon.api.alerts.postEntitiesAlertsV2(body as Record<string, never>);
  detection.value = response.resources?.[0] as Detection | undefined;
});
</script>
```

## Form Handling

Shoelace has no form component. Put its controls in a native `<form>`, where they submit and validate like native inputs:

```vue
<template>
  <form @submit.prevent="applyFilters">
    <sl-input
      name="hostname"
      label="Hostname filter"
      :value="filters.hostname"
      @sl-input="filters.hostname = ($event.target as HTMLInputElement).value"
      clearable
    >
      <sl-icon name="search" slot="prefix"></sl-icon>
    </sl-input>

    <sl-select
      name="severity"
      label="Minimum severity"
      :value="filters.severity"
      @sl-change="filters.severity = ($event.target as HTMLSelectElement).value"
    >
      <sl-option value="20">Low (20+)</sl-option>
      <sl-option value="50">Medium (50+)</sl-option>
      <sl-option value="70">High (70+)</sl-option>
    </sl-select>

    <sl-button type="submit" variant="primary">Apply filters</sl-button>
  </form>
</template>

<script setup lang="ts">
import { reactive } from 'vue';

const filters = reactive({ hostname: '', severity: '1' });
const emit = defineEmits<{ apply: [filters: { hostname: string; severity: string }] }>();

function applyFilters() {
  emit('apply', { ...filters });
}
</script>
```

## Unit Testing Vue Components

Hand the component a stub through `global.provide` instead of the plugin. Only the API methods the component calls need stubs:

```typescript
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { mount, flushPromises } from '@vue/test-utils';
import AlertsDashboard from '../components/AlertsDashboard.vue';
import { FALCON_API } from '../plugins/falcon-api';

const getQueriesAlertsV2 = vi.fn();
const postEntitiesAlertsV2 = vi.fn();
const falconStub = { api: { alerts: { getQueriesAlertsV2, postEntitiesAlertsV2 } } };

const mountDashboard = () =>
  mount(AlertsDashboard, {
    global: {
      provide: { [FALCON_API as symbol]: falconStub },
      config: { compilerOptions: { isCustomElement: (tag: string) => tag.startsWith('sl-') } },
    },
  });

describe('AlertsDashboard', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('shows alerts returned by the API', async () => {
    getQueriesAlertsV2.mockResolvedValueOnce({ resources: ['id-1'] });
    postEntitiesAlertsV2.mockResolvedValueOnce({
      resources: [{ composite_id: 'id-1', display_name: 'Test alert', severity: 70 }],
    });

    const wrapper = mountDashboard();
    await flushPromises();

    expect(wrapper.text()).toContain('Test alert');
  });

  it('shows the error when the API call fails', async () => {
    getQueriesAlertsV2.mockRejectedValueOnce(new Error('API Error'));

    const wrapper = mountDashboard();
    await flushPromises();

    expect(wrapper.find('sl-alert[variant="danger"]').exists()).toBe(true);
    expect(wrapper.text()).toContain('API Error');
  });
});
```
