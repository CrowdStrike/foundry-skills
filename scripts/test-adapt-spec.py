#!/usr/bin/env python3
"""Tests for adapt-spec-for-foundry.py"""
# pylint: disable=invalid-name,wrong-import-position,global-statement

import json
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(__file__))
from importlib import import_module

# Import the script as a module
spec = import_module('adapt-spec-for-foundry')

PASS = 0
FAIL = 0


def assert_eq(actual, expected, msg):
    """Assert actual equals expected."""
    global PASS, FAIL
    if actual == expected:
        PASS += 1
        print(f"  PASS: {msg}")
    else:
        FAIL += 1
        print(f"  FAIL: {msg}")
        print(f"    expected: {expected}")
        print(f"    actual:   {actual}")


def assert_in(needle, haystack, msg):
    """Assert needle is found in haystack."""
    global PASS, FAIL
    if needle in haystack:
        PASS += 1
        print(f"  PASS: {msg}")
    else:
        FAIL += 1
        print(f"  FAIL: {msg}")
        print(f"    '{needle}' not found in: {haystack}")


def assert_true(val, msg):
    """Assert val is truthy."""
    global PASS, FAIL
    if val:
        PASS += 1
        print(f"  PASS: {msg}")
    else:
        FAIL += 1
        print(f"  FAIL: {msg}")


def make_spec(**overrides):
    """Build a minimal OpenAPI spec with overrides."""
    base = {
        "openapi": "3.0.0",
        "info": {"title": "Test API", "version": "1.0.0"},
        "servers": [{"url": "https://api.example.com"}],
        "paths": {
            "/users": {
                "get": {
                    "operationId": "listUsers",
                    "summary": "List all users",
                    "responses": {"200": {"description": "OK"}}
                }
            }
        }
    }
    base.update(overrides)
    return base


# ── Server URL Tests ─────────────────────────────────────────

print("Server URL transformations:")

# Variable-based URL: strip https://
s = make_spec(servers=[{
    "url": "https://{yourDomain}/api/v1",
    "variables": {"yourDomain": {"description": "Your domain"}}
}])
changes = spec.fix_server_urls(s)
assert_eq(s["servers"][0]["url"], "{yourDomain}/api/v1", "strips https:// from variable URL")
assert_true(len(changes) > 0, "reports changes for variable URL")

# Hardcoded URL: keep https://
s = make_spec(servers=[{"url": "https://api.example.com"}])
changes = spec.fix_server_urls(s)
assert_eq(s["servers"][0]["url"], "https://api.example.com", "keeps https:// on hardcoded URL")
assert_true(len(changes) == 0, "no changes for hardcoded URL")

# Variable with default but no enum: remove default
s = make_spec(servers=[{
    "url": "{host}",
    "variables": {"host": {"description": "Host", "default": "api.example.com"}}
}])
spec.fix_server_urls(s)
assert_true("default" not in s["servers"][0]["variables"]["host"],
            "removes default from variable without enum")

# Variable with default AND enum: keep default
s = make_spec(servers=[{
    "url": "{region}.api.example.com",
    "variables": {"region": {"default": "us", "enum": ["us", "eu"]}}
}])
spec.fix_server_urls(s)
assert_eq(s["servers"][0]["variables"]["region"]["default"], "us",
          "keeps default when enum exists")

# http:// also stripped
s = make_spec(servers=[{
    "url": "http://{host}",
    "variables": {"host": {"description": "Host"}}
}])
spec.fix_server_urls(s)
assert_eq(s["servers"][0]["url"], "{host}", "strips http:// from variable URL")

# Already clean URL (no protocol, has variables)
s = make_spec(servers=[{
    "url": "{host}/api/v1",
    "variables": {"host": {"description": "Host"}}
}])
changes = spec.fix_server_urls(s)
assert_eq(s["servers"][0]["url"], "{host}/api/v1", "no-op when URL already clean")
assert_true(len(changes) == 0, "no changes when URL already clean")

print()

# ── Auth Fix Tests ───────────────────────────────────────────

print("Auth fix:")

# Valid http/bearer with global security: no changes
s = make_spec(
    components={"securitySchemes": {
        "bearerAuth": {"type": "http", "scheme": "bearer", "bearerFormat": "apikey"}
    }},
    security=[{"bearerAuth": []}]
)
changes = spec.fix_auth(s)
assert_true(len(changes) == 0, "no changes for http/bearer with global security")

# Valid http/bearer without global security: adds global security
s = make_spec(components={"securitySchemes": {
    "bearerAuth": {"type": "http", "scheme": "bearer", "bearerFormat": "apikey"}
}})
changes = spec.fix_auth(s)
assert_true("security" in s, "adds global security for http/bearer when missing")
assert_eq(s["security"], [{"bearerAuth": []}], "global security references bearerAuth")

# Valid apiKey in custom header with global security: no changes
s = make_spec(
    components={"securitySchemes": {
        "apiKey": {"type": "apiKey", "name": "x-apikey", "in": "header"}
    }},
    security=[{"apiKey": []}]
)
changes = spec.fix_auth(s)
assert_true(len(changes) == 0, "no changes for apiKey in custom header with global security")

# Valid apiKey in custom header without global security: adds global security
s = make_spec(components={"securitySchemes": {
    "apiKey": {"type": "apiKey", "name": "x-apikey", "in": "header"}
}})
changes = spec.fix_auth(s)
assert_true("security" in s, "adds global security for apiKey when missing")

# apiKey in Authorization header: kept as-is (Foundry supports apiKey natively)
s = make_spec(components={"securitySchemes": {
    "apiKey": {"type": "apiKey", "name": "Authorization", "in": "header"}
}})
changes = spec.fix_auth(s)
assert_true(len(changes) > 0, "adds global security for apiKey in Authorization header")
assert_true("apiKey" in s["components"]["securitySchemes"],
            "keeps apiKey scheme (no longer converts to http/bearer)")
assert_eq(s["security"], [{"apiKey": []}],
          "global security references apiKey scheme")

# Unsupported type: warns (also adds global security)
s = make_spec(components={"securitySchemes": {
    "custom": {"type": "openIdConnect", "openIdConnectUrl": "https://..."}
}})
changes = spec.fix_auth(s)
assert_true(any("unsupported" in c.lower() or "WARNING" in c for c in changes),
            "warns about unsupported auth type")

# No securitySchemes: no crash
s = make_spec()
changes = spec.fix_auth(s)
assert_true(len(changes) == 0, "no changes when no securitySchemes")

# oauth2 authorizationCode removed, security refs cleaned up
s = make_spec(
    components={"securitySchemes": {
        "oauth2_auth": {"type": "oauth2", "flows": {"authorizationCode": {
            "authorizationUrl": "https://example.com/auth",
            "tokenUrl": "https://example.com/token",
            "scopes": {}
        }}}
    }},
    security=[{"oauth2_auth": []}]
)
changes = spec.fix_auth(s)
assert_true("oauth2_auth" not in s["components"]["securitySchemes"],
            "removes oauth2 authorizationCode scheme")
assert_true(all("oauth2_auth" not in req for req in s.get("security", [])),
            "removes dangling oauth2 security references")

# Missing global security: adds one referencing the converted scheme
s = make_spec(
    components={"securitySchemes": {
        "apiToken": {"type": "apiKey", "name": "Authorization", "in": "header"},
        "oauth2": {"type": "oauth2", "flows": {"authorizationCode": {
            "authorizationUrl": "https://example.com/auth",
            "tokenUrl": "https://example.com/token",
            "scopes": {}
        }}}
    }},
    paths={
        "/users": {
            "get": {
                "operationId": "listUsers",
                "security": [{"apiToken": []}, {"oauth2": []}],
                "responses": {"200": {"description": "OK"}}
            }
        },
        "/public": {
            "get": {
                "operationId": "publicEndpoint",
                "security": [],
                "responses": {"200": {"description": "OK"}}
            }
        }
    }
)
changes = spec.fix_auth(s)
assert_true("security" in s, "adds global security when missing")
assert_eq(s["security"], [{"apiToken": []}],
          "global security references remaining apiKey scheme")
assert_true("security" not in s["paths"]["/public"]["get"],
            "removes empty security override from operations")
assert_true(any("global security" in c.lower() for c in changes),
            "reports adding global security in changes")
assert_true(any("empty" in c.lower() for c in changes),
            "reports removing empty security overrides in changes")

# Existing global security: does not duplicate it
s = make_spec(
    components={"securitySchemes": {
        "bearerAuth": {"type": "http", "scheme": "bearer"}
    }},
    security=[{"bearerAuth": []}]
)
changes = spec.fix_auth(s)
assert_eq(s["security"], [{"bearerAuth": []}],
          "does not duplicate existing global security")

print()

# ── End-to-end JSON round-trip ───────────────────────────────

print("End-to-end round-trip:")

input_spec = {
    "openapi": "3.0.0",
    "info": {"title": "Vendor API", "version": "2.0"},
    "servers": [{
        "url": "https://{yourDomain}/api/v1",
        "variables": {
            "yourDomain": {"description": "Your domain", "default": "example.com"}
        }
    }],
    "components": {
        "securitySchemes": {
            "bearerAuth": {"type": "http", "scheme": "bearer"}
        }
    },
    "security": [{"bearerAuth": []}],
    "paths": {
        "/users": {
            "get": {
                "operationId": "listUsers",
                "summary": "List users",
                "responses": {"200": {"description": "OK"}}
            }
        },
        "/users/{id}": {
            "get": {
                "operationId": "getUser",
                "summary": "Get user by ID",
                "responses": {"200": {"description": "OK"}}
            }
        }
    }
}

with tempfile.NamedTemporaryFile(suffix='.json', mode='w', delete=False) as f:
    json.dump(input_spec, f, indent=2)
    tmp_input = f.name

with tempfile.NamedTemporaryFile(suffix='.json', mode='w', delete=False) as f:
    tmp_output = f.name

try:
    s, fmt = spec.load_spec(tmp_input)
    spec.fix_server_urls(s)
    spec.fix_auth(s)
    spec.save_spec(s, tmp_output, fmt)

    with open(tmp_output, encoding='utf-8') as fout:
        result = json.loads(fout.read())
    assert_eq(result["servers"][0]["url"], "{yourDomain}/api/v1",
              "round-trip: URL stripped")
    assert_true("default" not in result["servers"][0]["variables"]["yourDomain"],
                "round-trip: default removed")
    assert_true("x-cs-operation-config" not in result["paths"]["/users"]["get"],
                "round-trip: no operation config added (agent's responsibility)")
finally:
    os.unlink(tmp_input)
    os.unlink(tmp_output)

print()

# ── Summary ──────────────────────────────────────────────────

total = PASS + FAIL
print(f"{'=' * 40}")
print(f"  {PASS}/{total} passed, {FAIL} failed")
print(f"{'=' * 40}")
sys.exit(1 if FAIL > 0 else 0)
