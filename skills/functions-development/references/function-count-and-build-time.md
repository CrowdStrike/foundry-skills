# Function Count and Build Time

Each function in `manifest.yml` is built as its own container when the app deploys. The number of functions, not their size or handler count, is what drives deploy time, and on a fresh install a large number of them can fail the build outright. Packages of 1–3 MB each are far from the 50 MB cap and don't matter here.

**Measured:** the same 43 Python handlers from a large production app, deployed fresh with no other artifacts:

| Shape | Result |
|-------|--------|
| 43 functions × 1 handler | Deployment **Failed** (twice: 15 and 23 minutes) |
| 11 functions × ~4 handlers | Deployment **Successful** in about 9 minutes |

The app's team saw the same in their full app (about 60 agents, 7 knowledge bases, 5 collections, 6 workflows): at 43 functions fresh installs failed with no CLI trace, and after consolidating to 11, fresh installs finish in under 15 minutes. Knowledge bases, agents, collections, workflows, and UI don't have this problem. The threshold is somewhere between 11 and 43, so don't treat 11 as a limit, just keep the count low.

## Plan Functions by Domain

- Before running `foundry functions create`, check whether an existing function in the same language covers the same domain, and add to it instead.
- Group logic that shares a language and dependencies. A Python function and a Go function can't merge.
- Twenty collectors that differ only by which API they call are one function, not twenty.

## Two Ways to Consolidate

**Mode-switched dispatcher (for workflow-called logic).** One function, one handler, with a dispatch table keyed by a mode field in the request body. Each workflow node calls the same action with a different mode value. Use this when the logic is called from workflows: the single handler is created with `foundry functions create … --wf-expose --input-schema --output-schema`, so its schemas are bound, while hand-added handlers get no bound I/O schemas.

```python
from crowdstrike.foundry.function import APIError, Function, Request, Response

from modes import devices, detections, incidents

func = Function.instance()
MODES = {"devices": devices.run, "detections": detections.run, "incidents": incidents.run}


@func.handler(method="POST", path="/collect-data")
def on_post(request: Request) -> Response:
    mode = request.body.get("source")
    if mode not in MODES:
        return Response(code=400, errors=[APIError(code=400, message=f"unknown source: {mode}")])
    run = MODES[mode]
    try:
        return Response(code=200, body=run(request.body))
    except Exception as e:  # one mode failing must not look like the whole function failing
        return Response(code=500, errors=[APIError(code=500, message=f"{mode} failed: {e}")])


if __name__ == "__main__":
    func.run()
```

Two rules that fail silently if missed:

1. **Declare the mode field and every per-mode input in `request_schema`.** A workflow action passes the handler only properties its `request_schema` declares, even with `additionalProperties: true`, so an undeclared mode field arrives empty and the function never learns which mode to run. See the `workflows-development` skill → Calling Functions from Workflows.
2. **Make `response_schema` the union of every mode's top-level output keys.** Downstream nodes read individual keys (`${data['collect_devices.FaaS.collector.collect_data.device_count']}`), and a key a mode returns but the schema omits can't be referenced from the workflow.

**Several handlers per function (for UI- or API-called logic).** Keep each old `main.py` as a module and import them all into one `main.py`. Every module registers its handler on the same `Function.instance()`, and the FDK routes by method and path.

```python
from crowdstrike.foundry.function import Function

import devices_collector  # noqa: F401
import detections_collector  # noqa: F401

func = Function.instance()

if __name__ == "__main__":
    func.run()
```

## Handler Rules

- Handler names must be **5 to 64 characters** (`read` fails, `merge` passes). `apps validate` reports a short name as `handler name must be greater than 5 characters`, but exactly 5 is accepted.
- Handler names must be **unique within a function**: `function handler name shows up in multiple handlers`. When merging functions whose handlers are all named `collect`, rename them in the manifest. The code doesn't change, because routing is by `api_path`.
- `api_path` must also be unique within a function.
- The 100-concurrent-executions limit now applies to the whole consolidated function, so check the widest fan-out a workflow runs at once.

## Checklist for Consolidating an Existing App

1. **Map every reference.** List each old `FaaS.<function>.<handler>.<key>` used in workflows and give it its new target. Every old reference needs one.
2. **Audit the wiring.** Each workflow node must pass the right mode value and that mode's inputs. Watch nodes that call the same action and differ only by one input.
3. **Check the contract.** Each consolidated function's `response_schema` covers every key its modes return.
4. **Diff the output.** Move logic byte for byte, run old and new with the same inputs, and compare. A difference then points to wiring, not logic.

Consolidate on a fresh install first. Redeploying a consolidated manifest onto an existing app that already has the old functions can fail on the update path even when a fresh install works.
