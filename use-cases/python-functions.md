---
name: python-functions
description: Build Python serverless functions with FalconPy SDK, API integrations, and collection access
source: https://www.crowdstrike.com/tech-hub/ng-siem/dive-into-falcon-foundry-functions-with-python/
skills: [functions-development]
capabilities: [function]
---

## When to Use

User wants to create a Python function that processes data, calls Falcon APIs via FalconPy, invokes an API integration, or reads/writes collections. Also applies when adding handlers, shared utilities, logging, or unit tests to existing functions.

## Pattern

1. **Scaffold the function** with the Foundry CLI (always use `--no-prompt`):
   ```bash
   foundry functions create --name my-func --description "Does X" \
     --language python --handler-name my-handler --handler-path /my-path \
     --handler-method POST --wf-expose wf-app-only-action --no-prompt
   ```
2. **Add FalconPy** to `requirements.txt` (leave version unpinned):
   ```
   crowdstrike-falconpy
   ```
3. **Add auth scopes** for any Falcon APIs the function calls:
   ```bash
   foundry auth scopes add   # search for the scope you need
   ```
4. **Implement the handler** in `functions/<name>/main.py` following the FDK pattern.
5. **Test locally** before deploying:
   ```bash
   cd functions/<name>
   python -m venv .venv && source .venv/bin/activate
   pip install -r requirements.txt
   python main.py            # starts on port 8081
   # In another terminal:
   http POST :8081 "body[key]=value" method=POST url=/my-path
   ```
6. **Add request/response schemas** if exposing to workflows (root must be `object`).
7. **Write unit tests** using `unittest.mock` to patch FalconPy classes.

## Key Code

**Basic handler structure:**
```python
from crowdstrike.foundry.function import Function, Request, Response, APIError
func = Function.instance()

@func.handler(method='POST', path='/my-path')
def on_post(request: Request) -> Response:
    if 'required_field' not in request.body:
        return Response(code=400,
            errors=[APIError(code=400, message='missing required_field')])
    return Response(body={'result': 'ok'}, code=200)

if __name__ == '__main__':
    func.run()
```

**Calling Falcon APIs with FalconPy (context auth in cloud, env auth locally):**
```python
from falconpy import Hosts
falcon = Hosts()  # auto-authenticates in cloud
response = falcon.get_device_details(ids=host_id)
```

**Calling an API integration from a function:**
```python
from falconpy import APIIntegrations
api = APIIntegrations()
response = api.execute_command_proxy(
    definition_id="IntegrationName",  # use manifest ID when running locally
    operation_id="POST__api_now_table_tablename",
    params={"path": {"tableName": "incident"}},
    request={"json": payload, "headers": {"Accept": "application/json"}}
)
```

**Accessing collections from a function:**
```python
from falconpy import APIHarnessV2
api_client = APIHarnessV2()
# Write
api_client.command("PutObject", body=data,
    collection_name="my_collection", object_key=key)
# Read (returns bytes)
result = api_client.command("GetObject",
    collection_name="my_collection", object_key=key)
json_data = json.loads(result.decode("utf-8"))
```

**Handler with logging and config:**
```python
from logging import Logger
from typing import Dict, Optional

@func.handler(method="POST", path="/my-path")
def on_post(request: Request, _config: Optional[Dict[str, object]],
            logger: Logger) -> Response:
    logger.info(f"Processing request: {request.body}")
```

**Unit test pattern:**
```python
import importlib, unittest
from unittest.mock import patch, MagicMock

def mock_handler(*_args, **_kwargs):
    def identity(func): return func
    return identity

class FnTestCase(unittest.TestCase):
    def setUp(self):
        patcher = patch("crowdstrike.foundry.function.Function.handler",
                        new=mock_handler)
        self.addCleanup(patcher.stop)
        patcher.start()
        importlib.reload(main)

    @patch("main.Hosts")
    def test_success(self, mock_hosts_class):
        mock_instance = MagicMock()
        mock_hosts_class.return_value = mock_instance
        mock_instance.get_device_details.return_value = {
            "status_code": 200,
            "body": {"resources": [{"device_id": "abc"}]}
        }
        request = Request()
        request.body = {"host_id": "abc"}
        response = main.on_post(request)
        self.assertEqual(response.code, 200)
```

## Gotchas

- **API integration `definition_id`**: In the cloud, use the integration *name*. When running locally against a deployed app, use the manifest *ID* (hex string). Using the name locally returns a 404.
- **Collections need separate API credentials**: The Foundry CLI client ID/secret does not have Custom Storage scope. Create a new API client with Custom Storage read/write.
- **`X-CS-APP-ID` header**: Automatically set in cloud. For local testing, set `APP_ID` env var and add the header manually.
- **Shared utilities across functions**: `sys.path.append("../")` works with `python main.py` but NOT with `foundry functions run` (Docker) or in FaaS. Copy `utils.py` into each function directory before deploying.
- **Function limits**: 124 KB request, 120 KB response, 30s timeout (configurable to 900s), 256 MB RAM (configurable to 1 GB), 50 MB package size.
- **View function logs** in Next-Gen SIEM: `"#event_simpleName" = FunctionLogMessage | "fn_id" = {function ID}`
- **Invoke without HTTP server**: `python main.py --data ./test_payload.json`
