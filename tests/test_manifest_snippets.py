"""Manifest snippets in the skills must use fields the real manifest format has.

Agents copy YAML blocks from the skills into manifest.yml, so an invented field
(`csp:`, `read_only:`) or a wrong shape (a list where ui.pages is a map) ships
as a broken manifest. Each manifest-shaped block is checked against the field
paths the public foundry-sample-* manifests use, recorded in
tests/fixtures/manifest-vocabulary.json by scripts/build_manifest_vocabulary.py.

Skip a block on purpose (an example of what not to write) with
`<!-- snippet-check: skip -->` on the line before it.
"""

import json
import os
import re
import sys

import pytest
import yaml

_ROOT = os.environ.get("SKILLS_ROOT") or os.path.join(os.path.dirname(__file__), "..")
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))
from build_manifest_vocabulary import field_paths  # noqa: E402  pylint: disable=wrong-import-position

VOCABULARY = json.load(open(os.path.join(os.path.dirname(__file__), "fixtures", "manifest-vocabulary.json"),
                            encoding="utf-8"))
KNOWN = set(VOCABULARY["paths"])
# Top-level keys only a manifest has; a block needs one of these to be checked
MANIFEST_SECTIONS = {"ui", "auth", "functions", "collections", "api_integrations", "ai", "rtr_scripts", "logscale"}
TOP_LEVEL = {p for p in KNOWN if "." not in p and "[" not in p}
FENCE = re.compile(r"^\s*```ya?ml\s*$")
SKIP = "<!-- snippet-check: skip -->"


def _yaml_blocks():
    files = [os.path.join(dirpath, name)
             for dirpath, _, names in os.walk(os.path.join(_ROOT, "skills"))
             for name in names if name.endswith(".md")]
    agents = os.path.join(_ROOT, "AGENTS.md")
    if os.path.exists(agents):
        files.append(agents)
    for path in sorted(files):
        with open(path, encoding="utf-8") as f:
            lines = f.read().split("\n")
        i = 0
        while i < len(lines):
            if FENCE.match(lines[i]):
                prev = next((l for l in reversed(lines[:i]) if l.strip()), "")
                end = i + 1
                while end < len(lines) and lines[end].strip() != "```":
                    end += 1
                if prev.strip() != SKIP:
                    yield os.path.relpath(path, _ROOT), i + 1, "\n".join(lines[i + 1:end])
                i = end
            i += 1


def _manifest_blocks():
    for path, line, text in _yaml_blocks():
        try:
            doc = yaml.safe_load(text)
        except yaml.YAMLError:
            continue  # fragments with placeholders like `…` aren't parseable
        if isinstance(doc, dict) and set(doc) & MANIFEST_SECTIONS and set(doc) <= TOP_LEVEL:
            yield path, line, doc


BLOCKS = list(_manifest_blocks())


def test_vocabulary_covers_the_samples():
    assert len(VOCABULARY["sources"]) >= 10
    assert "ui.pages.*.content_security_policy.connect-src" in KNOWN


def test_some_manifest_blocks_are_checked():
    assert len(BLOCKS) >= 5, "the block detector stopped finding manifest snippets"


@pytest.mark.parametrize("path,line,doc", BLOCKS, ids=[f"{p}:{l}" for p, l, _ in BLOCKS])
def test_manifest_snippet_uses_real_fields(path, line, doc):
    unknown = sorted(set(field_paths(doc)) - KNOWN)
    assert not unknown, (
        f"{path}:{line} uses manifest fields no sample manifest has: {unknown}. "
        "Fix the snippet, or regenerate tests/fixtures/manifest-vocabulary.json if the field is real."
    )
