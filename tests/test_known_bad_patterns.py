"""Known-bad patterns must not come back into the skills.

Each entry is an API call, manifest field, or ID format that once appeared in a
skill, looked plausible, and was wrong: invented foundry-js methods, manifest
keys the CLI never writes, an action-ID shape that doesn't exist. Agents copy
these examples, so a single regression ships broken apps. The whole of
skills/ and AGENTS.md is scanned, not just the file where each was first found.
"""

import os
import re

import pytest

_ROOT = os.environ.get("SKILLS_ROOT") or os.path.join(os.path.dirname(__file__), "..")

# (pattern, why it's wrong). Patterns are regexes matched against each file.
BANNED = [
    # foundry-js 0.22.0 (dist/abstraction/*.d.ts, dist/api.d.ts)
    (r"new Collection<", "collections come from falcon.collection({ collection }), not a constructor"),
    (r"\bcollection\.(get|query|update)\(", "foundry-js collections have write/read/delete/search/list"),
    (r"this\.collection\.create\(", "foundry-js collections have no create(); write() creates or overwrites"),
    (r"collection\.(write|read|delete)\(\{", "collection write/read/delete take the key as a string"),
    (r"falcon\.cloudFunction\(\)", "cloudFunction() requires { name } or { id }"),
    (r"\n\s*\.query\(\{ limit", "CloudFunction paths have no .query(); put query strings in the path"),
    (r"falcon\.workflow\(", "there is no falcon.workflow(); use falcon.api.workflows"),
    (r"events\.broadcast\(", "broadcast with falcon.sendBroadcast()"),
    (r"navigation\.openModal\(", "modals open with falcon.ui.openModal(identifier, title, options)"),
    (r"import \{[^}]*\bMigration\b[^}]*\} from '@crowdstrike/foundry-js'", "foundry-js exports no Migration type"),
    (r"@crowdstrike/foundry-js/react", "foundry-js exports only . and ./apis/*; there are no React hooks"),
    (r"\buseFoundry(Extension)?\b", "foundry-js has no hooks; use the FalconApi instance"),
    (r"foundry\.api\.get\(|onContextChange", "use falcon.api.<namespace>.<method> and falcon.events.on('data')"),
    (r"\.postMessage\([^)]*'\*'\)", "posting to '*' leaks data; foundry-js already targets the console origin"),
    (r"CONTEXT_UPDATE|ACTION_REQUEST|DATA_RESPONSE", "not foundry-js message types"),
    (r"SecureConsoleMessaging|addEventListener\(['\"]message['\"]", "foundry-js owns the console channel; use falcon.events and falcon.sendBroadcast"),
    (r"<sl-(table|form)\b", "Shoelace 2.x has no table or form component"),
    (r"shoelace@2\.x/", "pin the installed Shoelace version"),
    (r"var\(--link-color\)", "not a Toucan token"),
    # Functions (crowdstrike-foundry-function FDK, foundry-fn-go, FalconPy)
    (r"def handler\(event", "the FDK entry point is @func.handler with func.run(), not a lambda-style handler"),
    (r"request\.params\.get\([\"']", "RequestParams has header and query only; use params.query[...]"),
    (r"ingest_data\(body=", "ingest_data needs data_file=; body= raises KeyError 'file'"),
    (r"falconpy\.api_complete import", "api_complete exports no operation names"),
    (r"X-CS-ACCESSTOKEN", "Go handlers get the token from r.AccessToken"),
    (r"github\.com/crowdstrike/foundry-fn-go", "the module path is github.com/CrowdStrike/foundry-fn-go (case-sensitive)"),
    (r"falcon\.NewClient\(fdk\.FalconClientOpts\(\)\)", "falcon.NewClient takes *falcon.ApiConfig"),
    (r"localhost:8081/[A-Za-z]", "the local FDK runner routes on the JSON envelope's url, posted to the root URL"),
    (r"(APIIntegrations\(\)|api_integrations)\.execute\(", "FalconPy has no execute(); use execute_command_proxy()"),
    (r"\.update_case\(|`update_case`", "the CaseManagement method is update_case_fields"),
    (r"product:'detections'", "not an Alerts product value; endpoint detections are epp"),
    (r"self\.collection\.query\(|\{'\$(gte|gt|lte|lt|in|eq)'", "collection search takes FQL strings via SearchObjects"),
    (r"if not auth\.token\(\)", "token() returns a dict, which is always truthy"),
    # Falcon Fusion SOAR
    (r"\binvokeFunction\b|\bactivity: (read|write)Collection\b|`(read|write)Collection`", "workflows call functions.<name>.<handler> and collections.<name>.<op>"),
    (r"b3305a8e09d3430b9cd4e2fc1dfa73f3", "a node-key suffix; Put and run file is a29b38809708ffc5fb18a03676520b1a"),
    (r"path: workflows/[^\s/]+/workflow\.ya?ml", "workflow manifest paths are flat workflows/<Name>.yml"),
    # CLI flags (foundry --help, CLI 2.1.2)
    (r"foundry ui run --port|foundry profile active\b", "ui run has no --port; profile has activate/create/delete/list"),
    (r"rtr-scripts run[^\n]*--name\b", "rtr-scripts run takes --script-name"),
    (r"foundry apps clone[^\n]*--name", "apps clone has no --name flag"),
    (r"falcon\.us-gov(-1)?\.crowdstrike\.com", "the US-GOV-1 console is falcon.laggar.gcw.crowdstrike.com"),
    (r"update_ids", "no such command; IDs are filled by foundry apps validate or deploy"),
    # Manifest format (tests/fixtures/manifest-vocabulary.json)
    (r"^\s+csp:\s*$", "page CSP lives under content_security_policy:"),
    (r"\bconnect_src\b|\bimg_src\b|\bscript_src\b|\bdefault_src\b", "CSP directives are hyphenated (connect-src)"),
    (r"^\s+read_only: true", "collections have no read_only field; gate them with permissions"),
    (r"^\s+ttl:", "collections have no ttl; Falcon Foundry drops it from the deployed manifest"),
    (r"collections/\w+/schema\.json", "collection schemas live at collections/<name>.json"),
    (r"'X-Frame-Options'", "Falcon Foundry apps can't set response headers"),
    (r"FOUNDRY_UI_(HOST|PORT|HTTPS)", "not Foundry CLI settings"),
    # AI agents
    (r"reasoning_effort", "Reasoning Effort is an AgentWorks Model settings field, not a manifest key"),
    (r"<name>_<cid>", "agent action IDs resolve to <uuid>_<cid>"),
]


def _files():
    paths = [os.path.join(dirpath, name)
             for dirpath, _, names in os.walk(os.path.join(_ROOT, "skills"))
             for name in names if name.endswith(".md")]
    paths.append(os.path.join(_ROOT, "AGENTS.md"))
    return sorted(p for p in paths if os.path.exists(p))


FILES = _files()


@pytest.mark.parametrize("pattern,reason", BANNED, ids=[b[0] for b in BANNED])
def test_known_bad_pattern_is_gone(pattern, reason):
    regex = re.compile(pattern, re.MULTILINE)
    hits = []
    for path in FILES:
        with open(path, encoding="utf-8") as f:
            text = f.read()
        for match in regex.finditer(text):
            line = text.count("\n", 0, match.start()) + 1
            hits.append(f"{os.path.relpath(path, _ROOT)}:{line}")
    assert not hits, f"{reason}: {', '.join(hits)}"
