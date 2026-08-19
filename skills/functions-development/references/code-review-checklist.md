## Reviewing Function Code

Whenever you write or modify function handler code — and always before recommending a deploy — review it. This is a manual review you perform by reading the source code. Do a normal code review (correctness, error handling, resource cleanup, idiomatic SDK usage), **plus** the following function-specific checks below. Surface findings to the developer as warnings; do not auto-fix sensitive-data issues without confirming.

### 1. Logging adequacy — especially error paths

Foundry functions are debugged after the fact through `foundry functions logs <exec_id>` or by querying from the customer log repo through Falcon. If the code failed silently, the logs are empty and neither you nor the developer can tell what went wrong. **Warn the developer when important code paths are not adequately logged.** Check that:

- **Every error/exception path logs before returning or raising if the error returned is not surfacing enough details.** A `catch`/`except` that swallows an error, or an early `return Response(code=500)` with no preceding `logger.error(...)`, is the most important thing to flag — that is exactly the case that will be impossible to debug later.
- Failures log **actionable context**, not just `"error"` — include the operation attempted and identifiers (e.g. `logger.error("collection write failed for host_id=%s: %s", host_id, err)`), but see the sensitive-data check below for what NOT to log.
- External calls (Falcon API, API-integration proxy, collection ops) log on failure, and ideally a debug/info line on entry so the sequence of events is reconstructable.
- Non-trivial branches (validation rejections, early returns, retries) emit at least one log line, so a 4xx/short-circuit is distinguishable from a crash in the logs.

Handlers receive a `logger` parameter (Python `logging.Logger`, Go `*slog.Logger`) — flag handlers that never use it, and error branches that don't.

When you flag a gap, explain the payoff: adequate logs are what let the debugging workflow (below) correlate a failure against the code.

### 2. Sensitive information — hardcoded secrets and PII

**Warn on anything sensitive that is hardcoded in source or would be written to logs/responses.** There is no secrets management in Foundry, so a hardcoded credential is unencrypted and visible in app exports. Review for:

- **Hardcoded credentials/secrets:** API keys, bearer tokens, OAuth client secrets, passwords, private keys, connection strings, webhook URLs with embedded tokens. Flag string literals that look like secrets (long high-entropy strings, `sk-`/`xox`-style prefixes, `Authorization: Bearer <literal>`). These belong in an **API integration** (platform-managed) — never in `os.environ` defaults or source. See [Credential Management](#credential-management--no-secrets-system-exists) and [security-patterns](../../security-patterns/SKILL.md).
- **PII / sensitive data in logs or error messages:** email addresses, usernames, IPs tied to people, tokens, request bodies dumped wholesale, or full API responses logged at info level. Logging must be actionable without leaking — log identifiers and operation names, not raw credential values or personal data. This directly reinforces the security checklist item *"no sensitive data in error messages or logs."*
- **Secrets echoed back to the caller:** a handler that returns config values, env contents, or upstream auth headers in its response body.

### 3. Request / response schema coverage

Schemas bind only at creation time (see [Function I/O Schemas](#function-io-schemas--required-at-creation-time)), so review is the main safety net for catching gaps and drift *after* a function exists. Schemas are **optional in general** — a function invoked only via `exec`/`test`/API paths may legitimately have none. Check that:

- **Workflow-exposed handlers have both a `request_schema` and `response_schema`.** Only flag a missing/`null` schema when the handler is workflow-exposed (`workflow_integration` present) — there, a missing `response_schema` makes the Fusion action emit no usable output while still appearing to succeed. For handlers that are *not* workflow-exposed, a missing schema is fine; do not flag it. Since schemas can't be added by editing the manifest, if a workflow-exposed handler is missing one, warn the developer that closing the gap requires recreating the function.
- **If a schema is present, validate it against the handler's actual I/O.** When a `request_schema`/`response_schema` exists, read the schema file and the handler source together and flag drift: request fields the handler reads (`request.body.get("x")`, `r.Body.X`) that the `request_schema` doesn't declare, or fields the handler returns in its `Response`/`fdk.JSON` body that the `response_schema` omits. A stale schema silently drops fields at the workflow boundary. If no schema is present, skip this check.
- **The handler validates inputs at runtime — do not rely on the schema to reject bad input.** This applies whether or not a schema exists. A `request_schema` (when present) describes the shape for the workflow engine; it is not a guarantee the handler receives validated data (functions are also invoked directly via `exec`, `test`, and API paths). Confirm the handler checks required fields, types, and bounds and returns a 4xx on violation — this is the "Apply input validation before processing any request" rule from the top of this skill. A handler that trusts `request.body` without checks is a finding.

For a full pre-deploy security pass (OAuth scopes, input validation, collection sanitization), hand off to [security-patterns](../../security-patterns/SKILL.md) — this review covers the function-source subset.

