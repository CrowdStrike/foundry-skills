#!/usr/bin/env python3
"""Audit a Falcon Foundry app for documented anti-patterns, without calling any API.

Usage:
    python3 skills/app-audit/scripts/audit_app.py [APP_DIR] [--json] [--fix]

APP_DIR is the directory that holds manifest.yml (default: the current directory).
Each finding names the skill that explains it. --fix applies only the fixes that
are mechanical and safe (marked "fixable"); everything else is reported for a
person or the agent to decide. Exit code: 1 if any error-level finding remains,
else 0.
Requires: pyyaml (pip install pyyaml)
"""

import argparse
import json
import os
import re
import sys
from dataclasses import asdict, dataclass
from pathlib import Path

import yaml  # pylint: disable=import-error

# A fresh install failed at 43 functions and succeeded at 11 with the same
# handlers. The real limit is somewhere in between, so warn well above 11.
FUNCTION_COUNT_WARN = 20
HANDLER_NAME_MIN, HANDLER_NAME_MAX = 5, 64  # foundrycli FunctionHandlerMin/MaxLength
PYCACHE_PATTERN = "(^|/)__pycache__(/|$)"
SECRET_ENV = re.compile(
    # FALCON_CLIENT_ID/SECRET are the documented local-testing fallback for the platform's own token.
    r"""os\.(?:environ(?:\.get)?\s*[\[(]|[gG]etenv\s*\()\s*["']"""
    r"""(?!FALCON_)[A-Z0-9_]*(?:KEY|TOKEN|SECRET|PASSWORD)[A-Z0-9_]*["']"""
)
SOURCE_SUFFIX = {"python": ".py", "go": ".go"}
FAAS_REF = re.compile(r"\.FaaS\.([A-Za-z0-9_-]+)\.([A-Za-z0-9_-]+)\.([A-Za-z0-9_-]+)")
SEVERITY_ORDER = {"error": 0, "warn": 1, "info": 2}


@dataclass
class Finding:
    """One audit result."""

    check: str
    severity: str
    file: str
    message: str
    skill: str
    fixable: bool = False


def _load_yaml(path):
    try:
        return yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    except (OSError, yaml.YAMLError):
        return None


def _load_json(path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def _squash(name):
    """Compare handler names the way workflow data paths spell them (no spaces or separators)."""
    return re.sub(r"[^a-z0-9]", "", str(name).lower())


def _walk(root):
    """Yield (dir, files) under root without descending into hidden directories, which never deploy."""
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if not d.startswith(".")]
        yield Path(dirpath), filenames


def _actions(doc):
    """Yield (key, action) for a workflow's actions, including those inside loops."""
    for key, action in (doc.get("actions") or {}).items():
        if isinstance(action, dict):
            yield key, action
    for loop in (doc.get("loops") or {}).values():
        if isinstance(loop, dict):
            yield from _actions(loop)


class Audit:
    """Runs every check against one app directory."""

    def __init__(self, app_dir):
        self.app = Path(app_dir)
        self.manifest_path = self.app / "manifest.yml"
        loaded = _load_yaml(self.manifest_path)
        self.manifest_invalid = self.manifest_path.is_file() and not isinstance(loaded, dict)
        self.manifest = loaded if isinstance(loaded, dict) else {}
        self.findings = []
        self.functions = {f.get("name"): f for f in self.manifest.get("functions") or []}
        self.ignored = []
        for pattern in self.manifest.get("ignored") or []:
            try:
                self.ignored.append(re.compile(pattern))
            except re.error:
                pass

    def add(self, check, severity, file, message, skill, fixable=False):
        """Record a finding."""
        self.findings.append(Finding(check, severity, str(file), message, skill, fixable))

    def _invalid_file(self, rel):
        """Report a file the manifest points to that exists but doesn't parse."""
        if (self.app / rel).is_file():
            self.add("invalid-file", "error", rel, "doesn't parse, so the checks that read it were skipped.",
                     "debugging-workflows")

    def is_ignored(self, rel_path):
        """Mirror the CLI: hidden path segments are always skipped, then any ignored regex search."""
        if any(part.startswith(".") for part in Path(rel_path).parts):
            return True
        return any(r.search(rel_path) for r in self.ignored)

    # ── functions ─────────────────────────────────────────────
    def check_functions(self):
        """Function count, handler names, and stray __pycache__."""
        if len(self.functions) > FUNCTION_COUNT_WARN:
            self.add("function-count", "warn", "manifest.yml",
                     f"{len(self.functions)} functions. Each is a separate container build; a fresh install "
                     "failed at 43 where the same handlers in 11 functions deployed in about 9 minutes. "
                     "Consolidate related logic.",
                     "functions-development: references/function-count-and-build-time.md")
        stray_caches = []
        for fname, func in self.functions.items():
            seen = set()
            for handler in func.get("handlers") or []:
                name = str(handler.get("name") or "")
                if not HANDLER_NAME_MIN <= len(name) <= HANDLER_NAME_MAX:
                    self.add("handler-name-length", "error", "manifest.yml",
                             f"function '{fname}' handler '{name}' is {len(name)} characters; "
                             f"handler names must be {HANDLER_NAME_MIN} to {HANDLER_NAME_MAX}.",
                             "functions-development: Manifest Structure")
                if name in seen:
                    self.add("handler-name-duplicate", "error", "manifest.yml",
                             f"function '{fname}' has two handlers named '{name}'; names must be unique "
                             "within a function.", "functions-development: Manifest Structure")
                seen.add(name)
            fdir = self.app / str(func.get("path") or "")
            suffix = SOURCE_SUFFIX.get(func.get("language"))
            if not suffix or not fdir.is_dir():
                continue
            for folder, files in _walk(fdir):
                rel_dir = folder.relative_to(self.app).as_posix()
                if suffix == ".py" and folder.name == "__pycache__" and not self.is_ignored(rel_dir + "/x.pyc"):
                    stray_caches.append(rel_dir)
                for name in sorted(files):
                    rel = f"{rel_dir}/{name}"
                    if not name.endswith(suffix) or self.is_ignored(rel):
                        continue
                    for lineno, line in enumerate((folder / name).read_text(encoding="utf-8", errors="ignore")
                                                  .splitlines(), 1):
                        if SECRET_ENV.search(line):
                            self.add("secret-in-env", "warn", f"{rel}:{lineno}",
                                     "reads a credential from an environment variable, which is visible in app "
                                     "exports. Use an API integration so the platform manages it.",
                                     "functions-development: Credential Management")

        if stray_caches:
            self.add("pycache-not-ignored", "warn", "manifest.yml",
                     f"{len(stray_caches)} __pycache__/ director{'y' if len(stray_caches) == 1 else 'ies'} "
                     f"would be deployed ({stray_caches[0]}/ ...); add '{PYCACHE_PATTERN}' to ignored.",
                     "functions-development: requirements.txt Best Practices", fixable=True)

    # ── workflows ─────────────────────────────────────────────
    def _handler(self, fname, hname):
        func = self.functions.get(fname)
        if not func:
            return None, None
        for handler in func.get("handlers") or []:
            if handler.get("name") == hname or _squash(handler.get("name")) == _squash(hname):
                return func, handler
        return func, None

    def _schema_props(self, func, handler, key):
        ref = handler.get(key)
        if not ref:
            return None
        schema = _load_json(self.app / str(func.get("path") or "") / ref)
        if not isinstance(schema, dict):
            return None
        return set((schema.get("properties") or {}).keys())

    def check_workflows(self):
        """provision_on_install, function wiring, request/response schemas."""
        for wf in self.manifest.get("workflows") or []:
            rel = str(wf.get("path") or "")
            doc = _load_yaml(self.app / rel)
            if not isinstance(doc, dict):
                self._invalid_file(rel)
                continue
            if "provision_on_install" not in doc:
                self.add("provision-on-install-missing", "warn", rel,
                         "no provision_on_install; installing the app won't create this workflow. "
                         "Set it to true, unless the app provisions it itself through the Workflows API.",
                         "workflows-development: Prerequisites", fixable=True)
            elif doc.get("provision_on_install") is False:
                self.add("provision-on-install-false", "info", rel,
                         "provision_on_install is false, so installing creates no workflow. Fine if deliberate.",
                         "workflows-development: Prerequisites")
            for key, action in _actions(doc):
                self._check_function_action(rel, key, action)
            text = (self.app / rel).read_text(encoding="utf-8", errors="ignore")
            for fname, hname, field in sorted(set(FAAS_REF.findall(text))):
                func, handler = self._handler(fname, hname)
                if not handler:
                    continue  # can't match the path to a handler, so don't guess
                props = self._schema_props(func, handler, "response_schema")
                if props is not None and field not in props:
                    self.add("response-key-missing", "warn", rel,
                             f"reads '{field}' from {fname}/{handler.get('name')}, but its response_schema "
                             "doesn't declare it, so the workflow sees an empty value.",
                             "functions-development: references/function-count-and-build-time.md")

    def _check_function_action(self, rel, key, action):
        action_id = str(action.get("id") or "")
        if not action_id.startswith("functions."):
            return
        parts = action_id.split(".", 2)
        if len(parts) < 3:
            return
        func, handler = self._handler(parts[1], parts[2])
        if not handler:
            self.add("unknown-function-action", "error", rel,
                     f"action '{key}' calls {action_id}, which isn't a function handler in manifest.yml.",
                     "workflows-development: Calling Functions from Workflows")
            return
        if not handler.get("workflow_integration"):
            self.add("missing-workflow-integration", "error", "manifest.yml",
                     f"{parts[1]}/{handler.get('name')} is called by workflow action '{key}' but has no "
                     "workflow_integration, so deploy fails.", "workflows-development: Calling Functions "
                     "from Workflows")
        passed = set((action.get("properties") or {}).keys())
        if not passed:
            return
        declared = self._schema_props(func, handler, "request_schema")
        missing = passed - (declared or set())
        if missing:
            self.add("request-property-undeclared", "error", rel,
                     f"action '{key}' passes {', '.join(sorted(missing))} to {parts[1]}/{handler.get('name')}, "
                     "but its request_schema doesn't declare them, so they're silently dropped.",
                     "workflows-development: Calling Functions from Workflows")

    # ── API integrations ─────────────────────────────────────
    def check_api_integrations(self):
        """Server variable URLs and defaults that lock the install dropdown."""
        for integ in self.manifest.get("api_integrations") or []:
            rel = str(integ.get("path") or "")
            path = self.app / rel
            spec = _load_json(path) if path.suffix == ".json" else _load_yaml(path)
            if not isinstance(spec, dict):
                self._invalid_file(rel)
                continue
            for server in spec.get("servers") or []:
                variables = server.get("variables") or {}
                url = str(server.get("url", ""))
                if variables and re.match(r"https?://", url):
                    self.add("server-url-protocol", "error", rel,
                             f"server URL {url} has a protocol and variables; the console adds the "
                             "protocol, so it doubles.", "api-integrations: Server URL Configuration")
                for vname, var in variables.items():
                    if isinstance(var, dict) and "default" in var and "enum" not in var:
                        self.add("server-variable-default", "warn", rel,
                                 f"variable '{vname}' has a default but no enum, which renders as a dropdown "
                                 "with one value.", "api-integrations: Server URL Configuration")

    # ── UI ───────────────────────────────────────────────────
    def check_ui(self):
        """Deploy ships dist/ as is, so it must exist and be newer than the source."""
        ui = self.manifest.get("ui") or {}
        entries = list((ui.get("pages") or {}).values()) + list(ui.get("extensions") or [])
        for entry in entries:
            if not entry.get("entrypoint"):
                continue  # a JSON-defined extension has no dist/ to build
            dist = self.app / str(entry.get("path") or "")
            # Blueprints build either <page>/dist from <page>/src or <page>/src/dist from <page>/src.
            src = dist.parent if dist.parent.name == "src" else dist.parent / "src"
            if not dist.is_dir():
                self.add("ui-not-built", "error", str(entry.get("path")),
                         "dist/ doesn't exist; deploy never builds the UI. Run npm run build.",
                         "development-workflow: Step 7")
            elif src.is_dir():
                newest_src = max((p.stat().st_mtime for p in src.rglob("*")
                                  if p.is_file() and dist not in p.parents), default=0)
                newest_dist = max((p.stat().st_mtime for p in dist.rglob("*") if p.is_file()), default=0)
                if newest_src > newest_dist:
                    self.add("ui-stale-build", "warn", str(entry.get("path")),
                             "src/ is newer than dist/; deploy would ship the previous build. Run npm run build.",
                             "development-workflow: Step 7")

    def run(self):
        """Run every check and return findings, most severe first."""
        if not self.manifest_path.is_file():
            self.add("no-manifest", "error", str(self.manifest_path), "no manifest.yml here.",
                     "development-workflow")
            return self.findings
        if self.manifest_invalid:
            self.add("invalid-file", "error", "manifest.yml", "doesn't parse as a YAML mapping, so nothing "
                     "else could be checked.", "debugging-workflows")
            return self.findings
        self.check_functions()
        self.check_workflows()
        self.check_api_integrations()
        self.check_ui()
        self.findings.sort(key=lambda f: (SEVERITY_ORDER[f.severity], f.check, f.file))
        return self.findings


def _add_ignored(text, pattern):
    """Append one pattern to the top-level ignored: list, matching how the list is already written.

    Returns the text unchanged when ignored: is written in a shape this can't edit safely
    (a multi-line flow list, say), rather than adding a second ignored: key.
    """
    lines = text.splitlines(keepends=True)
    quoted = f"'{pattern}'"
    for i, line in enumerate(lines):
        if not line.startswith("ignored:"):
            continue
        match = re.match(r"ignored:[ \t]*(?:\[(.*)\]|null|~)?[ \t]*(#.*)?$", line.rstrip("\n"))
        if not match:
            return text
        comment = f" {match.group(2)}" if match.group(2) else ""
        if match.group(1) is not None:  # flow style: ignored: [] or ignored: [a, b]
            items = match.group(1).strip()
            lines[i] = f"ignored: [{items + ', ' if items else ''}{quoted}]{comment}\n"
            return "".join(lines)
        lines[i] = f"ignored:{comment}\n"  # block style; an explicit null becomes an empty block
        last, indent = i, "  "
        for j in range(i + 1, len(lines)):
            item = re.match(r"([ \t]*)- ", lines[j])
            if item:
                last, indent = j, item.group(1)
            elif lines[j].strip() and not lines[j].startswith((" ", "\t")):
                break
        if not lines[last].endswith("\n"):
            lines[last] += "\n"
        lines.insert(last + 1, f"{indent}- {quoted}\n")
        return "".join(lines)
    return text.rstrip("\n") + f"\nignored:\n  - {quoted}\n"


def apply_fixes(app_dir, findings):
    """Apply the fixable findings with line edits so the rest of each file stays as written."""
    app = Path(app_dir)
    fixed = []
    for f in findings:
        if not f.fixable:
            continue
        if f.check == "pycache-not-ignored":
            path = app / "manifest.yml"
            before = path.read_text(encoding="utf-8")
            after = _add_ignored(before, PYCACHE_PATTERN)
            if after != before:
                path.write_text(after, encoding="utf-8")
                fixed.append(f)
        elif f.check == "provision-on-install-missing":
            path = app / f.file
            lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
            at = next((i + 1 for i, line in enumerate(lines) if re.match(r"(name|description):", line)), 0)
            # Step past a block scalar or other continuation lines so the key stays top level.
            while 0 < at < len(lines) and (not lines[at].strip() or lines[at][0] in " \t"):
                at += 1
            if at and not lines[at - 1].endswith("\n"):
                lines[at - 1] += "\n"
            lines.insert(at, "provision_on_install: true\n")
            path.write_text("".join(lines), encoding="utf-8")
            fixed.append(f)
    return fixed


def main(argv=None):
    """CLI entry point."""
    parser = argparse.ArgumentParser(description="Audit a Falcon Foundry app for documented anti-patterns.")
    parser.add_argument("app_dir", nargs="?", default=".")
    parser.add_argument("--json", action="store_true", help="print findings as JSON")
    parser.add_argument("--fix", action="store_true", help="apply the safe, mechanical fixes")
    args = parser.parse_args(argv)

    findings = Audit(args.app_dir).run()
    if args.fix and any(f.fixable for f in findings):
        apply_fixes(args.app_dir, findings)
        findings = Audit(args.app_dir).run()

    if args.json:
        print(json.dumps([asdict(f) for f in findings], indent=2))
    else:
        for f in findings:
            tag = " (fixable with --fix)" if f.fixable else ""
            print(f"{f.severity.upper():5} {f.check}  {f.file}\n      {f.message}{tag}\n      see {f.skill}")
        counts = {s: sum(f.severity == s for f in findings) for s in SEVERITY_ORDER}
        print(f"{counts['error']} error(s), {counts['warn']} warning(s), {counts['info']} info")
    return 1 if any(f.severity == "error" for f in findings) else 0


if __name__ == "__main__":
    sys.exit(main())
