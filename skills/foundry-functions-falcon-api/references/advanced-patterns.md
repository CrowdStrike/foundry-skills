# Advanced Falcon API Patterns Reference

> Parent skill: [foundry-functions-falcon-api](../SKILL.md)

## Retry with Exponential Backoff

Reusable retry decorator for Falcon API calls that handles transient failures:

```python
# functions/common/retry.py
import time
from functools import wraps
from typing import TypeVar, Callable

T = TypeVar('T')

def with_retry(
    max_retries: int = 3,
    backoff_factor: float = 1.0,
    retry_on_status: tuple = (429, 500, 502, 503, 504)
):
    """Decorator for API calls with exponential backoff retry."""
    def decorator(func: Callable[..., T]) -> Callable[..., T]:
        @wraps(func)
        def wrapper(*args, **kwargs) -> T:
            last_response = None

            for attempt in range(max_retries + 1):
                response = func(*args, **kwargs)
                status_code = response.get("status_code", 500)

                if status_code not in retry_on_status:
                    return response

                last_response = response

                if attempt < max_retries:
                    sleep_time = backoff_factor * (2 ** attempt)
                    time.sleep(sleep_time)

            return last_response

        return wrapper
    return decorator

# functions/detections/main.py
from crowdstrike.foundry.function import Function, Request, Response
from falconpy import Detects
from common.retry import with_retry

func = Function.instance()

@func.handler(method='GET', path='/api/detections')
def get_detections(request: Request, config, logger) -> Response:
    falcon = Detects()

    @with_retry(max_retries=3)
    def query_with_retry():
        return falcon.query_detects(limit=50)

    response = query_with_retry()

    if response["status_code"] != 200:
        return Response(body={"error": "Failed after retries"}, code=500)

    detection_ids = response.get("body", {}).get("resources", [])
    return Response(body={"detection_ids": detection_ids}, code=200)

if __name__ == '__main__':
    func.run()
```

## Counter-Rationalizations Table

| Your Excuse | Reality |
|-------------|---------|
| "I need to set up OAuth manually" | Auth is completely automatic inside FDK handlers |
| "I should write a credential wrapper" | Wrappers break context auth and add no value |
| "I can use requests directly" | SDKs handle auth, retries, pagination, and region discovery |
| "Region configuration is required" | SDKs auto-discover the correct region from platform context |
| "I'll handle errors generically" | Specific error handling enables proper user feedback |
| "Mocking is extra work" | Real API calls in tests are slow, flaky, and quota-consuming |
| "I can skip the FDK handler pattern" | Handler pattern is required for automatic auth injection |
