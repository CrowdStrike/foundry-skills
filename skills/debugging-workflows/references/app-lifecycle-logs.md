# App Lifecycle Logs Reference

Record format and reason codes for `foundry apps logs`, which requires Foundry CLI 2.1.2+. See the App Lifecycle Logs section of `SKILL.md` for when to run it.

## Reading the Output

```text
2026-09-16 10:08:00  INFO   deploy  The app deployment started.  [reason=DEPLOY_STARTED]
2026-09-16 10:08:04  ERROR  deploy  The artifact failed validation.  [artifact=overview(UI_DASHBOARD) reason=ARTIFACT_VALIDATION_FAILED fix=customer fields=items version=1.0.3 trace=7c1f2ab99d3e4f10]
                                    ↳ 1. Open the artifact's definition in your app package, starting with any fields named on this record.
                                      2. Correct it so that it can be read and matches the expected structure.
                                      3. Redeploy the app.
2026-09-16 10:08:05  ERROR  deploy  The app deployment failed.  [reason=DEPLOY_FAILED fix=unclear version=1.0.3 trace=7c1f2ab99d3e4f10]
                                    ↳ 1. Look for another record from this deployment with a more specific reason.
                                      2. Address what that record reports, then redeploy.
```

Columns are timestamp (UTC), level, operation and message, followed by the actionable context in brackets:

- `artifact=` — which artifact, by manifest name and type. This is what to open next.
- `reason=` — the stable code to act on, shown when it adds to the message.
- `fix=` — who can act on the failure: `customer` (yours to fix), `crowdstrike` (not fixable in the app — escalate), `unclear` (unattributed — look for a more specific record first). Omitted on success records, where there is nothing to fix.
- `fields=` — the parts of your own file the platform rejected, comma-separated: a JSON field path, an archive entry, a spec path. In practice this appears on `ARTIFACT_VALIDATION_FAILED`, and only when the failure could be narrowed to a named part — its absence does not mean the file is fine.
- `version=` — the deployment version the record belongs to.
- `http=` — upstream status, when the failure came from a call.
- `trace=` — quote this when escalating to support. Shown on `warn` and `error` only.

Indented `↳` lines are the platform's own remediation steps for that reason, shown once per reason per invocation — a deploy that fails the same way on six artifacts prints them once. They are joined onto each record as it is read, so they reflect the platform's current guidance rather than whatever was true when the record was written. **Prefer them over the Action column below**, which is a local summary and can lag.

Levels are colored in a terminal and plain when piped, so the output is safe to parse.

Records print oldest first, so an operation reads as a narrative. The last line is usually the generic summary; the first `ERROR` is the cause.

## Reason Codes

**This table is a snapshot of a vocabulary that grows, not a closed set.** A code missing from it means this file is behind the platform — not that the record is invalid or the CLI is out of date. Every record carries its own `fix=` and `↳` steps, joined from the platform's live catalog when the record is read, so an unlisted code is still actionable without this table. Use the table to confirm and to add local context; use the record to decide. See the SKILL.md section on reasons and operations this skill does not list for how to place an unfamiliar code by the shape of its name.

| Reason | Meaning | Action |
|---|---|---|
| `ARTIFACT_VALIDATION_FAILED` | An artifact's own definition was rejected — unreadable, or readable but the wrong shape | Open the artifact named by `artifact=`, at the path in `fields=`. For OpenAPI, lint with `npx @redocly/cli lint` |
| `INVALID_MANIFEST` | Manifest or artifact manifest is malformed | `foundry apps validate --no-prompt`, fix the YAML |
| `VALIDATION_FAILED` | A request was rejected as invalid. Not artifact-scoped — for a rejected artifact definition see `ARTIFACT_VALIDATION_FAILED` | Check the request against the app's schema, starting with any `fields=` |
| `ARTIFACT_DISTRIBUTION_FAILED` | An artifact failed to distribute | Read the named artifact, then retry the deploy |
| `ARTIFACT_SAVE_FAILED` | A build-time artifact change failed, before any deploy | Retry the save in App Builder; check `http=` for the downstream rejection |
| `PERMISSION_DENIED` | Operation not permitted | Review manifest `oauth` scopes; confirm the tenant has the required module (SKU) |
| `NOT_FOUND` | A required resource is missing | Check IDs in the manifest; on a new cloud, strip cloud-specific IDs first |
| `DEPENDENCY_UNREACHABLE` | An upstream dependency was unreachable | Usually transient; retry, then check the API integration's host |
| `RATE_LIMITED` | Operation was rate limited | Wait, then retry |
| `TIMEOUT` | Operation timed out | Reported as `fix=crowdstrike`, so retry first; for a function, also check `max_exec_duration_seconds` |
| `INTERNAL_ERROR` | Failure inside the platform, not the app | Not fixable in the app — retry, then escalate with the trace ID |
| `UNKNOWN` | Unclassified failure | Escalate with the trace ID |
| `APP_METADATA_UPDATE_FAILED` | Editing app details failed | Check the name, description and logo in the request |
| `CREATE_FAILED`, `DEPLOY_FAILED`, `RELEASE_FAILED`, `PUBLISH_FAILED`, `INSTALL_FAILED`, `INSTALL_UPDATE_FAILED`, `UNINSTALL_FAILED`, `DELETE_FAILED` | The operation's summary record | A summary, not a cause — these carry `fix=unclear`; find the earlier artifact-scoped error |

Progress and success codes carry `fix=none`, so they print with no `fix=` part. The rule runs both ways and does not go stale: **any `info` record printing without a `fix=` part is progress or success**, including a code not listed here. Read it together with the level — on an `error` record a missing `fix=` means the platform has a reason it has not described, which is a gap worth reporting with the trace ID, not a success. Today's set is `APP_CREATED`, `APP_DELETED`, `APP_METADATA_SAVED`, `DEPLOY_STARTED`, `DEPLOY_DISTRIBUTIONS_SENT`, `ARTIFACTS_DISTRIBUTED`, `RELEASE_STARTED`, `RELEASE_SUCCEEDED`, `PUBLISH_SUBMITTED`, `IMPORT_SUCCEEDED`, `INSTALL_STARTED`, `INSTALL_SUCCEEDED`, `INSTALL_UPDATE_STARTED`, `INSTALL_UPDATE_SUCCEEDED`, `UNINSTALL_STARTED`, `UNINSTALL_SUCCEEDED`. These are the healthy narrative. Their absence is itself a signal, but an ambiguous one: a `DEPLOY_STARTED` with no terminal record means the operation is still running *or* failed in a way that is not recorded. Confirm which with `foundry apps list-deployments`.

**Several of them mean "accepted", not "done."** `DEPLOY_DISTRIBUTIONS_SENT` means the deploy was accepted and distribution requests were published; the per-artifact outcome arrives afterwards under the same `operation=deploy` but with an `artifact=` in the context. `APP_DELETED`, `INSTALL_SUCCEEDED`, `INSTALL_UPDATE_SUCCEEDED` and `UNINSTALL_SUCCEEDED` likewise report acceptance. Read the message, not just the code.

## Artifact Types

`--artifact-type` takes the platform's enum names. New artifact types ship regularly, so this list is a snapshot too — read the value off an existing record's `artifact=` rather than typing one from here:

`API_INTEGRATION`, `FAAS_FUNCTION`, `CUSTOM_OBJECT_COLLECTION`, `WORKFLOW_PLAYBOOK`, `SYSTEM_WORKFLOW`, `UI_PAGE`, `UI_EXTENSION`, `UI_DASHBOARD`, `UI_NAVIGATION`, `RTR_SCRIPT`, `LOG_SCALE_SAVED_SEARCH`, `LOG_SCALE_VIEW`, `LOG_SCALE_PARSER`, `LOG_SCALE_LOOKUP_FILE`, `DATA_CONNECTOR_PUSH`, `DATA_CONNECTOR_PULL`, `APP_DOCUMENTATION`, `AI_AGENT`, `AI_KNOWLEDGE_BASE`, `WEBHOOK`, `AUTH`, `AUTH_ROLE`, `AUTH_PERMISSION`

Read the value off an existing record's `artifact=` rather than guessing — the filter is an exact match, so a near-miss returns nothing rather than erroring.

## When There Are No Records

An empty result is not proof the app is healthy. Check, in order:

1. **Asked too early** — records are indexed asynchronously, so an operation that just finished may not be queryable yet. Re-read at a 10-second interval for up to ~3 minutes before concluding anything. This is first on the list because it is the only cause that resolves on its own, and the only one where changing the query or the app is wasted work
2. **Window too short** — the default is 24 hours; widen with `--since 168h`. There is no server-side cap on the window, but records older than the log store's retention return nothing however far back you ask
3. **Filters too narrow** — drop `--level` or `--deployment-id` and retry. A deploy rejected at validation has no deployment ID on its app-scoped records, so filter by `--deployment-version` instead. A filter value the platform does not recognize matches nothing silently, so check spelling before widening
4. **Never deployed** — records begin at the first deploy; confirm with `foundry apps list-deployments`
5. **Wrong app** — outside an app directory `--app-id` is required; inside one, confirm the manifest's `app_id` is the app you mean. A nonexistent app ID returns empty rather than an error, so a typo is indistinguishable from a quiet app

Absence of a record does not prove absence of the operation: artifact execution is not instrumented, and a release that stops at an MFA challenge writes no terminal record.
