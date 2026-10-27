#!/usr/bin/env python3
"""Upgrade a Falcon Foundry app installed from a template, in place.

Usage:
    python3 skills/app-upgrades/scripts/upgrade_manifest.py resolve SOURCE --dest DIR
    python3 skills/app-upgrades/scripts/upgrade_manifest.py find-template --manifest PATH
    python3 skills/app-upgrades/scripts/upgrade_manifest.py merge --deployed PATH --template PATH

merge copies the IDs of a deployed app into a newer template's manifest so
`foundry apps deploy` updates the existing app instead of creating a new one.
Requires: pyyaml; find-template also needs falconpy
(pip install crowdstrike-falconpy pyyaml)
"""

import argparse
import json
import re
import shutil
import subprocess
import sys
import tarfile
import zipfile
from pathlib import Path, PurePosixPath

import yaml  # pylint: disable=import-error

ID_KEYS = ("id", "app_id")


class MergeError(ValueError):
    """The manifests can't be merged safely."""


def _strip_ids(node):
    if isinstance(node, dict):
        return {k: _strip_ids(v) for k, v in node.items() if k not in ID_KEYS}
    if isinstance(node, list):
        return [_strip_ids(v) for v in node]
    return node


def _has_ids(node):
    if isinstance(node, dict):
        return any(node.get(k) for k in ID_KEYS) or any(_has_ids(v) for v in node.values())
    if isinstance(node, list):
        return any(_has_ids(v) for v in node)
    return False


def _index_by_name(items, path):
    index = {}
    for item in items:
        name = item["name"]
        if name in index:
            raise MergeError(f"{path} has two entries named {name!r}; names must be unique to match artifacts.")
        index[name] = item
    return index


def _merge_dict(deployed, new, path):
    if not isinstance(deployed, dict):
        return _strip_ids(new)
    merged = {}
    for key in ID_KEYS:
        if key not in new and deployed.get(key):
            merged[key] = deployed[key]
    for key, value in new.items():
        if key in ID_KEYS:
            if deployed.get(key):
                merged[key] = deployed[key]
            continue
        merged[key] = _merge(deployed.get(key), value, f"{path}.{key}" if path else key)
    return merged


def _merge_list(deployed, new, path):
    if not all(isinstance(item, dict) for item in new):
        return list(new)
    deployed = deployed if isinstance(deployed, list) else []
    if not all("name" in item for item in new):
        if _has_ids(deployed):
            raise MergeError(f"{path} has entries with IDs but no name to match them on; upgrade this app by hand.")
        return _strip_ids(new)
    _index_by_name(new, path)
    index = _index_by_name([d for d in deployed if isinstance(d, dict) and "name" in d], path)
    return [_merge(index.get(item["name"]), item, f"{path}[{item['name']}]") for item in new]


def _merge(deployed, new, path):
    if isinstance(new, dict):
        return _merge_dict(deployed, new, path)
    if isinstance(new, list):
        return _merge_list(deployed, new, path)
    return new


def merge_ids(deployed, template):
    """Return the template manifest with the deployed app's IDs filled in."""
    if not deployed.get("app_id"):
        raise MergeError("The deployed manifest has no app_id. Sync the app with `foundry apps sync --app-id` first.")
    merged = _merge(deployed, template, "")
    # The customer may have renamed the app, so the deployed name wins.
    if deployed.get("name"):
        merged["name"] = deployed["name"]
    return merged


ARTIFACT_SECTIONS = (
    "functions", "collections", "workflows", "api_integrations", "rtr_scripts",
    "parsers", "lookup_files", "ai.agents", "ai.knowledge_bases",
    "logscale.saved_searches", "ui.pages", "ui.extensions", "ui.dashboards",
    "ui.navigation.links", "auth.permissions", "auth.roles",
)


def _section_names(manifest, section):
    node = manifest
    for part in section.split("."):
        node = node.get(part) if isinstance(node, dict) else None
    if isinstance(node, dict):
        return set(node)
    if isinstance(node, list):
        return {item["name"] for item in node if isinstance(item, dict) and "name" in item}
    return set()


def _section_items(manifest, section):
    node = manifest
    for part in section.split("."):
        node = node.get(part) if isinstance(node, dict) else None
    if isinstance(node, dict):
        return node
    if isinstance(node, list):
        return {item["name"]: item for item in node if isinstance(item, dict) and "name" in item}
    return {}


def build_plan(deployed, template):
    """Compare artifacts by section: what the upgrade keeps, adds, and removes."""
    plan = {"kept": {}, "added": {}, "removed": {}, "access_changes": {},
            "possible_renames": [], "data_loss": []}
    for section in ARTIFACT_SECTIONS:
        old, new = _section_names(deployed, section), _section_names(template, section)
        for group, names in (("kept", old & new), ("added", new - old), ("removed", old - new)):
            if names:
                plan[group][section] = sorted(names)
        if new - old and old - new:
            plan["possible_renames"].append(section)
        old_items, new_items = _section_items(deployed, section), _section_items(template, section)
        for name in old & new:
            before, after = old_items.get(name), new_items.get(name)
            if isinstance(before, dict) and isinstance(after, dict):
                old_permissions = set(before.get("permissions") or [])
                new_permissions = set(after.get("permissions") or [])
                if old_permissions != new_permissions:
                    plan["access_changes"][f"{section}.{name}"] = {
                        "removed": sorted(old_permissions - new_permissions),
                        "added": sorted(new_permissions - old_permissions),
                    }
    plan["data_loss"] = plan["removed"].get("collections", [])
    plan["needs_confirmation"] = bool(plan["removed"] or plan["access_changes"])
    return plan


def format_plan(plan):
    """Render a plan for the person running the upgrade."""
    lines = []
    for group in ("kept", "added", "removed"):
        for section, names in plan[group].items():
            lines.append(f"{group.capitalize()} {section}: {', '.join(names)}")
    for section in ("auth.permissions", "auth.roles"):
        if section in plan["removed"]:
            lines.append(f"WARNING: removing {section} changes app access.")
    for path, changes in plan["access_changes"].items():
        detail = "; ".join(f"{direction} {', '.join(permissions)}"
                           for direction, permissions in changes.items() if permissions)
        lines.append(f"WARNING: access change in {path}: {detail}")
    for name in plan["data_loss"]:
        lines.append(f"WARNING: removing collection {name!r} deletes its stored data.")
    for section in plan["possible_renames"]:
        lines.append(f"WARNING: {section} has additions and removals; a possible rename loses the old artifact's ID.")
    return "\n".join(lines) or "No artifacts found."


class SourceError(ValueError):
    """The new template version can't be used."""


def _check_member(name):
    path = PurePosixPath(name.replace("\\", "/"))
    if path.is_absolute() or ".." in path.parts or (path.parts and path.parts[0].endswith(":")):
        raise SourceError(f"The archive has an unsafe path ({name}). Use the archive from the template's repository.")


def _require_empty(dest):
    """Validate that dest is new or empty; return it as a Path."""
    dest = Path(dest)
    if dest.exists() and any(dest.iterdir()):
        raise SourceError(f"{dest} is not empty. Extract into a new directory.")
    return dest


def _unreadable_archive_error(archive):
    return SourceError(
        f"{archive.name} isn't a readable .tar.gz or .zip archive. Download it again, "
        "or use the template's directory or owner/repo."
    )


def extract_archive(archive, dest):
    """Extract a .tar.gz, .tgz, or .zip into an empty directory."""
    archive, dest = Path(archive), _require_empty(dest)
    dest.mkdir(parents=True, exist_ok=True)
    name = archive.name.lower()
    if name.endswith((".tar.gz", ".tgz")):
        if not hasattr(tarfile, "data_filter"):
            raise SourceError(
                "Extracting .tar.gz archives safely needs Python 3.12 or newer. "
                "Use a newer Python, or pass the .zip version of the template."
            )
        try:
            with tarfile.open(archive, "r:gz") as tar:
                for member in tar.getmembers():
                    _check_member(member.name)
                try:
                    tar.extractall(dest, filter="data")
                except tarfile.FilterError as err:
                    raise SourceError(
                        f"The archive has an unsafe link or file ({err.tarinfo.name}). "  # pylint: disable=no-member
                        "Use the archive from the template's repository."
                    ) from err
        except tarfile.ReadError as err:
            raise _unreadable_archive_error(archive) from err
    elif name.endswith(".zip"):
        try:
            with zipfile.ZipFile(archive) as zf:
                for member in zf.namelist():
                    _check_member(member)
                zf.extractall(dest)
        except zipfile.BadZipFile as err:
            raise _unreadable_archive_error(archive) from err
    else:
        raise SourceError(f"{archive.name} isn't a supported archive. Use a .tar.gz, .tgz, or .zip file.")


def find_app_root(root):
    """Return the one directory under root that holds manifest.yml."""
    root = Path(root)
    found = [p.parent for p in root.rglob("manifest.yml") if "node_modules" not in p.parts]
    if not found:
        raise SourceError(f"There's no manifest.yml in {root}. Is this a Falcon Foundry app?")
    if len(found) > 1:
        listed = ", ".join(str(p.relative_to(root)) for p in sorted(found))
        raise SourceError(f"There's more than one manifest.yml in {root} ({listed}). Point to the app's directory.")
    return found[0]


_GITHUB_REF = re.compile(r"^(?P<repo>[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)(?:@(?P<ref>[^\s@]+))?$")


def parse_github_ref(source):
    """Return (owner/repo, ref) for a GitHub source, or None."""
    if Path(source).exists() or source.lower().endswith((".zip", ".tar.gz", ".tgz")):
        return None
    match = _GITHUB_REF.match(source)
    return (match["repo"], match["ref"]) if match else None


def resolve_source(source, dest, run=subprocess.run):
    """Turn a directory, archive, or owner/repo[@ref] into an app root directory."""
    dest = Path(dest)
    path = Path(source)
    if path.is_dir():
        _require_empty(dest)
        # copytree follows symlinks by default. A template-provided link to
        # a file outside the source would copy its contents into the app tree.
        root = path.resolve()
        for member in path.rglob("*"):
            if not member.is_symlink() or any(p in (".git", "node_modules") for p in member.parts):
                continue
            if not member.resolve().is_relative_to(root):
                raise SourceError(f"{member} is a symlink outside the template source.")
        copy_dest = dest / "src"
        shutil.copytree(path, copy_dest, ignore=shutil.ignore_patterns(".git", "node_modules"), dirs_exist_ok=True)
        return find_app_root(copy_dest)
    if path.is_file():
        extract_archive(path, dest)
        return find_app_root(dest)
    github = parse_github_ref(source)
    if github is None:
        raise SourceError(f"{source} isn't a directory, archive, or owner/repo[@ref].")
    repo, ref = github
    _require_empty(dest)
    dest.mkdir(parents=True, exist_ok=True)
    zipball = dest / "source.zip"
    endpoint = f"repos/{repo}/zipball/{ref}" if ref else f"repos/{repo}/zipball"
    try:
        with open(zipball, "wb") as out:
            run(["gh", "api", endpoint], stdout=out, check=True)
    except (OSError, subprocess.CalledProcessError) as err:
        raise SourceError(
            f"Couldn't download {source} from GitHub. If it's a local path, check that it exists. "
            "Otherwise check the repository and ref, and run `gh auth status`."
        ) from err
    extract_archive(zipball, dest / "src")
    return find_app_root(dest / "src")


BASE_URLS = {
    "us-1": "https://api.crowdstrike.com",
    "us-2": "https://api.us-2.crowdstrike.com",
    "eu-1": "https://api.eu-1.crowdstrike.com",
    "us-gov-1": "https://api.laggar.gcw.crowdstrike.com",
    "us-gov-2": "https://api.us-gov-2.crowdstrike.com",
}


def get_credentials(config_path=None):
    """Read API credentials from the active Foundry CLI profile."""
    config_path = config_path or Path.home() / ".config" / "foundry" / "configuration.yml"
    with open(config_path, encoding="utf-8") as f:
        cfg = yaml.safe_load(f) or {}
    profiles = cfg.get("profiles") or []
    active = cfg.get("active_profile", profiles[0].get("name") if profiles else None)
    profile = next((p for p in profiles if p.get("name") == active), None)
    if profile is None:
        raise SourceError(
            f"The Foundry CLI profile {active!r} isn't in {config_path}. "
            "Run `foundry profile list` and `foundry profile activate`."
        )
    creds = profile.get("credentials") or {}
    client_id, client_secret = creds.get("api_client_id"), creds.get("api_client_secret")
    if not client_id or not client_secret:
        raise SourceError(
            f"The Foundry CLI profile {active!r} has no API credentials. Run `foundry login` or recreate the profile."
        )
    region = profile.get("cloud_region") or "us-1"
    return {
        "client_id": client_id,
        "client_secret": client_secret,
        "base_url": BASE_URLS.get(region, BASE_URLS["us-1"]),
    }


def _api(falcon, override, parameters):
    response = falcon.command(override=override, parameters=parameters)
    if response["status_code"] != 200:
        errors = "; ".join(e.get("message", "") for e in response["body"].get("errors") or [])
        detail = f": {errors}" if errors else ""
        raise SourceError(
            f"The templates API returned {response['status_code']}{detail}. "
            "Check that the active Foundry CLI profile's API client can read app templates, "
            "or pass the new version as an archive, directory, or owner/repo instead."
        )
    return response["body"]


def find_template(falcon, name, page_size=100):
    """Return the app template whose name matches the app's manifest name, or None."""
    offset = 0
    seen = set()
    while True:
        body = _api(falcon, "GET,/foundry/queries/app-templates/v1", {"limit": page_size, "offset": offset})
        ids = body.get("resources") or []
        new_ids = [i for i in ids if i not in seen]
        if new_ids:
            seen.update(new_ids)
            records = _api(falcon, "GET,/foundry/entities/app-templates/v1", {"ids": new_ids})
            for record in records.get("resources") or []:
                if record.get("name") == name:
                    return record
        offset += len(ids)
        total = body.get("meta", {}).get("pagination", {}).get("total")
        # Stop on an empty page, a page of only repeats, or the reported total.
        if not new_ids or (total is not None and offset >= total):
            return None


def _load_yaml(path):
    with open(path, encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
    if not isinstance(data, dict):
        raise MergeError(f"{path} isn't a Falcon Foundry manifest (expected a mapping at the top level).")
    return data


def _default_falcon():
    try:
        from falconpy import APIHarnessV2  # pylint: disable=import-error,import-outside-toplevel
    except ImportError as err:
        raise SourceError(
            "FalconPy isn't installed. Run `pip install crowdstrike-falconpy`, or pass the new version "
            "as an archive, directory, or owner/repo instead."
        ) from err
    return APIHarnessV2(**get_credentials())


def _cmd_merge(args):
    deployed, template = _load_yaml(args.deployed), _load_yaml(args.template)
    merged = merge_ids(deployed, template)
    plan = build_plan(deployed, template)
    with open(args.template, "w", encoding="utf-8") as f:
        yaml.safe_dump(merged, f, sort_keys=False, allow_unicode=True)
    print(json.dumps(plan, indent=2) if args.json else format_plan(plan))
    return 2 if plan["needs_confirmation"] else 0


def _cmd_find_template(args, falcon_factory):
    name = _load_yaml(args.manifest).get("name")
    if not name:
        raise MergeError(
            f"{args.manifest} has no name, so its template can't be looked up. "
            "Pass the new version as an archive, directory, or owner/repo instead."
        )
    record = find_template((falcon_factory or _default_falcon)(), name)
    if record is None:
        print(f"No template named {name!r} on this cloud. Pass the new version as an archive, directory, "
              "or owner/repo[@ref] instead.", file=sys.stderr)
        return 1
    print(json.dumps({k: record.get(k) for k in ("id", "name", "version", "github_url")}))
    return 0


def main(argv=None, falcon_factory=None):
    """Run a subcommand; see the module docstring."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    resolve = sub.add_parser("resolve", help="turn a directory, archive, or owner/repo[@ref] into an app root")
    resolve.add_argument("source")
    resolve.add_argument("--dest", required=True, help="new, empty directory for downloads and extraction")
    find = sub.add_parser("find-template", help="find the template matching a manifest's name")
    find.add_argument("--manifest", required=True)
    merge = sub.add_parser("merge", help="copy a deployed app's IDs into a new manifest")
    merge.add_argument("--deployed", required=True, help="manifest.yml from `foundry apps sync`")
    merge.add_argument("--template", required=True, help="the new version's manifest.yml (overwritten)")
    merge.add_argument("--json", action="store_true", help="print the plan as JSON")
    try:
        args = parser.parse_args(argv)
    except SystemExit as err:
        # argparse has already printed usage. Exit 2 is reserved for "merged, needs confirmation".
        return 0 if err.code in (0, None) else 1
    try:
        if args.command == "resolve":
            print(resolve_source(args.source, Path(args.dest)))
            return 0
        if args.command == "find-template":
            return _cmd_find_template(args, falcon_factory)
        return _cmd_merge(args)
    except (MergeError, SourceError, OSError, yaml.YAMLError) as err:
        print(f"Error: {err}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
