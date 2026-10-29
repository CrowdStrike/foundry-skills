---
name: app-audit
description: Audit an existing Falcon Foundry app for documented anti-patterns and fix the safe ones, like npm audit. TRIGGER when user asks to "audit my Foundry app", "check my app for problems", "review this Foundry app", "scan for anti-patterns", "why might this deploy fail", or runs `audit_app.py`. DO NOT TRIGGER for creating a new app (use development-workflow) or for debugging an error the user already has (use debugging-workflows).
version: 1.7.0
updated: 2026-10-29
tags: [foundry, audit, lint, best-practices]
author: CrowdStrike
license: MIT
compatibility: Claude Code >=1.0
metadata:
  category: quality
---

# Auditing a Foundry App

Run the bundled script against the app directory (the one with `manifest.yml`). It reads the manifest and the files it points to, calls no API, and needs only `pyyaml`:

```bash
python3 skills/app-audit/scripts/audit_app.py path/to/app          # report
python3 skills/app-audit/scripts/audit_app.py path/to/app --json   # machine-readable
python3 skills/app-audit/scripts/audit_app.py path/to/app --fix    # apply the safe fixes, then report
```

It exits `1` when an error-level finding remains. Each finding names the skill and section that explains it; read that section before changing anything.

## What It Checks

| Check | Severity | Why |
|-------|----------|-----|
| `function-count` | warn | More than 20 functions. Each is a separate container build, and a fresh install with 43 failed where the same handlers in 11 functions deployed. |
| `handler-name-length` | error | Handler names must be 5 to 64 characters (the CLI's own limits). |
| `handler-name-duplicate` | error | Handler names must be unique within a function. |
| `request-property-undeclared` | error | A workflow passes a property the function's `request_schema` doesn't declare, so it's silently dropped. |
| `response-key-missing` | warn | A workflow reads a `FaaS` output key the handler's `response_schema` doesn't declare. |
| `unknown-function-action` | error | A workflow calls `functions.<name>.<handler>` that isn't in the manifest. |
| `missing-workflow-integration` | error | A workflow calls a handler that has no `workflow_integration`, so deploy fails. |
| `provision-on-install-missing` | warn, fixable | Installing won't create the workflow. Leave it off only when the app provisions the workflow itself through the Workflows API, as rapid-response and scalable-rtr do. |
| `provision-on-install-false` | info | Fine when deliberate. |
| `pycache-not-ignored` | warn, fixable | A local `__pycache__/` would deploy. The CLI already skips hidden paths like `.venv/`. |
| `secret-in-env` | warn | A function reads a key, token, secret, or password from an environment variable, which is visible in app exports. |
| `server-url-protocol` | error | An OpenAPI server URL with variables starts with `https://` or `http://`, so the protocol doubles. |
| `server-variable-default` | warn | A server variable has a `default` but no `enum`, which renders as a one-value dropdown. |
| `ui-not-built` | error | A page or extension has no `dist/`; deploy never builds the UI. |
| `ui-stale-build` | warn | `src/` is newer than `dist/`, so deploy would ship the previous build. |
| `invalid-file` | error | `manifest.yml`, a workflow, or an API spec it points to doesn't parse, so the checks that read it were skipped. |

## Fixing Findings

`--fix` applies only the fixes marked fixable: it adds the `__pycache__` pattern to `ignored:` and `provision_on_install: true` to workflows that lack it. Both are single-line insertions that leave the rest of the file as written. Tell the user what `--fix` will change before running it, and show the diff afterward.

Everything else needs judgment, so handle it with the user:

- **Undeclared request properties:** add each property to the handler's `request_schema.json`, then redeploy. If the handler has no schema, the function needs one bound at create time (see the `functions-development` skill → Function I/O Schemas).
- **Missing response keys:** add the key to `response_schema.json`, or fix the workflow's data path if the key is misspelled.
- **Too many functions:** follow the `functions-development` skill's `references/function-count-and-build-time.md`; consolidating changes workflow wiring and needs its checklist.
- **Server URLs and defaults:** run the `api-integrations` skill's spec adapter on the spec rather than editing it by hand.
- **UI builds:** run `npm run build` in each page or extension directory, then return to the app root.

Run the audit again after fixing, and run `foundry apps validate --no-prompt` before deploying. The audit complements validation and doesn't replace it.

## Reading Results

The checks are static, so treat a finding as a strong lead, not proof. A warning can be deliberate (a large app may need many functions, and an app that provisions its own workflows skips `provision_on_install`). If a finding looks wrong for the app in front of you, say why instead of forcing a fix.
