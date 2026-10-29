#!/usr/bin/env python3
"""Deploy a Falcon Foundry app, wait for the deployment, then release it.

`foundry apps deploy --no-prompt` returns as soon as the deployment starts, so
an agent otherwise spends three or more turns on deploy, polling
`list-deployments`, and release. This does all three in one call: it deploys
once, polls for the version deploy printed (not the newest row), and releases
that deployment's ID when it succeeds.

Run it from the app root (where manifest.yml lives):
    deploy_and_release.py --change-log "Initial app" [--change-type Patch]
        [--notes "Release notes"] [--no-release] [--timeout 900]

Exit codes: 0 released (or deployed with --no-release), 1 deploy, deployment,
or release failed, 2 not in an app root, 3 still in progress at the timeout.
"""

import argparse
import os
import re
import subprocess
import sys
import time

VERSION_RE = re.compile(r"Deployment (v\S+) in progress")
FILE_LINE_RE = re.compile(r"^\s*◦\s+(\S.*)$")


def run(cmd):
    """Run a CLI command; return (exit code, combined stdout and stderr)."""
    proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
    return proc.returncode, proc.stdout + proc.stderr


def parse_version(output):
    """Return the deployment version `foundry apps deploy` printed, or None."""
    match = VERSION_RE.search(output)
    return match.group(1) if match else None


def find_deployment(table, version):
    """Return (deployment ID, state) for `version` in list-deployments output."""
    for line in table.splitlines():
        cells = [c.strip() for c in line.split("│")[1:-1]]
        if len(cells) >= 3 and cells[1] == version:
            return cells[0], cells[2]
    return None


def summarize_deploy(output):
    """Collapse the packaged-file list, keeping dist/ files so a stale build shows."""
    kept, others = [], 0
    for line in output.splitlines():
        match = FILE_LINE_RE.match(line)
        if not match:
            kept.append(line)
        elif "/dist/" in match.group(1):
            kept.append(line)
        else:
            others += 1
    if others:
        kept.append(f"\t(+ {others} other packaged files)")
    return "\n".join(kept).strip()


def wait_for(runner, version, timeout, interval):
    """Poll until the deployment leaves 'In progress'; return (id, state)."""
    deadline = time.monotonic() + timeout
    found = None
    while True:
        _, table = runner(["foundry", "apps", "list-deployments"])
        found = find_deployment(table, version) or found
        if found and "progress" not in found[1].lower():
            return found
        if time.monotonic() >= deadline:
            return found or ("", "not listed yet")
        time.sleep(interval)


def finish(args, runner, version):
    """Wait for `version`, then release it unless --no-release; return the exit code."""
    dep_id, state = wait_for(runner, version, args.timeout, args.interval)
    print(f"\nDeployment {version} ({dep_id or 'no ID yet'}): {state}")
    if "progress" in state.lower() or not dep_id:
        print("It is still in progress. Don't deploy again; poll `foundry apps list-deployments`, then run:\n"
              f"  foundry apps release --change-type {args.change_type} --deployment-id {dep_id} "
              f"--notes \"...\" --no-prompt")
        return 3
    if "success" not in state.lower():
        print("The CLI doesn't show why. Open the app in App manager and click \"Show errors\" "
              "for each failed capability.")
        return 1
    if args.no_release:
        return 0

    code, out = runner(["foundry", "apps", "release", "--change-type", args.change_type,
                        "--deployment-id", dep_id, "--notes", args.notes or args.change_log,
                        "--no-prompt"])
    print(out.strip())
    if code != 0:
        return code
    print(f"\nReleased deployment {dep_id} ({version}).")
    return 0


def main(argv=None, runner=run):
    """Deploy, wait, and release; return the process exit code."""
    parser = argparse.ArgumentParser(
        description="Deploy a Falcon Foundry app, wait for the deployment, then release it.")
    parser.add_argument("--change-log", required=True)
    parser.add_argument("--change-type", default="Patch", choices=("Major", "Minor", "Patch"))
    parser.add_argument("--notes", help="release notes (default: the change log)")
    parser.add_argument("--no-release", action="store_true", help="deploy and wait only")
    parser.add_argument("--timeout", type=int, default=900, help="seconds to wait (default 900)")
    parser.add_argument("--interval", type=int, default=5, help="seconds between polls")
    args = parser.parse_args(argv)

    if not os.path.isfile("manifest.yml"):
        print("Run this from the app root, where manifest.yml lives.")
        return 2

    code, out = runner(["foundry", "apps", "deploy", "--no-prompt",
                        "--change-type", args.change_type, "--change-log", args.change_log])
    print(summarize_deploy(out))
    version = parse_version(out)
    if code != 0 or not version:
        return code or 1

    return finish(args, runner, version)

if __name__ == "__main__":
    sys.exit(main())
