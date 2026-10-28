"""TypeScript and JavaScript snippets in the skills must type-check against foundry-js.

Runs tests/snippets/check.mjs, which compiles every TS/JS block against the
pinned @crowdstrike/foundry-js types and reports only errors that involve the
SDK (a method that doesn't exist, a wrong argument shape). Needs Node and
`npm ci --prefix tests/snippets`; CI installs both.
"""

import os
import shutil
import subprocess

import pytest

_HERE = os.path.dirname(__file__)
_ROOT = os.environ.get("SKILLS_ROOT") or os.path.join(_HERE, "..")
_SNIPPETS = os.path.join(_HERE, "snippets")
_INSTALLED = os.path.isdir(os.path.join(_SNIPPETS, "node_modules", "@crowdstrike", "foundry-js"))


@pytest.mark.skipif(not (shutil.which("node") and _INSTALLED),
                    reason="run `npm ci --prefix tests/snippets` to type-check snippets")
def test_snippets_type_check_against_foundry_js():
    result = subprocess.run(["node", os.path.join(_SNIPPETS, "check.mjs"), _ROOT],
                            capture_output=True, text=True, timeout=300, check=False)
    assert result.returncode == 0, result.stdout + result.stderr
    assert "Checked" in result.stdout
