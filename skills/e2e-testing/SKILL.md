---
name: e2e-testing
description: End-to-end testing for Falcon Foundry apps using Playwright and @crowdstrike/foundry-playwright. TRIGGER when user asks to "add e2e tests", "add playwright tests", "write end-to-end tests", "test my app", or mentions "e2e", "playwright", or "end-to-end" in the context of testing a Foundry app. DO NOT TRIGGER during normal app creation, UI development, or function development. This skill is opt-in; not all apps need e2e tests.
version: 1.3.0
updated: 2026-06-11
tags: [foundry, e2e, playwright, testing]
author: CrowdStrike
license: MIT
compatibility: Claude Code >=1.0
metadata:
  category: testing
---

# Foundry E2E Testing

End-to-end testing for Falcon Foundry apps using [Playwright](https://playwright.dev/) and the [`@crowdstrike/foundry-playwright`](https://github.com/CrowdStrike/foundry-playwright) library.

The library provides authentication, app install/uninstall, page objects, and configuration so each app only writes its app-specific tests.

## Quick Start

### 1. Create the `e2e/` directory

```
my-foundry-app/
├── e2e/
│   ├── .env                    # Local credentials (git-ignored)
│   ├── .env.sample             # Template for other developers
│   ├── .gitignore
│   ├── package.json
│   ├── playwright.config.ts
│   └── tests/
│       └── foundry.spec.ts
├── manifest.yml
└── ...
```

### 2. `package.json`

Node.js LTS is recommended.

```json
{
  "name": "playwright-foundry",
  "version": "1.0.0",
  "scripts": {
    "test": "npx playwright test",
    "test:ui": "npx playwright test --ui",
    "test:debug": "npx playwright test --debug",
    "test:verbose": "DEBUG=true npx playwright test --reporter=list"
  },
  "type": "commonjs",
  "devDependencies": {
    "@crowdstrike/foundry-playwright": "0.5.0",
    "@types/node": "25.6.0"
  }
}
```

**Always pin exact versions** — never use `"latest"`, `"^"`, or `"~"`. Check npm for the current version of each package.

The library brings `@playwright/test`, `@dotenvx/dotenvx`, and `otpauth` as transitive dependencies. No need to install them separately.

### 3. `.env`

```sh
FALCON_USERNAME=your.email@company.com
FALCON_PASSWORD=your-password
FALCON_AUTH_SECRET=your-totp-secret
FALCON_BASE_URL=https://falcon.us-2.crowdstrike.com
APP_NAME=your-app-name
```

**Convention for sample apps:** Set `APP_NAME` to match the manifest `name` field, which should match the repo name (e.g., `foundry-sample-functions-python`). This avoids spaces in names and simplifies CI. This is a convention, not a hard requirement.

### 4. `playwright.config.ts`

```typescript
import { defineFoundryConfig } from '@crowdstrike/foundry-playwright';

export default defineFoundryConfig();
```

This gives you the standard 4-project pipeline automatically:
1. **setup**: authenticate and save session state
2. **app-install**: install the app via App Catalog
3. **chromium**: run your tests
4. **app-uninstall**: clean up after tests

### 5. `.gitignore`

```
node_modules/
playwright/.auth/
playwright-report/
test-results/
.env
```

### 6. Install and run

```bash
cd e2e
npm install
npx playwright install chromium --with-deps
npm test
```

## Writing Tests

### Available page objects

The library provides these page objects:

| Class | Purpose |
|-------|---------|
| `WorkflowsPage` | Search, open, execute, and verify Falcon Fusion SOAR workflows |
| `DetectionExtensionPage` | Navigate to Endpoint Detections, expand extensions, return iframe FrameLocator |
| `HostManagementPage` | Navigate to host management, retrieve host IDs |
| `AppCatalogPage` | Install, uninstall, and navigate to apps |
| `AppBuilderPage` | Disable workflow provisioning before install |
| `AppManagerPage` | Find and navigate to apps in App Manager |
| `FoundryHomePage` | Navigate to Falcon Foundry home |

### Fixtures pattern

Create `src/fixtures.ts` to wire up page objects as Playwright fixtures. **Only import what your tests actually use** — don't define unused fixtures:

```typescript
import { test as baseTest } from '@playwright/test';
import { DetectionExtensionPage, WorkflowsPage } from '@crowdstrike/foundry-playwright';

type FoundryFixtures = {
  detectionExtensionPage: DetectionExtensionPage;
  workflowsPage: WorkflowsPage;
};

export const test = baseTest.extend<FoundryFixtures>({
  detectionExtensionPage: async ({ page }, use) => { await use(new DetectionExtensionPage(page)); },
  workflowsPage: async ({ page }, use) => { await use(new WorkflowsPage(page)); },
});

export { expect } from '@playwright/test';
```

Playwright fixtures are lazy (only instantiated when a test requests them), so unused fixtures don't hurt performance — but they add confusion and dead code. Add fixtures as you add tests that need them.

### Example test: workflows

```typescript
import { test } from '../src/fixtures';

test.describe.configure({ mode: 'serial' });

test('should execute workflow', async ({ workflowsPage }) => {
  test.setTimeout(180000);
  await workflowsPage.navigateToWorkflows();
  await workflowsPage.executeAndVerifyWorkflow('My Workflow Name');
  await workflowsPage.verifyWorkflowExecutionCompleted();
});

test('should execute workflow with input', async ({ workflowsPage, hostManagementPage }) => {
  test.setTimeout(180000);
  const hostId = await hostManagementPage.getFirstHostId();
  if (!hostId) { test.skip(true, 'No hosts available'); return; }

  await workflowsPage.navigateToWorkflows();
  await workflowsPage.executeAndVerifyWorkflow('Host Details Workflow', {
    inputs: { 'Host ID': hostId },
  });
  await workflowsPage.verifyWorkflowExecutionCompleted();
});
```

`executeAndVerifyWorkflow()` handles search, execution trigger, and initial verification. `verifyWorkflowExecutionCompleted()` opens the execution detail view in a new tab and polls until the status leaves "In Progress" — it fails the test if the execution reports "Failed" and times out after 120s by default. For render-only checks (e.g., ServiceNow workflows without credentials), use `verifyWorkflowRenders()`.

### Example test: UI extensions

```typescript
import { test, expect } from '../src/fixtures';

test('should render extension', async ({ detectionExtensionPage }) => {
  const frame = await detectionExtensionPage.openExtension('hello');
  await expect(frame.getByText(/My App Title/i)).toBeVisible({ timeout: 10000 });
});
```

`openExtension()` navigates to Endpoint Detections, opens the first detection, scrolls to the named extension button, expands it, and returns the iframe FrameLocator.

## Apps with Configuration Screens

If your app has API integration settings during install (e.g., ServiceNow credentials), the default install will fail because the Install button stays disabled until fields are filled.

### 1. Add integration credentials to `.env` and `.env.sample`

```sh
# .env.sample — commit this as a template
SERVICENOW_INSTANCE_URL=https://dev123456.service-now.com
SERVICENOW_USERNAME=your-servicenow-username
SERVICENOW_PASSWORD=your-servicenow-password

# .env — local values, git-ignored
SERVICENOW_INSTANCE_URL=https://dev99999.service-now.com
SERVICENOW_USERNAME=admin
SERVICENOW_PASSWORD=s3cret
```

### 2. Create a custom `tests/app-install.setup.ts`

```typescript
import { test as setup } from '@playwright/test';
import { AppCatalogPage, config } from '@crowdstrike/foundry-playwright';

setup('install app', async ({ page }) => {
  const catalog = new AppCatalogPage(page);

  const instanceUrl = process.env.SERVICENOW_INSTANCE_URL;
  const username = process.env.SERVICENOW_USERNAME;
  const password = process.env.SERVICENOW_PASSWORD;
  if (!instanceUrl || !username || !password) {
    throw new Error('Missing required ServiceNow env vars: SERVICENOW_INSTANCE_URL, SERVICENOW_USERNAME, SERVICENOW_PASSWORD');
  }

  await catalog.installApp(config.appName, {
    configureSettings: async (page) => {
      await page.getByRole('textbox', { name: 'Name', exact: true }).fill('ServiceNow Integration');
      await page.getByRole('textbox', { name: 'Instance' }).fill(instanceUrl);
      await page.getByRole('textbox', { name: 'Username' }).fill(username);
      await page.getByRole('textbox', { name: 'Password' }).fill(password);
    },
  });
});
```

The library loads `.env` automatically (via `@dotenvx/dotenvx`) so `process.env` values are available without extra setup. In CI, set these as GitHub Actions secrets instead.

### 3. Point the config at the custom install

```typescript
export default defineFoundryConfig({
  appInstallDir: './tests',
});
```

**How to discover field names:** Use Playwright MCP to take a snapshot of the install page and inspect the form fields. See [debugging-with-mcp.md](references/debugging-with-mcp.md).

### Disabling Workflow Provisioning

Apps with workflows that require valid API credentials will fail during install if you provide fake credentials for the configuration screen. Some workflows are also long-running (e.g., Anomali ThreatStream ingestion) and shouldn't be provisioned during testing because they'll start automatically. Use `AppBuilderPage.disableWorkflowProvisioning()` before install to skip provisioning:

```typescript
import { test as setup } from '@playwright/test';
import { AppBuilderPage, AppCatalogPage, config } from '@crowdstrike/foundry-playwright';

setup('install app', async ({ page }) => {
  setup.setTimeout(300000);
  const appBuilder = new AppBuilderPage(page);
  await appBuilder.disableWorkflowProvisioning(config.appName);

  const catalog = new AppCatalogPage(page);
  await catalog.installApp(config.appName);
});
```

This navigates to the App Builder, finds the app, toggles off workflow provisioning for each workflow, and saves. Call it before `installApp()` in your custom `app-install.setup.ts`.

### Multi-Screen Configuration Wizards

Some apps have settings spread across multiple screens (e.g., Workday with 4 screens, SailPoint with 3). Navigate between screens using the "Next setting" button:

```typescript
import { test as setup } from '@playwright/test';
import { AppBuilderPage, AppCatalogPage, config } from '@crowdstrike/foundry-playwright';

setup('install app', async ({ page }) => {
  setup.setTimeout(300000);
  const appBuilder = new AppBuilderPage(page);
  await appBuilder.disableWorkflowProvisioning(config.appName);

  const catalog = new AppCatalogPage(page);

  await catalog.installApp(config.appName, {
    configureSettings: async (page) => {
      const nextButton = page.getByRole('button', { name: 'Next setting' });

      // Screen 1: First API integration settings
      await page.getByRole('textbox', { name: 'Name' }).fill('My Integration');
      await page.getByRole('textbox', { name: 'Host' }).fill('https://api.example.com');
      await nextButton.click();
      await page.waitForLoadState('networkidle').catch(() => {});

      // Screen 2: Authentication settings
      await page.getByRole('textbox', { name: 'Client ID' }).fill(process.env.CLIENT_ID!);
      await page.getByRole('textbox', { name: 'Client Secret' }).fill(process.env.CLIENT_SECRET!);
      await nextButton.click();
      await page.waitForLoadState('networkidle').catch(() => {});

      // Screen 3: Additional settings (last screen — "Install app" button is visible here)
      await page.getByRole('textbox', { name: 'Tenant ID' }).fill(process.env.TENANT_ID!);
    },
  });
});
```

The `waitForLoadState('networkidle').catch(() => {})` after each "Next setting" click gives the next screen time to load. The `.catch(() => {})` prevents failures if the page is already idle.

## Custom Page Objects

For app-specific UI that the library doesn't cover, extend `BasePage`:

```typescript
import { Page, expect } from '@playwright/test';
import { BasePage, AppCatalogPage, config } from '@crowdstrike/foundry-playwright';

export class MyAppPage extends BasePage {
  constructor(page: Page) {
    super(page, 'MyAppPage'); // display name for logging only
  }

  protected getPagePath(): string {
    throw new Error('Direct path navigation not supported. Use navigateToInstalledApp() instead.');
  }

  protected async verifyPageLoaded(): Promise<void> {
    await this.page.locator('h1').filter({ hasText: /My App/i }).waitFor();
  }

  async navigateToInstalledApp(): Promise<void> {
    return this.withTiming(async () => {
      const catalog = new AppCatalogPage(this.page);
      await catalog.navigateToInstalledApp(config.appName);
      await this.verifyPageLoaded();
    }, 'Navigate to installed app');
  }

  async verifyAppContent(): Promise<void> {
    return this.withTiming(async () => {
      const iframe = this.page.frameLocator('iframe[name="portal"]');
      const heading = iframe.getByRole('heading', { name: /My App/i });
      await expect(heading).toBeVisible({ timeout: 10000 });
    }, 'Verify app content');
  }
}
```

Foundry app page URLs contain deployment-specific IDs that change on every deploy, so never hardcode paths. Use `AppCatalogPage.navigateToInstalledApp()` to navigate via the App Catalog menu instead.

`BasePage` gives you `smartClick()`, `withTiming()`, `navigateToPath()`, `elementExists()`, a `logger`, and a `waiter` (SmartWaiter instance).

Add the custom page to your fixtures alongside library page objects.

## Debugging with Playwright MCP

Playwright MCP is invaluable for writing and debugging e2e tests. See [references/debugging-with-mcp.md](references/debugging-with-mcp.md) for detailed patterns.

**Key principle:** When using Playwright MCP interactively, authentication is manual. Navigate to the Falcon login page, then tell the user: *"Please log in to Falcon in the browser, then let me know when you're ready."* Do not attempt automated TOTP login through MCP.

## CI with GitHub Actions

The sample apps use a shared `e2e.yml` workflow pattern. Rather than duplicating it here (where it would go stale), reference the canonical implementation:

**Reference:** [`foundry-sample-functions-python/.github/workflows/e2e.yml`](https://github.com/CrowdStrike/foundry-sample-functions-python/blob/main/.github/workflows/e2e.yml)

### Key CI concepts

1. **Concurrency serialization**: Only one e2e run per repo at a time (prevents deployment collisions)
2. **Unique app names**: CI generates a unique name from repo + actor + timestamp to avoid conflicts
3. **Manifest ID stripping**: `yq -i 'del(.. | select(has("id")).id) | del(.. | select(has("app_id")).app_id)' manifest.yml`
4. **Deploy → wait → release → test → cleanup**: The workflow deploys, polls for success, releases, runs tests, then always deletes the app
5. **App cleanup**: `foundry apps delete -f` runs in an `always()` step so apps are cleaned up even on failure

### Required GitHub secrets

| Secret | Purpose |
|--------|---------|
| `FOUNDRY_API_CLIENT_ID` | Foundry CLI authentication |
| `FOUNDRY_API_CLIENT_SECRET` | Foundry CLI authentication |
| `FOUNDRY_CID` | CrowdStrike Customer ID |
| `FOUNDRY_CLOUD_REGION` | Cloud region (us-1, us-2, eu-1) |
| `FALCON_USERNAME` | Falcon console login for Playwright |
| `FALCON_PASSWORD` | Falcon console password |
| `FALCON_AUTH_SECRET` | TOTP secret for 2FA |

### CI-specific behavior

The library detects `CI=true` and adjusts:
- Higher timeouts (60s default vs 45s local)
- Retries enabled (2 retries vs 0 local)
- `.env` loading skipped (credentials come from environment)

## `defineFoundryConfig()` Options

| Option | Type | Default |
|--------|------|---------|
| `testDir` | `string` | `'./tests'` |
| `appInstallDir` | `string` | Library built-in (override for apps with config screens) |
| `timeout` | `number` | 60s (CI) / 45s (local) |
| `retries` | `number` | 2 (CI) / 0 (local) |
| `reporter` | `string` | `'list'` |
| `use` | `object` | Merged with defaults (`testIdAttribute: 'data-test-selector'`) |
| `projects` | `array` | Replaces the default 4-project pipeline if provided |

### Sidebar navigation flakiness

The Falcon sidebar menu re-renders during navigation, which can detach DOM elements mid-click and cause intermittent timeouts. This affects any test that navigates through the sidebar (detections, workflows, host management, etc.). The library's navigation methods include retry logic for this, but with `retries: 0` locally, a single re-render failure will fail the test.

For apps that navigate through the sidebar, set `retries: 2` to handle this reliably:

```typescript
export default defineFoundryConfig({ retries: 2 });
```

## Common Pitfalls

| Problem | Cause | Fix |
|---------|-------|-----|
| "Could not find app in catalog" | `APP_NAME` doesn't match the manifest `name` | Ensure `.env` APP_NAME matches `manifest.yml` name field |
| Install button stays disabled | App has config screens (API integrations) | Create custom `app-install.setup.ts` with `configureSettings()` |
| "collection existed previously but was deleted" | Stale IDs in manifest from a previous deployment | Strip all IDs: `yq -i 'del(.. \| select(has("id")).id) \| del(.. \| select(has("app_id")).app_id)' manifest.yml` |
| Tests fail on first run after deploy | Release not propagated yet | Wait 15-30s after release before running tests; CI workflow includes a sleep |
| Tests pass locally but fail in CI | Different timeout/retry settings | Check `CI=true` is set; library auto-adjusts timeouts |
| Login fails with account lockout | Running `npm test` in multiple apps simultaneously | Run tests for one app at a time. Concurrent login attempts against the same Falcon account trigger rate-limiting and temporarily lock the account. |

## Reference Implementations

All [CrowdStrike/foundry-sample-*](https://github.com/CrowdStrike?q=foundry-sample) apps have e2e tests using this library:

| App | Highlights |
|-----|------------|
| [foundry-sample-functions-python](https://github.com/CrowdStrike/foundry-sample-functions-python/tree/main/e2e) | `configureSettings()`, workflows, extension, host details |
| [foundry-sample-mitre](https://github.com/CrowdStrike/foundry-sample-mitre/tree/main/e2e) | Custom page objects (`MitreChartPage`), parallel tests |
| [foundry-sample-anomali-threatstream](https://github.com/CrowdStrike/foundry-sample-anomali-threatstream/tree/main/e2e) | API integration config |
| [foundry-sample-category-blocking](https://github.com/CrowdStrike/foundry-sample-category-blocking/tree/main/e2e) | UI page testing |
| [foundry-sample-charlotte-toolkit](https://github.com/CrowdStrike/foundry-sample-charlotte-toolkit/tree/main/e2e) | Charlotte AI toolkit |
| [foundry-sample-collections-toolkit](https://github.com/CrowdStrike/foundry-sample-collections-toolkit/tree/main/e2e) | Collection CRUD |
| [foundry-sample-detection-translation](https://github.com/CrowdStrike/foundry-sample-detection-translation/tree/main/e2e) | Detection extension |
| [foundry-sample-foundryjs-demo](https://github.com/CrowdStrike/foundry-sample-foundryjs-demo/tree/main/e2e) | Foundry-JS demo |
| [foundry-sample-idp-notifications](https://github.com/CrowdStrike/foundry-sample-idp-notifications/tree/main/e2e) | IDP notifications |
| [foundry-sample-insider-risk-sailpoint](https://github.com/CrowdStrike/foundry-sample-insider-risk-sailpoint/tree/main/e2e) | SailPoint integration |
| [foundry-sample-insider-risk-workday](https://github.com/CrowdStrike/foundry-sample-insider-risk-workday/tree/main/e2e) | Workday integration |
| [foundry-sample-logscale](https://github.com/CrowdStrike/foundry-sample-logscale/tree/main/e2e) | LogScale data ingestion |
| [foundry-sample-ngsiem-importer](https://github.com/CrowdStrike/foundry-sample-ngsiem-importer/tree/main/e2e) | Next-Gen SIEM importer |
| [foundry-sample-openrouter-toolkit](https://github.com/CrowdStrike/foundry-sample-openrouter-toolkit/tree/main/e2e) | OpenRouter AI toolkit |
| [foundry-sample-rapid-response](https://github.com/CrowdStrike/foundry-sample-rapid-response/tree/main/e2e) | Rapid response |
| [foundry-sample-scalable-rtr](https://github.com/CrowdStrike/foundry-sample-scalable-rtr/tree/main/e2e) | Scalable RTR |
| [foundry-sample-servicenow-idp](https://github.com/CrowdStrike/foundry-sample-servicenow-idp/tree/main/e2e) | ServiceNow IDP |
| [foundry-sample-servicenow-itsm](https://github.com/CrowdStrike/foundry-sample-servicenow-itsm/tree/main/e2e) | ServiceNow ITSM |
| [foundry-sample-threat-intel](https://github.com/CrowdStrike/foundry-sample-threat-intel/tree/main/e2e) | Threat intelligence |
| [foundry-sample-zscaler-internet-access](https://github.com/CrowdStrike/foundry-sample-zscaler-internet-access/tree/main/e2e) | Zscaler integration |

## Integration with Other Skills

- **development-workflow**: E2E testing is delegated from the orchestrator when users request it
- **ui-development**: Tests verify UI pages and extensions render correctly in the Falcon console
- **workflows-development**: Tests verify workflow execution and completion
- **debugging-workflows**: Use for deploy/release issues that block testing
