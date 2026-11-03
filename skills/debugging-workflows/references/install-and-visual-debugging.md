# Debugging App Install Failures

When a Foundry app fails to install with no useful error message, isolate the problem by testing each component in the Falcon console:

1. **Test the API integration first** — In the Falcon console, use the credentials from the install config to test the operation directly (e.g., run `listUsers` with the Okta domain and API key). This proves whether the spec and credentials work independently of the app.

2. **Eliminate unlikely suspects** — Static UI files (extensions, pages) don't cause install failures. If the API integration works, the problem is almost certainly in a workflow.

3. **Inspect the workflow in the console** — Open Falcon Fusion SOAR, edit the workflow, and look at each action's configuration. The workflow editor shows validation errors (like unknown variable references in CEL expressions) that the install API doesn't surface.

> **Example:** Apps failed to install with no detail. API integration tested fine. Editing the workflow in the console revealed "unknown variable" on the Print data action — the CEL variable path was missing the `Custom_` prefix the platform adds to all API integration names. The install error gave no hint; the workflow editor showed it immediately.

## A Function Action That Never Registered

`foundry apps validate` passes and `deploy` reports success, yet install fails the same way across releases whose changes have nothing to do with it. In the workflow editor, a node that calls the app's own function (`functions.<name>.<handler>`) shows one of these, though no Store plugin or subscription is involved:

- `Requires a plugin configuration. Add this via the CrowdStrike Store or select a different action.`
- `missing required subscription to use action '<handler>' on node <node>`

That handler's `workflow_integration` action is missing from the CID's action catalog. Deploy doesn't report it, `foundry apps logs` may show nothing, and redeploying the same `workflow_integration` `id` keeps it broken. A workflow with `provision_on_install: true` that calls the handler then fails every install. This was seen after consolidating functions, on handlers whose IDs changed. Other handlers with identical manifest entries resolved.

Recover in three releases:

1. Set `provision_on_install: false` on each workflow that calls the handler. Deploy and release. The app installs, with those workflows not created.
2. In `manifest.yml`, set that handler's `workflow_integration` `id` to `""`. Deploy and release. The deploy writes a new `id` back to `manifest.yml`, and workflows keep working because they call the handler by name (`functions.<name>.<handler>`), not by `id`. Check that the editor now resolves the node.
3. Set `provision_on_install: true` again. Deploy and release.

## Visual Debugging with Screenshots

Claude Code can read images directly. When the Falcon console shows something unexpected — a blank page, an error modal, a disabled button — a screenshot is often the fastest way to diagnose the issue.

**Without Playwright MCP (fastest):** Ask the user to take a screenshot of what they're seeing and paste or drag it into the conversation. Claude reads it immediately and can identify error messages, missing elements, wrong page states, or styling issues without any setup.

**With Playwright MCP:** If Playwright MCP is configured (`claude mcp add playwright -- npx @playwright/mcp@latest`), Claude can take screenshots directly via `browser_take_screenshot`. This is useful for interactive debugging sessions. See `e2e-testing/references/debugging-with-mcp.md` for details.

**From test failure artifacts:** When e2e tests fail, Playwright saves screenshots to `test-results/`. Read the `.png` file directly — it shows the exact page state at the moment of failure.

Screenshots are particularly effective for:
- Blank pages after deploy (missing iframe, broken Vite config)
- Extension buttons that don't appear or expand
- Error banners or modals with messages not surfaced by the CLI
- `foundry ui run` rendering issues (dark mode, missing Shoelace styles)
- App install dialogs with unexpected form fields
