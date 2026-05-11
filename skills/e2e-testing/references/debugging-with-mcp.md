# Debugging E2E Tests with Playwright MCP

Playwright MCP provides browser automation tools that are invaluable for writing and debugging Foundry e2e tests.

## Setup

Add the Playwright MCP server to Claude Code:

```bash
claude mcp add playwright -- npx @playwright/mcp@latest
```

This gives Claude access to browser automation tools (`browser_navigate`, `browser_snapshot`, `browser_click`, etc.) for interactive debugging.

## Interactive Login

When using Playwright MCP to debug tests interactively, authentication is manual. The automated TOTP flow used by `npm test` does not apply in MCP sessions.

**Pattern:**

1. Navigate to the Falcon console login page:
   ```
   browser_navigate: https://falcon.us-2.crowdstrike.com
   ```

2. **Pause and ask the user to log in manually:**
   > "Please log in to Falcon in the browser, then let me know when you're ready."

3. Once the user confirms, continue with test actions.

This pause-and-wait pattern applies every time you start a new MCP debugging session. Never attempt to fill login forms or generate TOTP codes through MCP.

## Inspecting Page State

### Snapshots (preferred over screenshots)

```
browser_snapshot
```

Returns an accessibility tree of the current page. Use this to:
- Find exact button names, roles, and `aria-expanded` states for extension buttons
- Discover form field labels for `configureSettings` callbacks
- Verify element visibility without visual inspection
- Get `ref` values for clicking elements

### Screenshots

```
browser_take_screenshot
```

Use when you need to see visual layout, loading states, or verify styling. Always capture at 2x DPR for retina displays (Playwright MCP's default).

**Screenshots are extremely effective for debugging Falcon console issues.** When something looks wrong — a blank page, a missing extension, an unexpected error banner — take a screenshot and Claude can read it directly. This is often faster than inspecting the DOM because the Falcon console's visual state (loading spinners, error modals, disabled buttons) tells you immediately what's wrong.

**Pattern: Screenshot-driven debugging**
1. Navigate to the page where the issue occurs
2. Take a screenshot: `browser_take_screenshot`
3. Claude reads the image and identifies the problem (error message, missing element, wrong page state)
4. Fix the test or app code based on what's visible
5. Repeat until the page looks correct

## Finding Errors

### Console messages

```
browser_console_messages: { level: "error" }
```

Check for JavaScript errors that might cause blank pages, failed API calls, or broken extensions.

### Network requests

```
browser_network_requests: { static: false, requestBody: false, requestHeaders: false }
```

Look for failed API calls (4xx/5xx status codes) that might explain missing data or broken workflows.

## Debugging Failing Tests

### Read test failure artifacts

When a test fails, Playwright saves artifacts to `test-results/`:

```
test-results/
├── test-name/
│   ├── test-failed-1.png      # Screenshot at failure
│   ├── video.webm              # Full test video
│   └── error-context.md        # Error details with call log
```

Read `error-context.md` first for a quick diagnosis. The call log shows exactly which locator failed and what the page state was.

### Read the screenshot

```
Read: test-results/<test-dir>/test-failed-1.png
```

Claude Code can read images directly — this is one of the most powerful debugging tools available. The screenshot shows the exact page state at the moment of failure: error modals, blank iframes, disabled buttons, loading spinners, or unexpected page content. Often a single screenshot is enough to identify the root cause without any further investigation.

### Common debugging scenarios

**Extension button not found:**
1. Navigate to detection details via MCP
2. Take a snapshot to see all buttons
3. Check the exact extension name (case-sensitive by default)

**Install button disabled:**
1. Navigate to the app install page via MCP
2. Take a snapshot to see form fields
3. Note the exact field labels (Name, Instance, Username, Password)
4. Create a `configureSettings` callback that fills these fields

**Workflow execution fails:**
1. Navigate to the workflow via MCP
2. Open the execution modal
3. Check if input parameters are required
4. Verify the workflow name matches exactly (including capitalization)

## Tips

- **Snapshots over screenshots:** Snapshots are faster, text-searchable, and give you `ref` values for interacting with elements.
- **Check `aria-expanded`:** Extension buttons and menu items use `aria-expanded` to indicate state. The library checks this automatically.
- **Wait for navigation:** After clicking links in the Falcon console, use `browser_wait_for` to confirm page transitions before taking snapshots.
- **Read existing test-results:** If a test just failed, read the artifacts before launching MCP. The answer is often in the screenshot or error context.
