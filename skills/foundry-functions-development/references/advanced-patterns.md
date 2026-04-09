# Advanced Functions Patterns Reference

> Parent skill: [foundry-functions-development](../SKILL.md)

## Counter-Rationalizations Table

| Your Excuse | Reality |
|-------------|---------|
| "I can call APIs directly with HTTP" | SDKs handle auth, retries, regions, and error parsing |
| "Simple functions don't need structured responses" | Consistent response formats prevent UI parsing errors |
| "I'll add error handling later" | Unhandled errors leak sensitive stack traces |
| "Go is overkill for simple functions" | Go functions have faster cold starts and lower memory |
| "Python type hints are optional" | Type hints catch bugs early and improve maintainability |
| "Testing is overhead for small functions" | Small functions grow; tests prevent regression |

## Red Flags - STOP Immediately

If you catch yourself:
- Using `requests` library instead of CrowdStrike SDKs
- Returning raw strings instead of structured JSON
- Not validating input parameters
- Hardcoding API credentials in code
- Skipping tests for "simple" functions

**STOP. Follow the patterns above. No shortcuts.**
