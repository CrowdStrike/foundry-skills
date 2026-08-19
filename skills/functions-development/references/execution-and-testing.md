## Function Execution & Debugging

> **Requires Foundry CLI 2.1.0+.** The commands in this section (`foundry functions exec`, `test`, `logs`) do not exist in CLI 2.0.x. If the user's CLI is below 2.1.0, inform them and offer to upgrade: `brew upgrade crowdstrike/foundry-cli/foundry`. Do not attempt these commands on an older CLI.

> **⚠️ DEPLOY FIRST — `exec` and `test` run against the deployed Lambda, not local code.**
>
> `foundry functions exec` and `test` execute the **deployed** function artifact. Local edits are NOT reflected until you deploy.
>
> **This deploy-first check applies ONLY to `exec` and `test`.** The read-only commands `exec status`, `exec list`, and `logs` operate on an **existing exec ID** that was already run against a deployed function — they do NOT compare local files, do NOT trigger the deployment check, and must NOT prompt for a deploy. Never pass `--ignore-deploy-warning` to them (it isn't a valid flag there). Run them freely regardless of local changes.
>
> **NEVER deploy automatically. Deploying pushes code to the customer's cloud tenant — it is a state-changing action the user must consent to.**
>
> **For `exec` and `test` only, the CLI auto-detects undeployed local changes** (it compares local files against the last deployment). When changes are detected:
> - **Interactively**, it prints a warning and prompts to confirm before proceeding.
> - **With `--no-prompt`** (how this skill always runs it), it prints the warning and then **hard-errors** — it will NOT run unless you pass `--ignore-deploy-warning`.
>
> **Before running exec or test:**
> 1. If the user just edited the handler/function, assume local changes are undeployed.
> 2. If a deploy is likely needed, **ask the user for confirmation first**, and explain *why*: "Your local changes to `<function>` won't be reflected until deployed. `exec`/`test` runs against the deployed version. Would you like me to run `foundry apps deploy` before testing, or run against the currently-deployed version anyway?"
> 3. Only run `foundry apps deploy --change-type Patch --change-log "..." --no-prompt` **after** the user confirms.
> 4. If the user wants to run against the **currently-deployed** version despite local edits, pass `--ignore-deploy-warning` to `exec`/`test` (the warning is still logged). Do NOT pass this flag to silently bypass a needed deploy — only when the user has chosen to test the deployed version.
> 5. If exec/test returns `function is not deployed`, a 404, or `undeployed local changes detected`, surface the message and ask whether to deploy — do not deploy unprompted.
> 6. If the user explicitly asked to "deploy and test" or "deploy then run" in their request, that IS the confirmation — deploy, then run without re-asking.
>
> When in doubt, ask the user whether to deploy first or run against the currently-deployed version. Let the user decide whether a redeploy is warranted.

After deploying a function, use these commands to execute, inspect results, and retrieve logs:

### Execute a Function

> **Resolve WHICH function and WHICH handler before running.** An app can have multiple function artifacts, and each artifact can expose multiple handlers — so `exec` needs both a function (`--function`, omittable only when the app has exactly one) and a `--handler`. Read `manifest.yml` (the `functions:` list; each entry has a `id`, `name`, and a `handlers:` list) to see what's available, then close the gap between what you already know and what's still ambiguous:
> - **Function already known** (e.g. the user has a file under `functions/<name>/` open, named it in the prompt, or the app has only one) → don't re-ask it. Only resolve the handler.
> - **Handler ambiguous** → if that function exposes exactly one handler in the manifest, use it. If it exposes several, list them and ask which one (don't guess).
> - **Function ambiguous** (multi-function app, no context) → list the functions from the manifest and ask which one, then resolve its handler the same way.
> - Never invent a function or handler name — every value must come from `manifest.yml`. If the manifest and an open file disagree, trust the manifest and mention the discrepancy.

> **Resolve WHAT request data to send — only after the function and handler are settled (above).** A handler can read a body, headers, query parameters, and a context object (see [Supplying request values beyond the body](#supplying-request-values-beyond-the-body)).
>
> **⚠️ For `exec`, you MUST confirm the request data with the user before executing, unless they already gave it in their prompt.** A bare request like "execute my function" / "run my handler" carries NO request data — you must ask what to send. **Finding a `sample_payload.json` (or borrowing a `tests.yml` case as a sample) is NOT permission to `exec` with it** — for `exec`, a discovered sample is only a suggestion to show the user, never the payload to auto-run. Do not `exec` with an empty, guessed, or auto-discovered payload. *(This confirm-first rule is specific to `exec`. It does NOT apply to `foundry functions test`, which is meant to run a function's `tests.yml` directly — see [Run Function Test Cases](#run-function-test-cases-integration-tests).)*
> 1. **Gather candidate request data (to propose, not to send).** Search the app for a sample: a `--request-file`-style JSON (top-level `body`/`header`/`query`/`context`) or a plain body sample — check `functions/<name>/` first (`payload.json`, `sample*.json`, `*request*.json`, `test*.json`, `examples/`), then the app root. A handler's `tests.yml` case can also be borrowed as a sample body here (this is just mining it for example values — it's unrelated to running `foundry functions test`).
> 2. **Read the handler source** (at the function's `path`) to see which components it reads (body, headers, query, context) and which fields are required. This inventory drives what you ask about in step 3 — don't assume it's body-only without checking.
> 3. **Decide whether to ask:**
>    - **User already gave the request data in their prompt** (inline values, or a pointer to a specific file) → that's the confirmation; don't re-ask. But if the handler reads a component they omitted (e.g. a required body or query/header param), clarify *that gap* — don't nag about components the handler ignores.
>    - **Otherwise (including a bare "execute my function") → ASK before executing.** Your question MUST cover **every** request component the handler reads (per step 2), not just the body — if it reads a header, query param, or context field, ask for those too. Walk through each applicable type in turn — **body**, **headers**, **query**, **context** — skipping only the types the handler doesn't read, and let the user decline any. (If the handler genuinely reads only the body, asking just about the body is correct.) Show any sample you found as a proposed default, and only run `exec` once the user has confirmed the values.
> 4. **Map to inputs:** body → positional arg (or `@file`), headers → `--header`, query → `--query`, context → `--context`; or bundle everything into one `--request-file`. Method and path are never asked — they come from the manifest.

```bash
# Execute with inline JSON payload (positional arg = request body)
foundry functions exec --handler my_handler '{"key": "value"}' --no-prompt

# Execute AND poll for logs in one step — only when the user explicitly asks for logs
# (e.g. "run my function and show me the logs"). Do NOT add --logs by default.
foundry functions exec --handler my_handler --logs '{"key": "value"}' --no-prompt

# Execute a specific function in a multi-function app
foundry functions exec --function my-fn --handler my_handler '{"key": "value"}' --no-prompt

# Execute with a request body file
foundry functions exec --handler my_handler @payload.json --no-prompt

# Execute with headers, query parameters, and/or a request context object
foundry functions exec --handler my_handler \
  --header 'X-Api-Key: abc123' --query 'limit=10' --context '{"user_id": "42"}' \
  '{"key": "value"}' --no-prompt

# Execute with body + headers + query + context bundled in one JSON file
foundry functions exec --handler my_handler --request-file request.json --no-prompt

# Execute against the currently-deployed version despite undeployed local edits
# (warning is still logged; only use when the user chose to run the deployed version)
foundry functions exec --handler my_handler --ignore-deploy-warning '{"key": "value"}' --no-prompt
```

The response shows: status code, exec ID, artifact info, and the function's response body. For async functions (202), the CLI automatically polls until the function completes and shows the actual result.

#### Supplying request values beyond the body

The positional argument (inline JSON, a file path, `@filename`, or stdin) is the request **body**. A handler can also read headers, query parameters, and a request context object — supply those with flags or a bundled file. **The HTTP method and path always come from the handler's manifest definition — they are NOT set here.** The platform passes these values to the handler without filtering (header names are canonicalized; query and context values are delivered verbatim), so shape them exactly as the handler code reads them.

| Flag | Repeatable | Format | Maps to |
|------|-----------|--------|---------|
| `--header` | yes | `"Name: value"` | request headers |
| `--query` | yes | `"name=value"` | query parameters |
| `--context` | no | inline JSON or `@filename` | request context object |
| `--request-file` | no | path to a JSON file (see below) | body + headers + query + context together |

- **Repeatable flags accumulate** — pass `--header` / `--query` more than once for multiple values (a name may repeat). Values are taken literally and are NOT comma-split, so `--header 'Accept: text/html,application/json'` sends one value containing a comma.
- **`--request-file`** points at a JSON file bundling everything in one place. All keys are optional; `header`/`query` values are arrays of strings. It is **mutually exclusive** with a positional body, `--header`, `--query`, and `--context` (combining them errors). `method`/`path` are not valid keys — they come from the manifest.

  ```json
  {
    "body":    { "hostname": "example.com" },
    "header":  { "X-Api-Key": ["abc123"] },
    "query":   { "limit": ["10"] },
    "context": { "user_id": "42" }
  }
  ```

  When the user asks for the exact file format, point them at `foundry functions exec --help` — it documents these keys inline.

- **Interactively** (no body and no request flags given), `exec` asks a single yes/no: whether to provide a bundled request file, then prompts for its path. It does not prompt for headers/query/context individually — use the flags or `--request-file` for those.

> **Execute ≠ fetch logs. When asked to run a handler, execute it and return the response body — then stop.** Do NOT automatically fetch logs (no `--logs`, no follow-up `foundry functions logs`) unless the user explicitly asked for them (e.g. "run it and show me the logs"). Logs arrive via Firehose ~5 minutes later, so auto-fetching adds a long, usually unwanted delay.
>
> **If the handler returns an error** (non-2xx status, error in the response body, or a stack trace): report the response to the user first, then *offer* to investigate — e.g. "The handler returned a 500. Would you like me to fetch the logs to see what went wrong?" Only run `foundry functions logs <exec_id>` after the user says yes. The exception is when the user's original request already asked you to debug or "figure out why it fails" — that is standing consent to pull logs without re-asking.

### Check Execution Status

> `exec status`, `exec list`, and `logs` act on an existing exec ID (or list past runs). They never inspect local files, so run them directly regardless of undeployed local changes — no deploy prompt, no `--ignore-deploy-warning`.

```bash
# Poll until an async execution completes
foundry functions exec status <exec_id>

# Single check without polling
foundry functions exec status <exec_id> --no-poll
```

### List Recent Executions

```bash
# List recent executions (interactive function selection)
foundry functions exec list

# List for a specific function
foundry functions exec list --function my-fn --no-prompt
```

### Retrieve Execution Logs

```bash
# Retrieve logs for a specific execution
foundry functions logs <exec_id>

# Resume polling a previous log query job
foundry functions logs <exec_id> --job-id <job_id>

# Force a fresh log query (if logs are still arriving)
foundry functions logs <exec_id> --refresh
```

Logs are delivered via the Firehose pipeline and typically arrive ~5 minutes after execution. The CLI shows a spinner during the query and a countdown between poll attempts.

### Debugging Workflow (AI-Assisted)

When a function execution fails or returns unexpected results, use this workflow:

1. **Execute and observe**: `foundry functions exec --handler <handler> --logs '<payload>'`
2. **Review logs**: If logs show the failure, correlate timestamps against the function source code
3. **Read source**: The function source is at the path specified in `manifest.yml` → `functions[].path`
4. **Identify root cause**: Compare log error messages, status codes, and stack traces against the handler logic
5. **Fix and re-deploy**: Apply the fix, `foundry apps deploy`, then re-execute to verify

When using Claude Code, ask "debug my last function execution" or "why did this function fail?" — the skill will automatically:
- Retrieve execution logs via `foundry functions logs`
- Read the function handler source from the manifest path
- Correlate log entries against the code to identify the failure point
- Suggest a concrete fix with specific code changes

### Run Function Test Cases (Integration Tests)

> **Not to be confused with unit tests.** Unit tests (`pytest`, Go `httptest`) run locally against mocked dependencies — see [testing-patterns.md](testing-patterns.md). Function test cases are **integration tests** that execute against the real deployed Lambda with real API calls, real collections, and real credentials.

Define test cases in a `tests.yml` file inside each function's directory and run them against the deployed function:

**File location:** `<app-root>/functions/<function-name>/tests.yml`

**Test cases are grouped by handler.** The top-level `tests:` key is a list of handler groups; each group names one handler (from the function's `manifest.yml`) and holds that handler's `cases:`. One `tests.yml` covers all of a function's handlers, and per-handler coverage is visible at a glance.

```yaml
# functions/my-function/tests.yml
tests:
  - handler: process          # a handler name this function exposes in manifest.yml
    cases:
      - name: valid_input
        input:
          body:
            hostname: "example.com"
        expect:
          status: 200
          body:
            result: "ok"        # subset match — actual body may contain more fields

      - name: missing_hostname
        input:
          body: {}
        expect:
          status: 400
          errors:
            - "hostname is required"

  - handler: healthcheck       # a second handler group in the same file
    cases:
      - name: health_ok
        input: {}
        expect:
          status: 200
```

**Schema (grouped by handler):**

- `tests:` — a list of **handler groups**, run and reported in file order.
- Each group has:
  - `handler:` (**required**) — the handler name, matching an entry in the function's `handlers:` list in `manifest.yml`. A group naming a handler that doesn't exist fails loudly (the CLI lists the available handlers).
  - `cases:` — the test cases for that handler.
- Each case has:
  - `name:` (**required**) — a unique, descriptive snake_case name. Shown in output as `handler/name`.
  - `input:` — the request payload/params (see below). The HTTP **method and path are NOT specified here** — they are taken from the handler's manifest definition, so a test always exercises the handler's real route.
  - `expect:` — the assertions (see below). **At least one of `status`/`body`/`errors` is required** — a case that asserts nothing is rejected at load time.

**`input` fields (all optional):**

| Field | Type | Notes |
|-------|------|-------|
| `body` | any JSON | Request body payload |
| `query` | map of string → list of strings | Query parameters, e.g. `limit: ["10"]` |
| `header` | map of string → list of strings | Request headers, e.g. `X-Custom: ["v"]` |
| `context` | any JSON | Request context object injected into the handler |

**`expect` fields (assert at least one):**

| Field | Type | Matching behavior |
|-------|------|-------------------|
| `status` | int | Exact match on the handler's response status code. Omit (or `0`) to skip the status check. |
| `body` | any JSON | **Object → subset match:** each field you list must be present in the response with an equal value; the actual body may contain additional fields. **Scalar/array → exact match.** |
| `errors` | list of strings | Set comparison against the handler's returned error messages. A mismatch reports both missing-expected and unexpected errors (order-independent). |

> **`method` no longer exists in `input`.** Earlier the schema was a flat `tests:` list where each case carried its own `handler:` and an `input.method:`. Now the handler comes from the enclosing group and the method/path come from the manifest — do NOT add a `method:` field, it is silently ignored.

```bash
# Run all test cases for all functions
foundry functions test --no-prompt

# Run a specific test case by name
foundry functions test --case valid_input --no-prompt

# Run tests for a specific function
foundry functions test --function my-function --no-prompt

# Run tests only for one handler group within a function
foundry functions test --function my-function --handler process --no-prompt

# Run tests one at a time (execute then validate each before the next)
foundry functions test --mode sync --no-prompt

# Run against the currently-deployed version despite undeployed local edits
# (warning is still logged; only use when the user chose to test the deployed version)
foundry functions test --ignore-deploy-warning --no-prompt
```

**Execution mode (`--mode`, default `async`):**

- **`async`** (default) — dispatches every test's execution up front, then validates each result. Slow or asynchronous (202) handlers run concurrently server-side rather than blocking the next test. Output order stays deterministic (file order), regardless of which executions finished first.
- **`sync`** — runs each test to full completion (execute → validate) before starting the next. Use when tests must not run concurrently — e.g. cases that share/mutate collection state or depend on ordering.

For async (202) handlers, the test command automatically polls for the actual result before asserting — in both modes.

> **Resolve WHICH function to test the same way as `exec`** (see [Execute a Function](#execute-a-function)). `test` runs the `tests.yml` in a function's directory, so it needs to know which function artifact you mean: pass `--function <name>` unless the app has exactly one, or the function is already known from an open file / the prompt. Consult `manifest.yml` for the available functions. Handlers are selected by the `handler:` field on each **group** in `tests.yml` (each group's handler must exist on the target function in the manifest); narrow a run to a single handler group with `--handler <name>`.

### Writing Integration Test Cases

When a user asks to "write tests for my function" or "add test cases", **first clarify which type of test they want:**

- **Unit tests** — run locally with mocked dependencies (`pytest`/`httptest`). Fast, no deployment needed. See [testing-patterns.md](testing-patterns.md).
- **Integration tests** — run against the real deployed Lambda via `foundry functions test`. Tests the full execution path including real API calls, collections, and credentials.

Ask: "Would you like unit tests (local, with mocks) or integration tests (against the deployed function)?"

If the answer is integration tests, generate **function integration test cases** as described below. If unit tests, follow the patterns in [testing-patterns.md](testing-patterns.md).

Generate integration test cases by:

1. **Read the function handlers** from `manifest.yml` — note the handler name, method, and api_path
2. **Read the handler source** to understand what inputs it expects and what validation it performs
3. **Group cases by handler** in `tests.yml` (one group per handler), then within each group generate cases covering:

| Category | What to test | Expected outcome |
|----------|-------------|-----------------|
| Happy path | Valid input with all required fields | `status: 200` (optionally assert `body`) |
| Missing required field | Omit each required field one at a time | `status: 400` (optionally `errors`) |
| Invalid field type | Wrong type for a field (string where int expected) | `status: 400` |
| Empty body | `{}` or no body | `status: 400` (if body required) |
| Edge cases | Boundary values, empty strings, nulls | Varies |
| Auth/permission failure | Input that triggers a downstream 401/403 | `status: 403` or `500` |

> **Prefer asserting more than just `status` where it's cheap.** `expect.body` (subset match) confirms the handler returned the right shape, and `expect.errors` confirms a rejection failed for the *expected* reason rather than incidentally. Each case must assert at least one of `status`/`body`/`errors`, or it is rejected at load time.

**Test case naming convention:** Use descriptive snake_case names that indicate what's being tested:
- `valid_hostname_lookup` — happy path
- `missing_hostname_field` — required field missing
- `invalid_hostname_format` — validation failure
- `empty_body` — no input provided

**Example — generating tests from handler source:**

Given this handler (from `manifest.yml`: handler `on_post`, method `POST`, path `/api/lookup`):
```python
@func.handler(method='POST', path='/api/lookup')
def on_post(request: Request, config, logger: Logger) -> Response:
    hostname = request.body.get("hostname")
    if not hostname:
        return Response(body={"error": "hostname is required"}, code=400)
    if not isinstance(hostname, str) or len(hostname) > 253:
        return Response(body={"error": "invalid hostname"}, code=400)
    # ... lookup logic
    return Response(body={"result": data}, code=200)
```

Generate this `functions/my-function/tests.yml` (cases grouped under the `on_post` handler; no `method:` field — it comes from the manifest):
```yaml
tests:
  - handler: on_post
    cases:
      - name: valid_hostname
        input:
          body:
            hostname: "example.com"
        expect:
          status: 200

      - name: missing_hostname
        input:
          body: {}
        expect:
          status: 400

      - name: hostname_too_long
        input:
          body:
            hostname: "a.b.c.d.e.f.g.h.i.j.k.l.m.n.o.p.q.r.s.t.u.v.w.x.y.z.a.b.c.d.e.f.g.h.i.j.k.l.m.n.o.p.q.r.s.t.u.v.w.x.y.z.a.b.c.d.e.f.g.h.i.j.k.l.m.n.o.p.q.r.s.t.u.v.w.x.y.z.a.b.c.d.e.f.g.h.i.j.k.l.m.n.o.p.q.r.s.t.u"
        expect:
          status: 400

      - name: hostname_wrong_type
        input:
          body:
            hostname: 12345
        expect:
          status: 400

      - name: empty_body
        input:
          body: {}
        expect:
          status: 400
```

**Workflow when user asks "write tests for my function":**
1. Read `manifest.yml` to find the function and its handlers (name, method, api_path)
2. Read the handler source code at the function's `path`
3. Identify input validation, required fields, and error paths
4. Generate `tests.yml` with one `handler:` group per handler, each holding its `cases:` — cover happy path + each validation branch, asserting at least one of `status`/`body`/`errors` per case
5. Write the `tests.yml` file to `<function-path>/tests.yml`
6. Run `foundry functions test --no-prompt` to verify they pass/fail as expected

