#!/usr/bin/env python3
"""Build the manifest field vocabulary the skill-snippet test checks against.

Fetches manifest.yml from each public CrowdStrike/foundry-sample-* repo on
GitHub and writes every field path it uses to
tests/fixtures/manifest-vocabulary.json. List items become `[]`, and maps keyed
by IDs or names (pages, dashboards, permissions, environment variables) become
`*`, so a path names a field, not a value. Nothing needs to be cloned.

Usage:
    python3 scripts/build_manifest_vocabulary.py                  # refresh the samples in the fixture
    python3 scripts/build_manifest_vocabulary.py foundry-sample-x  # add samples to the fixture
"""

import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

import yaml  # pylint: disable=import-error

# Maps whose keys are names the app chooses, not manifest fields
KEYED_MAPS = {
    "ui.pages", "ui.dashboards", "auth.permissions",
    "functions[].environment_variables", "functions[].config",
}
# Real fields newer than every sample, each confirmed as a yaml struct tag in the
# foundry CLI binary (strings $(command -v foundry) | grep 'yaml:"<field>').
CLI_FIELDS = {
    "collections[].agent_tools_integration",  # collections create --agent-tools-expose (CLI 2.1.2)
    "collections[].agent_tools_integration.exposed",
    # ai.agents and ai.knowledge_bases: no public sample uses them yet
    "ai", "ai.agents", "ai.knowledge_bases",
    *(f"ai.agents[].{f}" for f in (
        "id", "name", "description", "path", "model", "tools", "system_prompt", "input_format",
        "input_schema", "output_format", "output_schema", "knowledge_bases", "exposure")),
    "ai.agents[].exposure.workflows", "ai.agents[].exposure.workflows.system_action",
    "ai.agents[].exposure.charlotte_chat", "ai.agents[].exposure.agent_as_tool",
    *(f"ai.knowledge_bases[].{f}" for f in ("id", "name", "description", "encrypt", "path", "files")),
}
OUT = Path(__file__).resolve().parent.parent / "tests" / "fixtures" / "manifest-vocabulary.json"
RAW = "https://raw.githubusercontent.com/CrowdStrike/{repo}/main/manifest.yml"


def field_paths(node, path=""):
    """Yield every field path under node."""
    if isinstance(node, dict):
        for key, value in node.items():
            child = f"{path}.*" if path in KEYED_MAPS else (f"{path}.{key}" if path else str(key))
            yield child
            yield from field_paths(value, child)
    elif isinstance(node, list):
        for item in node:
            yield from field_paths(item, f"{path}[]")


def fetch_manifest(repo):
    """Return the parsed manifest.yml of a public CrowdStrike repo, or None if unavailable."""
    try:
        with urllib.request.urlopen(RAW.format(repo=repo), timeout=30) as response:
            return yaml.safe_load(response.read().decode("utf-8"))
    except urllib.error.URLError as error:
        print(f"Skipping {repo}: {error}", file=sys.stderr)
        return None


def main(added_repos):
    repos = set(added_repos)
    if OUT.exists():
        repos.update(json.loads(OUT.read_text(encoding="utf-8"))["sources"])
    paths, sources = set(), []
    for repo in sorted(repos):
        manifest = fetch_manifest(repo)
        if manifest is None:
            continue
        paths.update(field_paths(manifest))
        sources.append(repo)
    # A keyed map's children are app-chosen names, even where every sample's map is empty
    paths.update(f"{m}.*" for m in KEYED_MAPS)
    paths.update(CLI_FIELDS)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({"sources": sources, "paths": sorted(paths)}, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {len(paths)} field paths from {len(sources)} manifests to {OUT}")


if __name__ == "__main__":
    main(sys.argv[1:])
