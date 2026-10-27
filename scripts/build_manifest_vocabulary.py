#!/usr/bin/env python3
"""Build the manifest field vocabulary the skill-snippet test checks against.

Reads the manifest.yml of each public foundry-sample-* app and writes every
field path it uses to tests/fixtures/manifest-vocabulary.json. List items
become `[]`, and maps keyed by IDs or names (pages, dashboards, permissions,
environment variables) become `*`, so a path names a field, not a value.

Usage: python3 scripts/build_manifest_vocabulary.py ~/dev/foundry-sample-*
"""

import json
import sys
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
}
OUT = Path(__file__).resolve().parent.parent / "tests" / "fixtures" / "manifest-vocabulary.json"


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


def main(sample_dirs):
    paths, sources = set(), []
    for sample in sorted(Path(d) for d in sample_dirs):
        manifest = sample / "manifest.yml"
        if not manifest.is_file():
            continue
        paths.update(field_paths(yaml.safe_load(manifest.read_text(encoding="utf-8"))))
        sources.append(sample.name)
    # A keyed map's children are app-chosen names, even where every sample's map is empty
    paths.update(f"{m}.*" for m in KEYED_MAPS)
    paths.update(CLI_FIELDS)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({"sources": sources, "paths": sorted(paths)}, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {len(paths)} field paths from {len(sources)} manifests to {OUT}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    main(sys.argv[1:])
