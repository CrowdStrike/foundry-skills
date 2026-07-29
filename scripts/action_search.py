#!/usr/bin/env python3
"""Search Foundry workflow actions by name via the CrowdStrike API.

Usage:
    python3 scripts/action_search.py "send email"
    python3 scripts/action_search.py "contain" --details

Reads credentials from the active Foundry CLI profile.
Requires: falconpy, pyyaml (pip install crowdstrike-falconpy pyyaml)
"""

import argparse
import sys
from pathlib import Path

import yaml  # pylint: disable=import-error
from falconpy import Workflows  # pylint: disable=import-error


def get_credentials():
    """Read credentials from the active Foundry CLI profile."""
    config_path = Path.home() / ".config" / "foundry" / "configuration.yml"
    with open(config_path, encoding="utf-8") as f:
        cfg = yaml.safe_load(f)
    active = cfg.get("active_profile", cfg["profiles"][0]["name"])
    profile = next(p for p in cfg["profiles"] if p["name"] == active)
    region = profile.get("cloud_region", "us-1") or "us-1"
    base_urls = {
        "us-1": "https://api.crowdstrike.com",
        "us-2": "https://api.us-2.crowdstrike.com",
        "eu-1": "https://api.eu-1.crowdstrike.com",
        "us-gov-1": "https://api.laggar.gcw.crowdstrike.com",
        "us-gov-2": "https://api.us-gov-2.crowdstrike.com",
    }
    return {
        "client_id": profile["credentials"]["api_client_id"],
        "client_secret": profile["credentials"]["api_client_secret"],
        "base_url": base_urls.get(region, base_urls["us-1"]),
    }


def search_actions(query, details=False):
    """Search for workflow actions matching the query."""
    creds = get_credentials()
    falcon = Workflows(
        client_id=creds["client_id"],
        client_secret=creds["client_secret"],
        base_url=creds["base_url"],
    )

    response = falcon.search_activities(
        filter=f"name:~'{query}'",
        sort="name",
        limit=20,
    )

    if response["status_code"] != 200:
        body = response["body"]
        errors = body.get("errors", []) if isinstance(body, dict) else []
        print(f"Error: {errors}", file=sys.stderr)
        sys.exit(1)

    body = response["body"]
    resources = body.get("resources", []) if isinstance(body, dict) else []
    if not resources:
        print(f"No actions found matching '{query}'.")
        sys.exit(0)

    print(f"Found {len(resources)} action(s) matching '{query}':\n")
    for r in resources:
        sem = r.get("semantic_version", "")
        constraint = f"~{sem.split('.')[0]}" if sem else "~0"

        if details:
            note = f"(semantic_version: {sem})" if sem else "(no semantic_version)"
            print(f"  {r['name']}")
            print(f"    id: {r['id']}")
            print(f"    version_constraint: {constraint}  {note}")
            props = r.get("properties", {})
            if props:
                print("    properties:")
                for pname, pschema in props.items():
                    req = " (required)" if pschema.get("required") else ""
                    print(f"      {pname} [{pschema.get('type', '?')}]{req}")
            print()
        else:
            print(f"  {r['id']}: {r['name']}  (version_constraint: {constraint})")


def main():
    """Parse arguments and run the action search."""
    parser = argparse.ArgumentParser(description="Search Foundry workflow actions")
    parser.add_argument("query", help="Action name to search for (fuzzy match)")
    parser.add_argument("--details", action="store_true",
                        help="Show full details including properties")
    args = parser.parse_args()
    search_actions(args.query, details=args.details)


if __name__ == "__main__":
    main()
