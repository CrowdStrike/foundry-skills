"""Tests for skills/app-audit/scripts/audit_app.py."""

import json
import os
import time

import yaml

from audit_app import FUNCTION_COUNT_WARN, PYCACHE_PATTERN, Audit, main


def write_app(root, manifest, files=None):
    """Write manifest.yml plus any extra files (str content, or dict/list as JSON)."""
    (root / "manifest.yml").write_text(yaml.safe_dump(manifest, sort_keys=False))
    for rel, content in (files or {}).items():
        path = root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content if isinstance(content, str) else json.dumps(content))
    return root


def function(name, handlers, language="python", path=None):
    return {"name": name, "language": language, "path": path or f"functions/{name}", "handlers": handlers}


def handler(name, request_schema=None, response_schema=None, workflow=True):
    return {
        "name": name, "method": "POST", "api_path": f"/{name.replace(' ', '-')}",
        "request_schema": request_schema, "response_schema": response_schema,
        "workflow_integration": {"id": "", "disruptive": False, "system_action": False} if workflow else None,
    }


def checks(app_dir):
    return [f.check for f in Audit(app_dir).run()]


def schema(*props):
    return {"type": "object", "properties": {p: {"type": "string"} for p in props}}


# ── functions ─────────────────────────────────────────────────


def test_clean_app_has_no_findings(tmp_path):
    write_app(tmp_path, {"name": "clean", "functions": [function("lookup", [handler("lookup_host")])]})
    assert checks(tmp_path) == []


def test_function_count_warns_above_threshold(tmp_path):
    funcs = [function(f"fn_{i:02d}", [handler("collect")]) for i in range(FUNCTION_COUNT_WARN + 1)]
    write_app(tmp_path, {"name": "big", "functions": funcs})
    assert "function-count" in checks(tmp_path)


def test_function_count_at_threshold_is_fine(tmp_path):
    funcs = [function(f"fn_{i:02d}", [handler("collect")]) for i in range(FUNCTION_COUNT_WARN)]
    write_app(tmp_path, {"name": "ok", "functions": funcs})
    assert "function-count" not in checks(tmp_path)


def test_handler_name_length_matches_cli_bounds(tmp_path):
    write_app(tmp_path, {"name": "names", "functions": [
        function("short", [handler("read")]),
        function("exact", [handler("merge")]),
        function("long", [handler("x" * 65)]),
    ]})
    found = [f for f in Audit(tmp_path).run() if f.check == "handler-name-length"]
    assert sorted(f.message.split("'")[3] for f in found) == ["read", "x" * 65]


def test_duplicate_handler_names_in_one_function(tmp_path):
    write_app(tmp_path, {"name": "dups", "functions": [function("grouped", [handler("collect"), handler("collect")])]})
    assert checks(tmp_path) == ["handler-name-duplicate"]


def test_same_handler_name_in_different_functions_is_fine(tmp_path):
    write_app(tmp_path, {"name": "ok", "functions": [function("a_func", [handler("collect")]),
                                                     function("b_func", [handler("collect")])]})
    assert checks(tmp_path) == []


def test_stray_pycache_is_reported_once(tmp_path):
    write_app(tmp_path, {"name": "cache", "functions": [function("one_fn", [handler("handle")]),
                                                        function("two_fn", [handler("handle")])]},
              {"functions/one_fn/__pycache__/main.cpython-314.pyc": "",
               "functions/two_fn/__pycache__/main.cpython-314.pyc": ""})
    found = [f for f in Audit(tmp_path).run() if f.check == "pycache-not-ignored"]
    assert len(found) == 1 and found[0].fixable and "2 __pycache__/ directories" in found[0].message


def test_pycache_covered_by_any_matching_pattern(tmp_path):
    # The CLI searches each pattern anywhere in the path, like the samples' ".+/__pycache__/.+".
    write_app(tmp_path, {"name": "cache", "ignored": [".+/__pycache__/.+"],
                         "functions": [function("one_fn", [handler("handle")])]},
              {"functions/one_fn/__pycache__/main.cpython-314.pyc": ""})
    assert checks(tmp_path) == []


def test_hidden_directories_are_never_deployed(tmp_path):
    write_app(tmp_path, {"name": "venv", "functions": [function("one_fn", [handler("handle")])]},
              {"functions/one_fn/.venv/lib/__pycache__/x.pyc": "",
               "functions/one_fn/.venv/lib/settings.py": "KEY = os.environ['API_KEY']\n"})
    assert checks(tmp_path) == []


def test_credential_from_environment(tmp_path):
    write_app(tmp_path, {"name": "env", "functions": [function("caller", [handler("call_api")])]},
              {"functions/caller/main.py": "import os\ntoken = os.environ.get('VENDOR_API_TOKEN')\n"
                                           "level = os.environ.get('LOG_LEVEL')\n"})
    found = [f for f in Audit(tmp_path).run() if f.check == "secret-in-env"]
    assert [f.file for f in found] == ["functions/caller/main.py:2"]


# ── workflows ─────────────────────────────────────────────────


def workflow_app(tmp_path, actions, wf_extra=None, handlers=None, files=None):
    doc = {"name": "wf", "provision_on_install": True, "trigger": {"name": "On demand", "type": "On demand"},
           "actions": actions, **(wf_extra or {})}
    all_files = {"workflows/wf.yml": yaml.safe_dump(doc, sort_keys=False), **(files or {})}
    return write_app(tmp_path, {
        "name": "wf-app",
        "functions": [function("collector", handlers or [handler("collect_data", "request_schema.json",
                                                                  "response_schema.json")])],
        "workflows": [{"name": "wf", "path": "workflows/wf.yml"}],
    }, all_files)


SCHEMAS = {"functions/collector/request_schema.json": schema("source"),
           "functions/collector/response_schema.json": schema("device_count")}


def test_undeclared_request_property(tmp_path):
    workflow_app(tmp_path, {"run": {"id": "functions.collector.collect_data",
                                    "properties": {"source": "devices", "client_id": "x"}}}, files=SCHEMAS)
    found = [f for f in Audit(tmp_path).run() if f.check == "request-property-undeclared"]
    assert len(found) == 1 and "client_id" in found[0].message and "source" not in found[0].message


def test_handler_without_request_schema_drops_every_property(tmp_path):
    workflow_app(tmp_path, {"run": {"id": "functions.collector.collect_data", "properties": {"source": "x"}}},
                 handlers=[handler("collect_data")])
    assert checks(tmp_path) == ["request-property-undeclared"]


def test_handler_name_with_spaces_in_action_id(tmp_path):
    workflow_app(tmp_path, {"run": {"id": "functions.collector.Collect all data", "properties": {"source": "x"}}},
                 handlers=[handler("Collect all data", "request_schema.json")], files=SCHEMAS)
    assert checks(tmp_path) == []


def test_unknown_function_action(tmp_path):
    workflow_app(tmp_path, {"run": {"id": "functions.collector.nope_handler", "properties": {}}}, files=SCHEMAS)
    assert checks(tmp_path) == ["unknown-function-action"]


def test_function_without_workflow_integration(tmp_path):
    workflow_app(tmp_path, {"run": {"id": "functions.collector.collect_data", "properties": {}}},
                 handlers=[handler("collect_data", workflow=False)])
    assert checks(tmp_path) == ["missing-workflow-integration"]


def test_output_key_missing_from_response_schema(tmp_path):
    actions = {"run": {"id": "functions.collector.collect_data", "properties": {"source": "x"}, "next": ["out"]},
               "out": {"id": "aadbf530e35fc452a032f5f8acaaac2a",
                       "properties": {"text_data": "${data['run.FaaS.collector.collect_data.host_count']}"}}}
    workflow_app(tmp_path, actions, files=SCHEMAS)
    found = [f for f in Audit(tmp_path).run() if f.check == "response-key-missing"]
    assert len(found) == 1 and "host_count" in found[0].message


def test_output_path_matches_handler_with_spaces_removed(tmp_path):
    actions = {"run": {"id": "functions.collector.Collect data", "properties": {"source": "x"}},
               "out": {"id": "aadbf530e35fc452a032f5f8acaaac2a",
                       "properties": {"text_data": "${data['run.FaaS.collector.Collectdata.device_count']}"}}}
    workflow_app(tmp_path, actions, handlers=[handler("Collect data", "request_schema.json", "response_schema.json")],
                 files=SCHEMAS)
    assert checks(tmp_path) == []


def test_missing_provision_on_install(tmp_path):
    workflow_app(tmp_path, {}, files=SCHEMAS)
    path = tmp_path / "workflows/wf.yml"
    doc = yaml.safe_load(path.read_text())
    del doc["provision_on_install"]
    path.write_text(yaml.safe_dump(doc, sort_keys=False))
    assert checks(tmp_path) == ["provision-on-install-missing"]


def test_multi_instance_does_not_exempt_provision_on_install(tmp_path):
    # multi_instance lets the same workflow name exist more than once in a CID; it says
    # nothing about whether installing creates the workflow.
    workflow_app(tmp_path, {}, files=SCHEMAS)
    path = tmp_path / "workflows/wf.yml"
    doc = yaml.safe_load(path.read_text())
    del doc["provision_on_install"]
    doc["multi_instance"] = True
    path.write_text(yaml.safe_dump(doc, sort_keys=False))
    assert checks(tmp_path) == ["provision-on-install-missing"]


def test_provision_on_install_false_is_info(tmp_path):
    workflow_app(tmp_path, {}, wf_extra={"provision_on_install": False}, files=SCHEMAS)
    assert [(f.check, f.severity) for f in Audit(tmp_path).run()] == [("provision-on-install-false", "info")]


# ── API integrations ─────────────────────────────────────────


def spec_app(tmp_path, servers):
    return write_app(tmp_path, {"name": "api", "api_integrations": [{"name": "Vendor", "path": "api-integrations/v.json"}]},
                     {"api-integrations/v.json": {"openapi": "3.0.0", "servers": servers, "paths": {}}})


def test_server_url_with_protocol_and_variables(tmp_path):
    spec_app(tmp_path, [{"url": "https://{domain}", "variables": {"domain": {"description": "Your domain"}}}])
    assert checks(tmp_path) == ["server-url-protocol"]


def test_variable_default_without_enum(tmp_path):
    spec_app(tmp_path, [{"url": "{domain}", "variables": {"domain": {"default": "acme.okta.com"}}}])
    assert checks(tmp_path) == ["server-variable-default"]


def test_variable_default_with_enum_is_fine(tmp_path):
    spec_app(tmp_path, [{"url": "{host}", "variables": {"host": {"default": "api.crowdstrike.com",
                                                                 "enum": ["api.crowdstrike.com"]}}}])
    assert checks(tmp_path) == []


def test_fixed_https_url_is_fine(tmp_path):
    spec_app(tmp_path, [{"url": "https://api.vendor.com"}])
    assert checks(tmp_path) == []


# ── UI ───────────────────────────────────────────────────────


def ui_app(tmp_path, built, src_newer=False):
    files = {"ui/pages/home/src/App.js": "export default 1\n"}
    if built:
        files["ui/pages/home/dist/index.html"] = "<html></html>"
    write_app(tmp_path, {"name": "ui", "ui": {"pages": {"home": {
        "name": "home", "path": "ui/pages/home/dist", "entrypoint": "ui/pages/home/dist/index.html"}}}}, files)
    if built:
        old, new = time.time() - 100, time.time()
        os.utime(tmp_path / "ui/pages/home/dist/index.html", (old, old) if src_newer else (new, new))
        os.utime(tmp_path / "ui/pages/home/src/App.js", (new, new) if src_newer else (old, old))
    return tmp_path


def test_ui_never_built(tmp_path):
    assert checks(ui_app(tmp_path, built=False)) == ["ui-not-built"]


def test_ui_built_before_last_source_change(tmp_path):
    assert checks(ui_app(tmp_path, built=True, src_newer=True)) == ["ui-stale-build"]


def test_ui_built_after_source_is_fine(tmp_path):
    assert checks(ui_app(tmp_path, built=True)) == []


def test_json_defined_extension_needs_no_build(tmp_path):
    write_app(tmp_path, {"name": "ui", "ui": {"extensions": [{"name": "TI", "path": "ui/extensions/ti/ti.json",
                                                              "entrypoint": "", "sockets": ["activity.detections.details"]}]}},
              {"ui/extensions/ti/ti.json": {}})
    assert checks(tmp_path) == []


# ── --fix and CLI ────────────────────────────────────────────


MANIFEST_WITH_COMMENT = """# keep this comment
name: fixme
ignored:
  - e2e
functions:
  - name: one_fn
    language: python
    path: functions/one_fn
    handlers:
      - name: handle
        method: POST
        api_path: /handle
workflows:
  - name: wf
    path: workflows/wf.yml
"""


def test_fix_edits_lines_and_keeps_formatting(tmp_path):
    (tmp_path / "manifest.yml").write_text(MANIFEST_WITH_COMMENT)
    (tmp_path / "functions/one_fn/__pycache__").mkdir(parents=True)
    (tmp_path / "functions/one_fn/__pycache__/main.pyc").write_text("")
    (tmp_path / "workflows").mkdir()
    (tmp_path / "workflows/wf.yml").write_text("name: wf\ntrigger:\n    type: On demand\nactions: {}\n")

    assert main([str(tmp_path), "--fix"]) == 0
    manifest = (tmp_path / "manifest.yml").read_text()
    assert manifest.startswith("# keep this comment\n")
    assert yaml.safe_load(manifest)["ignored"] == ["e2e", PYCACHE_PATTERN]
    workflow = (tmp_path / "workflows/wf.yml").read_text()
    assert workflow == "name: wf\nprovision_on_install: true\ntrigger:\n    type: On demand\nactions: {}\n"
    assert checks(tmp_path) == []


def test_fix_adds_ignored_when_absent(tmp_path):
    write_app(tmp_path, {"name": "fixme", "functions": [function("one_fn", [handler("handle")])]},
              {"functions/one_fn/__pycache__/main.pyc": ""})
    main([str(tmp_path), "--fix"])
    assert yaml.safe_load((tmp_path / "manifest.yml").read_text())["ignored"] == [PYCACHE_PATTERN]


def test_fix_leaves_judgment_calls_alone(tmp_path):
    workflow_app(tmp_path, {"run": {"id": "functions.collector.collect_data", "properties": {"client_id": "x"}}},
                 files=SCHEMAS)
    before = (tmp_path / "workflows/wf.yml").read_text()
    assert main([str(tmp_path), "--fix"]) == 1
    assert (tmp_path / "workflows/wf.yml").read_text() == before


def test_json_output_and_exit_codes(tmp_path, capsys):
    write_app(tmp_path, {"name": "names", "functions": [function("short", [handler("read")])]})
    assert main([str(tmp_path), "--json"]) == 1
    out = json.loads(capsys.readouterr().out)
    assert out[0]["check"] == "handler-name-length" and out[0]["skill"].startswith("functions-development")


def test_missing_manifest(tmp_path):
    assert checks(tmp_path) == ["no-manifest"]


def test_fix_appends_to_flow_style_ignored(tmp_path):
    (tmp_path / "manifest.yml").write_text(
        "name: fixme\nignored: [e2e]\nfunctions:\n  - name: one_fn\n    language: python\n"
        "    path: functions/one_fn\n    handlers:\n      - {name: handle, method: POST, api_path: /handle}\n")
    (tmp_path / "functions/one_fn/__pycache__").mkdir(parents=True)
    (tmp_path / "functions/one_fn/__pycache__/main.pyc").write_text("")
    main([str(tmp_path), "--fix"])
    assert yaml.safe_load((tmp_path / "manifest.yml").read_text())["ignored"] == ["e2e", PYCACHE_PATTERN]


def test_unparseable_manifest_is_an_error(tmp_path):
    (tmp_path / "manifest.yml").write_text("name: x\nfunctions:\n  - name: f\n   bad: [\n")
    assert checks(tmp_path) == ["invalid-file"]
    assert main([str(tmp_path)]) == 1


def test_unparseable_workflow_is_an_error(tmp_path):
    workflow_app(tmp_path, {}, files={**SCHEMAS, "workflows/wf.yml": "name: wf\n  bad: [\n"})
    assert checks(tmp_path) == ["invalid-file"]


def test_function_action_inside_loop_is_checked(tmp_path):
    workflow_app(tmp_path, {}, wf_extra={"loops": {"Loop": {"actions": {
        "run": {"id": "functions.collector.collect_data", "properties": {"client_id": "x"}}}}}}, files=SCHEMAS)
    assert checks(tmp_path) == ["request-property-undeclared"]


def test_go_credential_from_environment(tmp_path):
    write_app(tmp_path, {"name": "go", "functions": [function("caller", [handler("call_api")], language="go")]},
              {"functions/caller/main.go": 'package main\nvar k = os.Getenv("API_KEY")\n'})
    found = [f for f in Audit(tmp_path).run() if f.check == "secret-in-env"]
    assert [f.file for f in found] == ["functions/caller/main.go:2"]


def test_http_server_url_with_variables(tmp_path):
    spec_app(tmp_path, [{"url": "http://{domain}", "variables": {"domain": {"description": "Your domain"}}}])
    assert checks(tmp_path) == ["server-url-protocol"]


def test_ui_stale_build_with_dist_inside_src(tmp_path):
    files = {"ui/pages/home/src/App.js": "export default 1\n", "ui/pages/home/src/dist/index.html": "<html></html>"}
    write_app(tmp_path, {"name": "ui", "ui": {"pages": {"home": {
        "name": "home", "path": "ui/pages/home/src/dist", "entrypoint": "ui/pages/home/src/dist/index.html"}}}}, files)
    old, new = time.time() - 100, time.time()
    os.utime(tmp_path / "ui/pages/home/src/dist/index.html", (old, old))
    os.utime(tmp_path / "ui/pages/home/src/App.js", (new, new))
    assert checks(tmp_path) == ["ui-stale-build"]
    os.utime(tmp_path / "ui/pages/home/src/App.js", (old - 100, old - 100))
    assert checks(tmp_path) == []


def test_fix_provision_skips_past_block_scalar(tmp_path):
    workflow_app(tmp_path, {}, files={**SCHEMAS, "workflows/wf.yml":
                                      "description: |\n  two\n  lines\nname: wf\nactions: {}"})
    main([str(tmp_path), "--fix"])
    doc = yaml.safe_load((tmp_path / "workflows/wf.yml").read_text())
    assert doc["description"] == "two\nlines\n" and doc["provision_on_install"] is True


def _pycache_app(tmp_path, ignored_line):
    (tmp_path / "manifest.yml").write_text(
        f"name: fixme\n{ignored_line}\nfunctions:\n  - name: one_fn\n    language: python\n"
        "    path: functions/one_fn\n    handlers:\n      - {name: handle, method: POST, api_path: /handle}\n")
    (tmp_path / "functions/one_fn/__pycache__").mkdir(parents=True)
    (tmp_path / "functions/one_fn/__pycache__/main.pyc").write_text("")
    main([str(tmp_path), "--fix"])
    return (tmp_path / "manifest.yml").read_text()


def test_fix_ignored_with_comment_or_null_keeps_one_key(tmp_path):
    text = _pycache_app(tmp_path, "ignored: # patterns\n  - e2e")
    assert text.count("ignored:") == 1 and yaml.safe_load(text)["ignored"] == ["e2e", PYCACHE_PATTERN]


def test_fix_ignored_null(tmp_path):
    text = _pycache_app(tmp_path, "ignored: null")
    assert text.count("ignored:") == 1 and yaml.safe_load(text)["ignored"] == [PYCACHE_PATTERN]


def test_fix_leaves_multiline_flow_ignored_alone(tmp_path):
    text = _pycache_app(tmp_path, "ignored: [\n  e2e\n]")
    assert text.count("ignored:") == 1 and yaml.safe_load(text)["ignored"] == ["e2e"]


def test_falcon_client_fallback_is_not_a_secret_finding(tmp_path):
    write_app(tmp_path, {"name": "go", "functions": [function("caller", [handler("call_api")], language="go")]},
              {"functions/caller/main.go": 'package main\nvar s = os.Getenv("FALCON_CLIENT_SECRET")\n'})
    assert checks(tmp_path) == []
