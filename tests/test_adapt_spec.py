"""Tests for scripts/adapt_spec_for_foundry.py.

Ported from the standalone scripts/test-adapt-spec.py assertion script to
pytest so it runs under the same coverage-gated CI job as the other script
tests. No network or credentials are needed — every case operates on in-memory
OpenAPI spec dicts.

Note: this imports the module by its snake_case name (adapt_spec_for_foundry),
which the script rename introduces. conftest.py puts scripts/ on sys.path.
"""

import json
import os
import tempfile

import adapt_spec_for_foundry as spec


def make_spec(**overrides):
    """Build a minimal OpenAPI spec, applying top-level overrides."""
    base = {
        "openapi": "3.0.0",
        "info": {"title": "Test API", "version": "1.0.0"},
        "servers": [{"url": "https://api.example.com"}],
        "paths": {
            "/users": {
                "get": {
                    "operationId": "listUsers",
                    "summary": "List all users",
                    "responses": {"200": {"description": "OK"}},
                }
            }
        },
    }
    base.update(overrides)
    return base


# ── Server URL transformations ───────────────────────────────────────────────


def test_strips_https_from_variable_url():
    s = make_spec(
        servers=[
            {
                "url": "https://{yourDomain}/api/v1",
                "variables": {"yourDomain": {"description": "Your domain"}},
            }
        ]
    )
    changes = spec.fix_server_urls(s)
    assert s["servers"][0]["url"] == "{yourDomain}/api/v1"
    assert len(changes) > 0


def test_keeps_https_on_hardcoded_url():
    s = make_spec(servers=[{"url": "https://api.example.com"}])
    changes = spec.fix_server_urls(s)
    assert s["servers"][0]["url"] == "https://api.example.com"
    assert len(changes) == 0


def test_removes_default_from_variable_without_enum():
    s = make_spec(
        servers=[
            {
                "url": "{host}",
                "variables": {
                    "host": {"description": "Host", "default": "api.example.com"}
                },
            }
        ]
    )
    spec.fix_server_urls(s)
    assert "default" not in s["servers"][0]["variables"]["host"]


def test_keeps_default_when_enum_exists():
    s = make_spec(
        servers=[
            {
                "url": "{region}.api.example.com",
                "variables": {"region": {"default": "us", "enum": ["us", "eu"]}},
            }
        ]
    )
    spec.fix_server_urls(s)
    assert s["servers"][0]["variables"]["region"]["default"] == "us"


def test_strips_http_from_variable_url():
    s = make_spec(
        servers=[{"url": "http://{host}", "variables": {"host": {"description": "Host"}}}]
    )
    spec.fix_server_urls(s)
    assert s["servers"][0]["url"] == "{host}"


def test_noop_when_url_already_clean():
    s = make_spec(
        servers=[
            {"url": "{host}/api/v1", "variables": {"host": {"description": "Host"}}}
        ]
    )
    changes = spec.fix_server_urls(s)
    assert s["servers"][0]["url"] == "{host}/api/v1"
    assert len(changes) == 0


# ── Auth fixes ────────────────────────────────────────────────────────────────


def test_no_changes_for_http_bearer_with_global_security():
    s = make_spec(
        components={
            "securitySchemes": {
                "bearerAuth": {
                    "type": "http",
                    "scheme": "bearer",
                    "bearerFormat": "apikey",
                }
            }
        },
        security=[{"bearerAuth": []}],
    )
    changes = spec.fix_auth(s)
    assert len(changes) == 0


def test_adds_global_security_for_http_bearer_when_missing():
    s = make_spec(
        components={
            "securitySchemes": {
                "bearerAuth": {
                    "type": "http",
                    "scheme": "bearer",
                    "bearerFormat": "apikey",
                }
            }
        }
    )
    spec.fix_auth(s)
    assert "security" in s
    assert s["security"] == [{"bearerAuth": []}]


def test_no_changes_for_apikey_custom_header_with_global_security():
    s = make_spec(
        components={
            "securitySchemes": {
                "apiKey": {"type": "apiKey", "name": "x-apikey", "in": "header"}
            }
        },
        security=[{"apiKey": []}],
    )
    changes = spec.fix_auth(s)
    assert len(changes) == 0


def test_adds_global_security_for_apikey_when_missing():
    s = make_spec(
        components={
            "securitySchemes": {
                "apiKey": {"type": "apiKey", "name": "x-apikey", "in": "header"}
            }
        }
    )
    spec.fix_auth(s)
    assert "security" in s


def test_apikey_in_authorization_header_kept_as_is():
    s = make_spec(
        components={
            "securitySchemes": {
                "apiKey": {"type": "apiKey", "name": "Authorization", "in": "header"}
            }
        }
    )
    changes = spec.fix_auth(s)
    assert len(changes) > 0
    # Foundry supports apiKey natively — the scheme is kept, not converted.
    assert "apiKey" in s["components"]["securitySchemes"]
    assert s["security"] == [{"apiKey": []}]


def test_warns_about_unsupported_auth_type():
    s = make_spec(
        components={
            "securitySchemes": {
                "custom": {"type": "openIdConnect", "openIdConnectUrl": "https://..."}
            }
        }
    )
    changes = spec.fix_auth(s)
    assert any("unsupported" in c.lower() or "WARNING" in c for c in changes)


def test_no_changes_when_no_security_schemes():
    s = make_spec()
    changes = spec.fix_auth(s)
    assert len(changes) == 0


def test_removes_oauth2_authorization_code_and_cleans_refs():
    s = make_spec(
        components={
            "securitySchemes": {
                "oauth2_auth": {
                    "type": "oauth2",
                    "flows": {
                        "authorizationCode": {
                            "authorizationUrl": "https://example.com/auth",
                            "tokenUrl": "https://example.com/token",
                            "scopes": {},
                        }
                    },
                }
            }
        },
        security=[{"oauth2_auth": []}],
    )
    spec.fix_auth(s)
    assert "oauth2_auth" not in s["components"]["securitySchemes"]
    assert all("oauth2_auth" not in req for req in s.get("security", []))


def test_adds_global_security_and_strips_empty_overrides():
    s = make_spec(
        components={
            "securitySchemes": {
                "apiToken": {
                    "type": "apiKey",
                    "name": "Authorization",
                    "in": "header",
                },
                "oauth2": {
                    "type": "oauth2",
                    "flows": {
                        "authorizationCode": {
                            "authorizationUrl": "https://example.com/auth",
                            "tokenUrl": "https://example.com/token",
                            "scopes": {},
                        }
                    },
                },
            }
        },
        paths={
            "/users": {
                "get": {
                    "operationId": "listUsers",
                    "security": [{"apiToken": []}, {"oauth2": []}],
                    "responses": {"200": {"description": "OK"}},
                }
            },
            "/public": {
                "get": {
                    "operationId": "publicEndpoint",
                    "security": [],
                    "responses": {"200": {"description": "OK"}},
                }
            },
        },
    )
    changes = spec.fix_auth(s)
    assert "security" in s
    assert s["security"] == [{"apiToken": []}]
    assert "security" not in s["paths"]["/public"]["get"]
    assert any("global security" in c.lower() for c in changes)
    assert any("empty" in c.lower() for c in changes)


def test_does_not_duplicate_existing_global_security():
    s = make_spec(
        components={
            "securitySchemes": {"bearerAuth": {"type": "http", "scheme": "bearer"}}
        },
        security=[{"bearerAuth": []}],
    )
    spec.fix_auth(s)
    assert s["security"] == [{"bearerAuth": []}]


# ── End-to-end JSON round-trip ────────────────────────────────────────────────


def test_end_to_end_round_trip():
    input_spec = {
        "openapi": "3.0.0",
        "info": {"title": "Vendor API", "version": "2.0"},
        "servers": [
            {
                "url": "https://{yourDomain}/api/v1",
                "variables": {
                    "yourDomain": {"description": "Your domain", "default": "example.com"}
                },
            }
        ],
        "components": {
            "securitySchemes": {"bearerAuth": {"type": "http", "scheme": "bearer"}}
        },
        "security": [{"bearerAuth": []}],
        "paths": {
            "/users": {
                "get": {
                    "operationId": "listUsers",
                    "summary": "List users",
                    "responses": {"200": {"description": "OK"}},
                }
            },
            "/users/{id}": {
                "get": {
                    "operationId": "getUser",
                    "summary": "Get user by ID",
                    "responses": {"200": {"description": "OK"}},
                }
            },
        },
    }

    with tempfile.NamedTemporaryFile(suffix=".json", mode="w", delete=False) as f:
        json.dump(input_spec, f, indent=2)
        tmp_input = f.name
    with tempfile.NamedTemporaryFile(suffix=".json", mode="w", delete=False) as f:
        tmp_output = f.name

    try:
        s, fmt = spec.load_spec(tmp_input)
        spec.fix_server_urls(s)
        spec.fix_auth(s)
        spec.save_spec(s, tmp_output, fmt)

        with open(tmp_output, encoding="utf-8") as fout:
            result = json.loads(fout.read())
        assert result["servers"][0]["url"] == "{yourDomain}/api/v1"
        assert "default" not in result["servers"][0]["variables"]["yourDomain"]
        # Operation config is the agent's responsibility, not the script's.
        assert "x-cs-operation-config" not in result["paths"]["/users"]["get"]
    finally:
        os.unlink(tmp_input)
        os.unlink(tmp_output)


# ── fix_auth: bearerFormat inference and securityDefinitions fallback ─────────


def test_infers_bearer_format_from_description():
    s = make_spec(
        components={
            "securitySchemes": {
                "apiToken": {
                    "type": "apiKey",
                    "name": "Authorization",
                    "in": "header",
                    "description": "Use SSWS {api_token} in the Authorization header",
                }
            }
        }
    )
    changes = spec.fix_auth(s)
    assert s["components"]["securitySchemes"]["apiToken"]["bearerFormat"] == "SSWS"
    assert any("bearerFormat" in c for c in changes)


def test_reads_swagger2_security_definitions():
    # Swagger 2.0 puts schemes under securityDefinitions, not components.
    s = make_spec(
        securityDefinitions={
            "apiKey": {"type": "apiKey", "name": "x-api-key", "in": "header"}
        }
    )
    spec.fix_auth(s)
    assert s["security"] == [{"apiKey": []}]


# ── load_spec / save_spec ────────────────────────────────────────────────────


def test_load_and_save_yaml_round_trip():
    doc = make_spec()
    with tempfile.NamedTemporaryFile(suffix=".yaml", mode="w", delete=False) as f:
        import yaml  # provided via requirements.txt

        yaml.safe_dump(doc, f)
        path = f.name
    try:
        loaded, fmt = spec.load_spec(path)
        assert fmt == "yaml"
        assert loaded["info"]["title"] == "Test API"
        spec.save_spec(loaded, path, "yaml")
        reloaded, _ = spec.load_spec(path)
        assert reloaded == loaded
    finally:
        os.unlink(path)


def test_load_spec_json():
    doc = make_spec()
    with tempfile.NamedTemporaryFile(suffix=".json", mode="w", delete=False) as f:
        json.dump(doc, f)
        path = f.name
    try:
        loaded, fmt = spec.load_spec(path)
        assert fmt == "json"
        assert loaded["openapi"] == "3.0.0"
    finally:
        os.unlink(path)


# ── dedup_parameters / _resolve_param_sig ────────────────────────────────────


def test_resolve_param_sig_inline_and_ref():
    components = {"parameters": {"Limit": {"name": "limit", "in": "query"}}}
    assert spec._resolve_param_sig({"name": "id", "in": "path"}, components) == (
        "id",
        "path",
    )
    assert spec._resolve_param_sig(
        {"$ref": "#/components/parameters/Limit"}, components
    ) == ("limit", "query")
    assert spec._resolve_param_sig({"no": "sig"}, components) is None
    assert spec._resolve_param_sig("not-a-dict", components) is None


def test_dedup_removes_operation_param_duplicating_path_param():
    s = make_spec(
        paths={
            "/users/{id}": {
                "parameters": [{"name": "id", "in": "path", "required": True}],
                "get": {
                    "operationId": "getUser",
                    "parameters": [
                        {"name": "id", "in": "path", "required": True},
                        {"name": "expand", "in": "query"},
                    ],
                    "responses": {"200": {"description": "OK"}},
                },
            }
        }
    )
    changes = spec.dedup_parameters(s)
    remaining = s["paths"]["/users/{id}"]["get"]["parameters"]
    assert remaining == [{"name": "expand", "in": "query"}]
    assert any("duplicate param" in c for c in changes)


def test_dedup_drops_parameters_key_when_all_removed():
    s = make_spec(
        paths={
            "/users/{id}": {
                "parameters": [{"name": "id", "in": "path"}],
                "get": {
                    "operationId": "getUser",
                    "parameters": [{"name": "id", "in": "path"}],
                    "responses": {"200": {"description": "OK"}},
                },
            }
        }
    )
    spec.dedup_parameters(s)
    assert "parameters" not in s["paths"]["/users/{id}"]["get"]


def test_dedup_noop_without_path_params():
    s = make_spec()  # no path-level parameters
    assert spec.dedup_parameters(s) == []


# ── validate_operation_config ────────────────────────────────────────────────


def test_validate_flags_misplaced_expose_to_workflow():
    s = make_spec(
        paths={
            "/users": {
                "get": {
                    "operationId": "listUsers",
                    "x-cs-operation-config": {"expose_to_workflow": True},
                    "responses": {"200": {"description": "OK"}},
                }
            }
        }
    )
    warnings = spec.validate_operation_config(s)
    assert len(warnings) == 1
    assert "expose_to_workflow" in warnings[0]


def test_validate_ok_when_nested_under_workflow():
    s = make_spec(
        paths={
            "/users": {
                "get": {
                    "operationId": "listUsers",
                    "x-cs-operation-config": {
                        "workflow": {"name": "listUsers", "expose_to_workflow": True}
                    },
                    "responses": {"200": {"description": "OK"}},
                }
            }
        }
    )
    assert spec.validate_operation_config(s) == []


# ── convert_swagger_to_openapi ───────────────────────────────────────────────


def test_convert_skips_non_swagger(tmp_path):
    p = tmp_path / "spec.json"
    p.write_text(json.dumps(make_spec()), encoding="utf-8")
    out, converted = spec.convert_swagger_to_openapi(str(p))
    assert out == str(p)
    assert converted is False


def test_convert_detects_swagger_but_handles_missing_npx(tmp_path, monkeypatch):
    p = tmp_path / "swagger.json"
    p.write_text(json.dumps({"swagger": "2.0", "paths": {}}), encoding="utf-8")

    def _raise(*_a, **_k):
        raise FileNotFoundError("npx")

    monkeypatch.setattr(spec.subprocess, "run", _raise)
    out, converted = spec.convert_swagger_to_openapi(str(p))
    assert out == str(p)
    assert converted is False


def test_convert_success(tmp_path, monkeypatch):
    p = tmp_path / "swagger.json"
    p.write_text(json.dumps({"swagger": "2.0", "paths": {}}), encoding="utf-8")
    out_expected = str(p).rsplit(".", 1)[0] + ".openapi3.json"

    def _fake_run(*_a, **_k):
        # Simulate swagger2openapi writing the converted file.
        with open(out_expected, "w", encoding="utf-8") as fh:
            json.dump({"openapi": "3.0.0", "paths": {}}, fh)

        class _R:
            returncode = 0
            stderr = ""

        return _R()

    monkeypatch.setattr(spec.subprocess, "run", _fake_run)
    out, converted = spec.convert_swagger_to_openapi(str(p))
    assert converted is True
    assert out == out_expected


def test_convert_nonzero_exit_falls_back(tmp_path, monkeypatch):
    p = tmp_path / "swagger.json"
    p.write_text(json.dumps({"swagger": "2.0", "paths": {}}), encoding="utf-8")

    class _R:
        returncode = 1
        stderr = "line1\nline2\nline3\nline4"

    monkeypatch.setattr(spec.subprocess, "run", lambda *_a, **_k: _R())
    out, converted = spec.convert_swagger_to_openapi(str(p))
    assert out == str(p)
    assert converted is False


def test_convert_timeout_falls_back(tmp_path, monkeypatch):
    p = tmp_path / "swagger.json"
    p.write_text(json.dumps({"swagger": "2.0", "paths": {}}), encoding="utf-8")

    def _timeout(*_a, **_k):
        raise spec.subprocess.TimeoutExpired(cmd="npx", timeout=120)

    monkeypatch.setattr(spec.subprocess, "run", _timeout)
    out, converted = spec.convert_swagger_to_openapi(str(p))
    assert out == str(p)
    assert converted is False


def test_convert_detects_yaml_swagger(tmp_path, monkeypatch):
    p = tmp_path / "swagger.yaml"
    p.write_text("swagger: '2.0'\npaths: {}\n", encoding="utf-8")
    out_expected = str(p).rsplit(".", 1)[0] + ".openapi3.yaml"

    def _fake_run(cmd, **_k):
        # The YAML branch passes --yaml and a .openapi3.yaml output path.
        assert "--yaml" in cmd
        with open(out_expected, "w", encoding="utf-8") as fh:
            fh.write("openapi: 3.0.0\npaths: {}\n")

        class _R:
            returncode = 0
            stderr = ""

        return _R()

    monkeypatch.setattr(spec.subprocess, "run", _fake_run)
    out, converted = spec.convert_swagger_to_openapi(str(p))
    assert converted is True
    assert out == out_expected


def test_load_spec_yaml_without_pyyaml_exits(tmp_path, monkeypatch):
    p = tmp_path / "spec.yaml"
    p.write_text("openapi: 3.0.0\n", encoding="utf-8")
    monkeypatch.setattr(spec, "HAS_YAML", False)
    with __import__("pytest").raises(SystemExit):
        spec.load_spec(str(p))


# ── main() ───────────────────────────────────────────────────────────────────


def test_main_prints_all_change_sections(tmp_path, monkeypatch, capsys):
    """A spec that triggers server, auth, param, and operation-config output
    exercises the print branches in main()."""
    doc = make_spec(
        servers=[
            {"url": "https://{host}/v1", "variables": {"host": {"description": "h"}}}
        ],
        components={
            "securitySchemes": {
                "bearerAuth": {"type": "http", "scheme": "bearer"}
            }
        },
        paths={
            "/users/{id}": {
                "parameters": [{"name": "id", "in": "path"}],
                "get": {
                    "operationId": "getUser",
                    "parameters": [{"name": "id", "in": "path"}],
                    "x-cs-operation-config": {"expose_to_workflow": True},
                    "responses": {"200": {"description": "OK"}},
                },
            }
        },
    )
    src = tmp_path / "in.yaml"
    import yaml

    src.write_text(yaml.safe_dump(doc), encoding="utf-8")
    monkeypatch.setattr(
        "sys.argv", ["adapt_spec_for_foundry.py", str(src), "--no-convert"]
    )
    spec.main()
    out = capsys.readouterr().out
    assert "Server URLs:" in out
    assert "Authentication:" in out
    assert "Parameters:" in out
    assert "Operation config warnings:" in out
    assert "Saved:" in out
    # Written back as YAML with the protocol stripped.
    result, _ = spec.load_spec(str(src))
    assert result["servers"][0]["url"] == "{host}/v1"


def test_main_dry_run_writes_nothing(tmp_path, monkeypatch, capsys):
    """--dry-run reports changes but leaves the input file untouched."""
    p = tmp_path / "spec.json"
    original = json.dumps(make_spec(), indent=2)
    p.write_text(original, encoding="utf-8")
    monkeypatch.setattr(
        "sys.argv", ["adapt_spec_for_foundry.py", str(p), "--dry-run", "--no-convert"]
    )
    spec.main()
    out = capsys.readouterr().out
    assert "dry run" in out.lower()
    assert p.read_text(encoding="utf-8") == original  # unchanged


def test_main_writes_output(tmp_path, monkeypatch):
    """-o writes the adapted spec to the output path with fixes applied."""
    src = tmp_path / "in.json"
    dst = tmp_path / "out.json"
    src.write_text(
        json.dumps(
            make_spec(
                servers=[
                    {
                        "url": "https://{host}/v1",
                        "variables": {"host": {"description": "h"}},
                    }
                ]
            )
        ),
        encoding="utf-8",
    )
    monkeypatch.setattr(
        "sys.argv",
        ["adapt_spec_for_foundry.py", str(src), "-o", str(dst), "--no-convert"],
    )
    spec.main()
    result = json.loads(dst.read_text(encoding="utf-8"))
    assert result["servers"][0]["url"] == "{host}/v1"  # protocol stripped

