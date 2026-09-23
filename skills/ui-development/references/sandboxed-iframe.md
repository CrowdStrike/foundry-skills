# Sandboxed Iframe Restrictions

Pages and extensions run in an iframe with `sandbox="allow-scripts allow-forms allow-downloads"`. Two missing flags change how browser code behaves, and the page's lifetime limits any work it drives.

## No `allow-same-origin`: Web Storage Throws

Without `allow-same-origin`, the document's origin is opaque, so `localStorage` and `sessionStorage` are not merely empty — any access throws:

```
SecurityError: Failed to read the 'localStorage' property from 'Window': The document is sandboxed and lacks the 'allow-same-origin' flag.
```

Keep UI state in memory (React/Vue state, a module-level object) for the life of the page, and use a foundry-js collection for anything that must persist across loads or users. If you are porting code that already uses Web Storage, wrap each call in `try/catch` and fall back to an in-memory map rather than letting the first read take the page down:

```javascript
const storage = {
  mem: {},
  get(k) { try { return localStorage.getItem(k); } catch { return this.mem[k] ?? null; } },
  set(k, v) { try { localStorage.setItem(k, v); } catch { this.mem[k] = v; } },
};
```

The same opaque-origin restriction applies to `document.cookie` and `indexedDB`.

## No `allow-modals`: Dialogs Are Silently Ignored

Without `allow-modals`, the browser ignores `alert()`, `confirm()`, `prompt()`, and the `beforeunload` leave-page prompt. Nothing throws; Chrome only logs a console message:

```
Ignored call to 'alert()'. The document is sandboxed, and the 'allow-modals' keyword is not set.
```

The failure is quiet, which makes it dangerous:

- `alert('Save failed: ...')` returns immediately, so an error path looks exactly like a success.
- `confirm()` returns `false`, so an action guarded by `if (confirm('Delete?'))` never runs.
- `prompt()` returns `null`.
- A `beforeunload` handler that calls `preventDefault()` never shows a prompt, so it can't stop a user from leaving mid-task.

Use in-page UI instead:

- **Errors:** show them inline, next to the control that failed (`<sl-alert variant="danger" open>` or plain text), and leave them visible until the next attempt.
- **Confirmation:** use a Shoelace `<sl-dialog>` with explicit confirm and cancel buttons, and run the action from the confirm button's handler.
- **Input:** use a form field or an `<sl-dialog>` containing one.

## Bulk Work Stops When the Page Closes

A page that loops over many items — one API or function call per item — only makes progress while it is open. Calls already in flight finish server-side, but nothing new starts once the user navigates away or closes the tab, and the leave-page prompt can't warn them (see above).

For a loop driven from the page:

- Show an on-screen notice while it runs ("Keep this page open until processing finishes").
- Save each item's result as soon as it completes (for example, to a collection), not at the end.
- Make a re-run resume: skip items that are already done, and redo everything only when all are done.
- Count failures and show the number plus the first error message. Don't skip failed items silently.

```javascript
async function processAll(items, isDone, processOne, concurrency = 8) {
  const pending = items.every(isDone) ? items : items.filter((i) => !isDone(i));
  const failures = [];
  let next = 0;
  async function worker() {
    while (next < pending.length) {
      const item = pending[next++];
      try {
        await processOne(item); // saves its own result
      } catch (err) {
        failures.push({ item, err });
      }
    }
  }
  await Promise.all(Array.from({ length: concurrency }, worker));
  return { processed: pending.length, failures };
}
```

If a job must finish even when the user leaves, move the loop server-side: trigger a Falcon Fusion workflow that iterates over the items, or schedule a workflow that calls a function to process one batch per run.
