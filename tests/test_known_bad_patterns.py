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
    (r"activity: (read|write)Collection\b", "Falcon Fusion SOAR has no readCollection/writeCollection activity"),
    # Manifest format (tests/fixtures/manifest-vocabulary.json)
    (r"^\s+csp:\s*$", "page CSP lives under content_security_policy:"),
    (r"\bconnect_src\b|\bimg_src\b|\bscript_src\b|\bdefault_src\b", "CSP directives are hyphenated (connect-src)"),
    (r"^\s+read_only: true", "collections have no read_only field; gate them with permissions"),
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
