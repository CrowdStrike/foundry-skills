# Function Runtime Debugging

When a deployed function returns unexpected results or errors:

**Step 1: Execute and observe**
```bash
foundry functions exec --handler <handler> --logs '{"test": "input"}' --no-prompt
```

Note the exec_id and status code from the output.

**Step 2: Retrieve logs if not already displayed**
```bash
foundry functions logs <exec_id>
```

Logs arrive 5-10 minutes after execution via the Firehose pipeline. The CLI polls automatically with a countdown.

**Step 3: Correlate logs against source**

The function source lives at the path in `manifest.yml`:
```yaml
functions:
  - name: my-function
    path: functions/my-function
    handlers:
      - name: my_handler
        method: POST
        api_path: /api/process
```

Read the handler source and compare against log timestamps and error messages.

**Step 4: Common runtime failures**

| Log Pattern | Likely Cause | Fix |
|-------------|-------------|-----|
| `ImportError: No module named X` | Missing from `requirements.txt` | Add dependency, redeploy |
| `KeyError: 'field'` | Missing field in request body | Add input validation |
| `403` with `access denied, scope not permitted` | Scope missing from `auth.scopes`, or the update that adds it not yet accepted | Add the scope, deploy, release, and accept the update in the App Catalog |
| `401 Unauthorized` on every call, scopes correct | FalconPy client constructed at module scope (no request token at import) | Construct the client inside the handler |
| `403` with `app is not installed` | App deployed but not released and installed | `foundry apps release`, then install from the App Catalog |
| `Timeout` / no logs appear | Function exceeded `max_exec_duration_seconds` | Increase timeout or optimize |
| Status 202, no result | Async execution | Poll: `foundry functions exec status <exec_id>` |
| Logs say "available" but empty | Logs not yet in pipeline | Wait 5-10 min or use `--refresh` |

**Step 5: Fix, redeploy, verify**
```bash
# After fixing the code:
foundry apps deploy --change-type Patch --change-log "fix handler error" --no-prompt

# Re-execute to verify
foundry functions exec --handler <handler> --logs '{"test": "input"}' --no-prompt
```
