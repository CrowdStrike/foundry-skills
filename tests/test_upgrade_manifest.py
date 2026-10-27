"""Tests for skills/app-upgrades/scripts/upgrade_manifest.py."""

import copy
import io
import json
import subprocess
import sys
import tarfile
import zipfile

import pytest
import yaml

from upgrade_manifest import (
    MergeError,
    SourceError,
    build_plan,
    extract_archive,
    find_app_root,
    find_template,
    format_plan,
    get_credentials,
    main,
    merge_ids,
    parse_github_ref,
    resolve_source,
)


def deployed_manifest():
    return {
        "app_id": "app111",
        "name": "Sample App",
        "description": "old description",
        "auth": {
            "scopes": ["devices:read"],
            "permissions": {"access:intel": {"id": "perm111", "name": "access:intel"}},
            "roles": [{"id": "role111", "name": "Analyst"}],
        },
        "functions": [
            {
                "id": "fn111",
                "name": "greet",
                "handlers": [
                    {"name": "hello", "workflow_integration": {"id": "wi111", "disruptive": False}},
                ],
            },
            {"id": "fn222", "name": "customer-added"},
        ],
        "collections": [{"id": "col111", "name": "events"}],
        "ui": {
            "pages": {"main": {"id": "page111", "name": "Main"}},
            "navigation": {"id": "nav111", "links": []},
        },
        "docs": {"id": "docs111", "path": "app_docs"},
    }


def template_manifest():
    return {
        "app_id": "",
        "name": "Sample App",
        "description": "new description",
        "auth": {
            "scopes": ["devices:read", "hosts:read"],
            "permissions": {"access:intel": {"id": "", "name": "access:intel"}},
            "roles": [{"id": "", "name": "Analyst"}],
        },
        "functions": [
            {
                "id": "",
                "name": "greet",
                "handlers": [
                    {"name": "hello", "workflow_integration": {"id": "", "disruptive": False}},
                    {"name": "bye", "workflow_integration": {"id": "", "disruptive": False}},
                ],
            },
            {"id": "", "name": "brand-new"},
        ],
        "collections": [{"name": "events"}],
        "ui": {"pages": {"main": {"name": "Main"}, "settings": {"id": "", "name": "Settings"}},
               "navigation": {"links": []}},
        "docs": {"id": "", "path": "app_docs"},
    }


def test_app_id_comes_from_deployed():
    merged = merge_ids(deployed_manifest(), template_manifest())
    assert merged["app_id"] == "app111"


def test_template_content_wins():
    merged = merge_ids(deployed_manifest(), template_manifest())
    assert merged["description"] == "new description"
    assert merged["auth"]["scopes"] == ["devices:read", "hosts:read"]


def test_deployed_app_name_is_kept():
    deployed = deployed_manifest()
    deployed["name"] = "Customer Renamed"
    template = template_manifest()
    merged = merge_ids(deployed, template)
    assert merged["name"] == "Customer Renamed"
    assert list(merged) == list(template)


def test_matched_artifacts_keep_ids_at_every_depth():
    merged = merge_ids(deployed_manifest(), template_manifest())
    greet = merged["functions"][0]
    assert greet["id"] == "fn111"
    assert greet["handlers"][0]["workflow_integration"]["id"] == "wi111"
    assert merged["auth"]["permissions"]["access:intel"]["id"] == "perm111"
    assert merged["auth"]["roles"][0]["id"] == "role111"
    assert merged["docs"]["id"] == "docs111"


def test_ids_restored_when_template_dropped_the_key():
    merged = merge_ids(deployed_manifest(), template_manifest())
    assert merged["collections"][0]["id"] == "col111"
    assert merged["ui"]["pages"]["main"]["id"] == "page111"
    assert merged["ui"]["navigation"]["id"] == "nav111"
    assert list(merged["collections"][0]) == ["id", "name"]


def test_new_artifacts_have_no_id_key():
    merged = merge_ids(deployed_manifest(), template_manifest())
    assert "id" not in merged["functions"][1]
    assert "id" not in merged["functions"][0]["handlers"][1]["workflow_integration"]
    assert "id" not in merged["ui"]["pages"]["settings"]


def test_deployed_only_artifacts_are_not_carried_forward():
    merged = merge_ids(deployed_manifest(), template_manifest())
    assert [f["name"] for f in merged["functions"]] == ["greet", "brand-new"]


def test_inputs_are_not_mutated():
    deployed, template = deployed_manifest(), template_manifest()
    before = copy.deepcopy((deployed, template))
    merge_ids(deployed, template)
    assert (deployed, template) == before


def test_identical_versions_round_trip():
    deployed = deployed_manifest()
    assert merge_ids(deployed, copy.deepcopy(deployed)) == deployed


def test_empty_deployed_id_is_dropped_not_copied():
    deployed = deployed_manifest()
    deployed["docs"]["id"] = ""
    merged = merge_ids(deployed, template_manifest())
    assert "id" not in merged["docs"]


def test_missing_deployed_app_id_is_an_error():
    deployed = deployed_manifest()
    deployed["app_id"] = ""
    with pytest.raises(MergeError, match="no app_id"):
        merge_ids(deployed, template_manifest())


def test_duplicate_names_are_an_error():
    template = template_manifest()
    template["functions"].append({"name": "greet"})
    with pytest.raises(MergeError, match="functions.*greet"):
        merge_ids(deployed_manifest(), template)


def test_unnamed_list_items_with_deployed_ids_are_an_error():
    deployed, template = deployed_manifest(), template_manifest()
    deployed["widgets"] = [{"id": "w111", "size": 1}]
    template["widgets"] = [{"size": 2}]
    with pytest.raises(MergeError, match="widgets"):
        merge_ids(deployed, template)


def test_unnamed_list_items_without_ids_pass_through():
    deployed, template = deployed_manifest(), template_manifest()
    deployed["ignored_rules"] = [{"pattern": "a"}]
    template["ignored_rules"] = [{"pattern": "b", "id": ""}]
    merged = merge_ids(deployed, template)
    assert merged["ignored_rules"] == [{"pattern": "b"}]


def test_plan_groups_artifacts():
    plan = build_plan(deployed_manifest(), template_manifest())
    assert plan["kept"]["functions"] == ["greet"]
    assert plan["added"]["functions"] == ["brand-new"]
    assert plan["removed"]["functions"] == ["customer-added"]
    assert plan["added"]["ui.pages"] == ["settings"]
    assert plan["kept"]["collections"] == ["events"]


def test_add_and_remove_in_one_section_is_a_possible_rename():
    plan = build_plan(deployed_manifest(), template_manifest())
    assert plan["possible_renames"] == ["functions"]
    assert plan["needs_confirmation"] is True


def test_removed_collection_is_data_loss():
    template = template_manifest()
    template["collections"] = []
    plan = build_plan(deployed_manifest(), template)
    assert plan["data_loss"] == ["events"]
    assert plan["needs_confirmation"] is True


def test_only_kept_and_added_needs_no_confirmation():
    deployed = deployed_manifest()
    deployed["functions"].pop()
    plan = build_plan(deployed, template_manifest())
    assert plan["removed"] == {}
    assert plan["needs_confirmation"] is False


def test_removing_roles_and_permission_definitions_requires_confirmation():
    deployed = deployed_manifest()
    template = copy.deepcopy(deployed)
    template["auth"]["roles"] = []
    template["auth"]["permissions"] = {}
    plan = build_plan(deployed, template)
    assert plan["removed"]["auth.roles"] == ["Analyst"]
    assert plan["removed"]["auth.permissions"] == ["access:intel"]
    assert plan["needs_confirmation"] is True


def test_removing_page_and_navigation_gates_requires_confirmation():
    deployed = deployed_manifest()
    deployed["ui"]["pages"]["main"]["permissions"] = ["access:intel"]
    deployed["ui"]["navigation"]["links"] = [{"name": "Main", "permissions": ["access:intel"]}]
    template = copy.deepcopy(deployed)
    template["ui"]["pages"]["main"]["permissions"] = []
    template["ui"]["navigation"]["links"][0].pop("permissions")
    plan = build_plan(deployed, template)
    assert plan["access_changes"] == {
        "ui.pages.main": {"removed": ["access:intel"], "added": []},
        "ui.navigation.links.Main": {"removed": ["access:intel"], "added": []},
    }
    assert plan["needs_confirmation"] is True
    assert "WARNING: access change in ui.pages.main: removed access:intel" in format_plan(plan)


def test_granting_new_permission_to_existing_role_requires_confirmation():
    deployed = deployed_manifest()
    deployed["auth"]["roles"][0]["permissions"] = ["access:intel"]
    template = copy.deepcopy(deployed)
    template["auth"]["roles"][0]["permissions"].append("app:write")
    plan = build_plan(deployed, template)
    assert plan["needs_confirmation"] is True
    assert "app:write" in format_plan(plan)


def test_format_plan_mentions_data_loss_and_renames():
    template = template_manifest()
    template["collections"] = []
    text = format_plan(build_plan(deployed_manifest(), template))
    assert "Removed" in text and "customer-added" in text
    assert "deletes its stored data" in text
    assert "possible rename" in text


def make_tar(path, files):
    with tarfile.open(path, "w:gz") as tar:
        for name, text in files.items():
            data = text.encode()
            info = tarfile.TarInfo(name)
            info.size = len(data)
            tar.addfile(info, io.BytesIO(data))


def make_zip(path, files):
    with zipfile.ZipFile(path, "w") as zf:
        for name, text in files.items():
            zf.writestr(name, text)


@pytest.mark.parametrize("maker,suffix", [(make_tar, ".tar.gz"), (make_zip, ".zip")])
def test_extract_finds_root_inside_github_wrapper(tmp_path, maker, suffix):
    archive = tmp_path / f"src{suffix}"
    maker(archive, {"repo-abc123/manifest.yml": "name: x\n", "repo-abc123/README.md": "hi"})
    dest = tmp_path / "out"
    extract_archive(archive, dest)
    assert find_app_root(dest) == dest / "repo-abc123"


@pytest.mark.parametrize("maker,suffix", [(make_tar, ".tgz"), (make_zip, ".zip")])
def test_extract_rejects_parent_traversal(tmp_path, maker, suffix):
    archive = tmp_path / f"evil{suffix}"
    maker(archive, {"../escape.txt": "x", "manifest.yml": "name: x\n"})
    with pytest.raises(SourceError, match="unsafe path"):
        extract_archive(archive, tmp_path / "out")
    assert not (tmp_path / "escape.txt").exists()


def test_extract_rejects_absolute_paths(tmp_path):
    archive = tmp_path / "abs.tar.gz"
    make_tar(archive, {"/etc/x": "x"})
    with pytest.raises(SourceError, match="unsafe path"):
        extract_archive(archive, tmp_path / "out")


def test_extract_requires_empty_destination(tmp_path):
    archive = tmp_path / "a.zip"
    make_zip(archive, {"manifest.yml": "name: x\n"})
    dest = tmp_path / "out"
    dest.mkdir()
    (dest / "leftover").write_text("x")
    with pytest.raises(SourceError, match="not empty"):
        extract_archive(archive, dest)


def test_unknown_archive_type(tmp_path):
    archive = tmp_path / "a.rar"
    archive.write_text("x")
    with pytest.raises(SourceError, match=r"\.tar\.gz, \.tgz, or \.zip"):
        extract_archive(archive, tmp_path / "out")


def test_extract_tar_without_data_filter_is_a_source_error(tmp_path, monkeypatch):
    archive = tmp_path / "a.tar.gz"
    make_tar(archive, {"manifest.yml": "name: x\n"})
    monkeypatch.delattr(tarfile, "data_filter")
    with pytest.raises(SourceError, match="Python 3.12"):
        extract_archive(archive, tmp_path / "out")


def test_extract_corrupt_tar_is_a_source_error(tmp_path):
    archive = tmp_path / "bad.tar.gz"
    archive.write_bytes(b"not a tarball")
    with pytest.raises(SourceError, match="isn't a readable"):
        extract_archive(archive, tmp_path / "out")


def test_extract_corrupt_zip_is_a_source_error(tmp_path):
    archive = tmp_path / "bad.zip"
    archive.write_bytes(b"not a zipfile")
    with pytest.raises(SourceError, match="isn't a readable"):
        extract_archive(archive, tmp_path / "out")


def test_find_app_root_errors(tmp_path):
    with pytest.raises(SourceError, match="no manifest.yml"):
        find_app_root(tmp_path)
    for sub in ("a", "b"):
        (tmp_path / sub).mkdir()
        (tmp_path / sub / "manifest.yml").write_text("name: x\n")
    with pytest.raises(SourceError, match="more than one manifest.yml"):
        find_app_root(tmp_path)


def test_find_app_root_ignores_node_modules(tmp_path):
    (tmp_path / "manifest.yml").write_text("name: x\n")
    nested = tmp_path / "ui" / "node_modules" / "pkg"
    nested.mkdir(parents=True)
    (nested / "manifest.yml").write_text("other\n")
    assert find_app_root(tmp_path) == tmp_path


def test_extract_reports_link_escapes_as_source_errors(tmp_path):
    archive = tmp_path / "link.tar.gz"
    with tarfile.open(archive, "w:gz") as tar:
        data = b"name: x\n"
        info = tarfile.TarInfo("manifest.yml")
        info.size = len(data)
        tar.addfile(info, io.BytesIO(data))
        link = tarfile.TarInfo("escape_link")
        link.type = tarfile.SYMTYPE
        link.linkname = "../../outside"
        tar.addfile(link)
    with pytest.raises(SourceError, match="unsafe link"):
        extract_archive(archive, tmp_path / "out")
    assert not (tmp_path / "out" / "../../outside").resolve().exists()


def test_parse_github_ref():
    assert parse_github_ref("CrowdStrike/foundry-sample-mitre") == ("CrowdStrike/foundry-sample-mitre", None)
    assert parse_github_ref("CrowdStrike/foundry-sample-mitre@v1.2.0") == ("CrowdStrike/foundry-sample-mitre", "v1.2.0")
    assert parse_github_ref("./some/dir") is None
    assert parse_github_ref("app.zip") is None


def test_resolve_directory_copies_instead_of_using_it_in_place(tmp_path):
    src = tmp_path / "app"
    src.mkdir()
    (src / "manifest.yml").write_text("name: x\n")
    dest = tmp_path / "out"
    root = resolve_source(str(src), dest)
    assert root == dest / "src"
    assert root != src
    assert (root / "manifest.yml").read_text() == "name: x\n"


def test_resolve_directory_ignores_git_and_node_modules(tmp_path):
    src = tmp_path / "app"
    (src / ".git").mkdir(parents=True)
    (src / ".git" / "config").write_text("x")
    (src / "node_modules" / "pkg").mkdir(parents=True)
    (src / "node_modules" / "pkg" / "index.js").write_text("x")
    (src / "manifest.yml").write_text("name: x\n")
    root = resolve_source(str(src), tmp_path / "out")
    assert not (root / ".git").exists()
    assert not (root / "node_modules").exists()


def test_resolve_directory_requires_empty_dest(tmp_path):
    src = tmp_path / "app"
    src.mkdir()
    (src / "manifest.yml").write_text("name: x\n")
    dest = tmp_path / "out"
    (dest / "src").mkdir(parents=True)
    (dest / "src" / "leftover").write_text("x")
    with pytest.raises(SourceError, match="not empty"):
        resolve_source(str(src), dest)


def test_resolve_directory_rejects_symlinks_outside_source(tmp_path):
    src = tmp_path / "app"
    src.mkdir()
    (src / "manifest.yml").write_text("name: x\n")
    private = tmp_path / "private.txt"
    private.write_text("outside source")
    (src / "copied.txt").symlink_to(private)
    dest = tmp_path / "out"
    with pytest.raises(SourceError, match="symlink"):
        resolve_source(str(src), dest)
    assert not (dest / "src" / "copied.txt").exists()


def test_resolve_directory_allows_symlinks_within_source(tmp_path):
    src = tmp_path / "app"
    src.mkdir()
    (src / "manifest.yml").write_text("name: x\n")
    (src / "readme.md").write_text("inside source")
    (src / "linked.md").symlink_to("readme.md")
    root = resolve_source(str(src), tmp_path / "out")
    assert (root / "linked.md").read_text() == "inside source"


def test_resolve_github_rejects_nonempty_destination_before_writing(tmp_path):
    dest = tmp_path / "out"
    dest.mkdir()
    original = dest / "source.zip"
    original.write_bytes(b"leave me alone")
    calls = []

    def fake_run(_cmd, **_kwargs):
        calls.append(True)

    with pytest.raises(SourceError, match="not empty"):
        resolve_source("CrowdStrike/example@main", dest, run=fake_run)
    assert not calls
    assert original.read_bytes() == b"leave me alone"


def test_resolve_archive(tmp_path):
    archive = tmp_path / "t.zip"
    make_zip(archive, {"w/manifest.yml": "name: x\n"})
    assert resolve_source(str(archive), tmp_path / "out") == tmp_path / "out" / "w"


def test_resolve_github_downloads_zipball(tmp_path):
    calls = []

    def fake_run(cmd, stdout, check):
        calls.append(cmd)
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w") as zf:
            zf.writestr("CrowdStrike-foundry-sample-mitre-abc/manifest.yml", "name: x\n")
        stdout.write(buf.getvalue())

    root = resolve_source("CrowdStrike/foundry-sample-mitre@main", tmp_path / "out", run=fake_run)
    assert calls == [["gh", "api", "repos/CrowdStrike/foundry-sample-mitre/zipball/main"]]
    assert root.name == "CrowdStrike-foundry-sample-mitre-abc"
    assert root.parent == tmp_path / "out" / "src"


def test_resolve_github_failure_is_a_source_error(tmp_path):
    def failing_run(cmd, stdout, check):
        raise subprocess.CalledProcessError(1, cmd)

    with pytest.raises(SourceError, match="gh auth status"):
        resolve_source("CrowdStrike/nope", tmp_path / "out", run=failing_run)


def test_resolve_missing_path(tmp_path):
    with pytest.raises(SourceError, match="isn't a directory, archive, or owner/repo"):
        resolve_source(str(tmp_path / "missing.zip"), tmp_path / "out")


def test_resolve_missing_relative_path_mentions_local_path(tmp_path):
    def failing_run(cmd, stdout, check):
        raise subprocess.CalledProcessError(1, cmd)

    with pytest.raises(SourceError, match="If it's a local path, check that it exists"):
        resolve_source("src/app", tmp_path / "out", run=failing_run)


class FakeFalcon:
    def __init__(self, templates, status=200):
        self.templates = templates
        self.status = status
        self.calls = []

    def command(self, override, parameters):
        self.calls.append((override, parameters))
        if self.status != 200:
            return {"status_code": self.status, "body": {"errors": [{"message": "denied"}]}}
        if override.startswith("GET,/foundry/queries/"):
            start = parameters["offset"]
            ids = [t["id"] for t in self.templates][start:start + parameters["limit"]]
            return {"status_code": 200, "body": {"resources": ids,
                    "meta": {"pagination": {"total": len(self.templates)}}}}
        wanted = set(parameters["ids"])
        return {"status_code": 200, "body": {"resources": [t for t in self.templates if t["id"] in wanted]}}


def test_find_template_pages_until_match():
    templates = [{"id": f"t{i}", "name": f"Other {i}"} for i in range(5)]
    templates.append({"id": "t5", "name": "Category Blocking", "github_url": "https://github.com/o/r"})
    falcon = FakeFalcon(templates)
    found = find_template(falcon, "Category Blocking", page_size=2)
    assert found["github_url"] == "https://github.com/o/r"
    queries = [c for c in falcon.calls if "queries" in c[0]]
    assert [q[1]["offset"] for q in queries] == [0, 2, 4]


def test_find_template_no_match():
    assert find_template(FakeFalcon([{"id": "t1", "name": "Other"}]), "Category Blocking") is None


def test_find_template_api_error():
    with pytest.raises(SourceError, match="403.*denied"):
        find_template(FakeFalcon([], status=403), "x")


def test_get_credentials_reads_active_profile(tmp_path):
    config = tmp_path / "configuration.yml"
    config.write_text(
        "active_profile: two\n"
        "profiles:\n"
        "  - name: one\n    cloud_region: us-1\n    credentials: {api_client_id: a, api_client_secret: b}\n"
        "  - name: two\n    cloud_region: eu-1\n    credentials: {api_client_id: c, api_client_secret: d}\n"
    )
    assert get_credentials(config) == {
        "client_id": "c", "client_secret": "d", "base_url": "https://api.eu-1.crowdstrike.com",
    }


def test_get_credentials_unknown_profile_is_a_source_error(tmp_path):
    config = tmp_path / "configuration.yml"
    config.write_text(
        "active_profile: missing\n"
        "profiles:\n"
        "  - name: one\n    credentials: {api_client_id: a, api_client_secret: b}\n"
    )
    with pytest.raises(SourceError, match="isn't in"):
        get_credentials(config)


def test_get_credentials_missing_credentials_is_a_source_error(tmp_path):
    config = tmp_path / "configuration.yml"
    config.write_text("active_profile: one\nprofiles:\n  - name: one\n    cloud_region: us-1\n")
    with pytest.raises(SourceError, match="no API credentials"):
        get_credentials(config)


class NoTotalFalcon(FakeFalcon):
    def command(self, override, parameters):
        response = super().command(override, parameters)
        response["body"].pop("meta", None)
        return response


def test_find_template_pages_without_a_total():
    templates = [{"id": f"t{i}", "name": f"Other {i}"} for i in range(5)]
    templates.append({"id": "t5", "name": "Category Blocking"})
    falcon = NoTotalFalcon(templates)
    assert find_template(falcon, "Category Blocking", page_size=2) == templates[5]
    queries = [c for c in falcon.calls if "queries" in c[0]]
    assert [q[1]["offset"] for q in queries] == [0, 2, 4]


class RepeatingFalcon:
    def __init__(self):
        self.queries = 0

    def command(self, override, parameters):
        if override.startswith("GET,/foundry/queries/"):
            self.queries += 1
            if self.queries > 10:
                raise AssertionError("find_template kept paging a repeating API")
            return {"status_code": 200, "body": {"resources": ["t1", "t2"]}}
        return {"status_code": 200, "body": {"resources": [{"id": i, "name": "Other"} for i in parameters["ids"]]}}


def test_find_template_stops_when_pages_repeat():
    falcon = RepeatingFalcon()
    assert find_template(falcon, "Category Blocking", page_size=2) is None
    assert falcon.queries == 2


class EmptyErrorFalcon:
    def command(self, override, parameters):
        return {"status_code": 500, "body": {"errors": []}}


def test_api_error_without_messages():
    with pytest.raises(SourceError, match="returned 500. Check"):
        find_template(EmptyErrorFalcon(), "x")


def write_yaml(path, data):
    path.write_text(yaml.safe_dump(data, sort_keys=False))
    return path


def test_main_merge_writes_and_flags_confirmation(tmp_path, capsys):
    deployed = write_yaml(tmp_path / "deployed.yml", deployed_manifest())
    template = write_yaml(tmp_path / "manifest.yml", template_manifest())
    assert main(["merge", "--deployed", str(deployed), "--template", str(template)]) == 2
    merged = yaml.safe_load(template.read_text())
    assert merged["app_id"] == "app111"
    assert "Removed functions: customer-added" in capsys.readouterr().out


def test_main_merge_flags_removed_access_gate(tmp_path, capsys):
    deployed_data = deployed_manifest()
    deployed_data["ui"]["pages"]["main"]["permissions"] = ["access:intel"]
    template_data = copy.deepcopy(deployed_data)
    template_data["ui"]["pages"]["main"]["permissions"] = []
    deployed = write_yaml(tmp_path / "deployed.yml", deployed_data)
    template = write_yaml(tmp_path / "manifest.yml", template_data)
    assert main(["merge", "--deployed", str(deployed), "--template", str(template)]) == 2
    assert "WARNING: access change in ui.pages.main: removed access:intel" in capsys.readouterr().out


def test_main_merge_json_and_clean_exit(tmp_path, capsys):
    d = deployed_manifest()
    d["functions"].pop()
    deployed = write_yaml(tmp_path / "deployed.yml", d)
    template = write_yaml(tmp_path / "manifest.yml", template_manifest())
    assert main(["merge", "--deployed", str(deployed), "--template", str(template), "--json"]) == 0
    assert json.loads(capsys.readouterr().out)["needs_confirmation"] is False


def test_main_merge_preserves_key_order(tmp_path):
    deployed = write_yaml(tmp_path / "deployed.yml", deployed_manifest())
    template = write_yaml(tmp_path / "manifest.yml", template_manifest())
    main(["merge", "--deployed", str(deployed), "--template", str(template)])
    assert list(yaml.safe_load(template.read_text())) == list(template_manifest())


def test_main_reports_errors_on_stderr(tmp_path, capsys):
    d = deployed_manifest()
    d["app_id"] = ""
    deployed = write_yaml(tmp_path / "deployed.yml", d)
    template = write_yaml(tmp_path / "manifest.yml", template_manifest())
    assert main(["merge", "--deployed", str(deployed), "--template", str(template)]) == 1
    assert "no app_id" in capsys.readouterr().err


def test_main_resolve_prints_root(tmp_path, capsys):
    src = tmp_path / "app"
    src.mkdir()
    (src / "manifest.yml").write_text("name: x\n")
    dest = tmp_path / "out"
    assert main(["resolve", str(src), "--dest", str(dest)]) == 0
    assert capsys.readouterr().out.strip() == str(dest / "src")


def test_resolve_then_merge_does_not_mutate_original_directory(tmp_path, capsys):
    src = tmp_path / "app"
    src.mkdir()
    write_yaml(src / "manifest.yml", template_manifest())
    original = (src / "manifest.yml").read_text()
    deployed = write_yaml(tmp_path / "deployed.yml", deployed_manifest())
    dest = tmp_path / "out"
    assert main(["resolve", str(src), "--dest", str(dest)]) == 0
    root = capsys.readouterr().out.strip()
    assert main(["merge", "--deployed", str(deployed), "--template", f"{root}/manifest.yml"]) in (0, 2)
    assert (src / "manifest.yml").read_text() == original


def test_find_template_requires_name(tmp_path, capsys):
    manifest = write_yaml(tmp_path / "manifest.yml", {"description": "no name"})
    assert main(["find-template", "--manifest", str(manifest)]) == 1
    assert "has no name" in capsys.readouterr().err


def test_main_find_template(tmp_path, capsys):
    manifest = write_yaml(tmp_path / "manifest.yml", {"name": "Category Blocking"})
    falcon = FakeFalcon([{"id": "t1", "name": "Category Blocking", "version": "v1.0.0",
                          "github_url": "https://github.com/o/r", "artifacts": []}])
    assert main(["find-template", "--manifest", str(manifest)], falcon_factory=lambda: falcon) == 0
    out = json.loads(capsys.readouterr().out)
    assert out == {"id": "t1", "name": "Category Blocking", "version": "v1.0.0", "github_url": "https://github.com/o/r"}


def test_main_find_template_none(tmp_path, capsys):
    manifest = write_yaml(tmp_path / "manifest.yml", {"name": "Mine"})
    assert main(["find-template", "--manifest", str(manifest)], falcon_factory=lambda: FakeFalcon([])) == 1
    assert "No template named 'Mine'" in capsys.readouterr().err


def test_main_find_template_api_error_is_a_clean_message(tmp_path, capsys):
    manifest = write_yaml(tmp_path / "manifest.yml", {"name": "Mine"})
    assert main(["find-template", "--manifest", str(manifest)], falcon_factory=lambda: FakeFalcon([], status=403)) == 1
    err = capsys.readouterr().err
    assert err.startswith("Error: The templates API returned 403: denied.")
    assert "Traceback" not in err


def test_main_find_template_missing_credentials_is_a_clean_message(tmp_path, monkeypatch, capsys):
    def no_profile():
        raise SourceError("The Foundry CLI profile 'x' has no API credentials.")

    monkeypatch.setattr("upgrade_manifest.get_credentials", no_profile)
    manifest = write_yaml(tmp_path / "manifest.yml", {"name": "Mine"})
    assert main(["find-template", "--manifest", str(manifest)]) == 1
    assert capsys.readouterr().err == "Error: The Foundry CLI profile 'x' has no API credentials.\n"


def test_main_usage_error_exits_1_and_help_exits_0(tmp_path, capsys):
    assert main(["merge", "--deployed", "x"]) == 1
    assert "--template" in capsys.readouterr().err
    assert main(["--help"]) == 0


def test_main_missing_falconpy_is_a_clean_message(tmp_path, monkeypatch, capsys):
    monkeypatch.setitem(sys.modules, "falconpy", None)
    monkeypatch.setattr("upgrade_manifest.get_credentials", lambda: {"client_id": "a", "client_secret": "b", "base_url": "u"})
    manifest = write_yaml(tmp_path / "manifest.yml", {"name": "Mine"})
    assert main(["find-template", "--manifest", str(manifest)]) == 1
    err = capsys.readouterr().err
    assert "FalconPy isn't installed" in err
    assert "Traceback" not in err


def test_main_non_mapping_manifest_is_left_unchanged(tmp_path, capsys):
    deployed = write_yaml(tmp_path / "deployed.yml", deployed_manifest())
    template = tmp_path / "manifest.yml"
    template.write_text("- a\n- b\n")
    assert main(["merge", "--deployed", str(deployed), "--template", str(template)]) == 1
    assert "isn't a Falcon Foundry manifest" in capsys.readouterr().err
    assert template.read_text() == "- a\n- b\n"


