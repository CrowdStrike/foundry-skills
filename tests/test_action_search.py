"""Tests for scripts/action_search.py.

All CrowdStrike API calls are mocked; no credentials are needed. The
credential tests drive get_credentials() through a patched Path.home() so the
real path-join and YAML-parsing logic runs on whatever OS hosts the test
(exercised on both Linux and Windows in CI).
"""

import io
import sys
from contextlib import redirect_stdout

import pytest

import action_search


# ── get_credentials ──────────────────────────────────────────────────────────


def _write_config(home, *, active="Dev", region="us-2", profiles=None):
    """Write a Foundry CLI configuration.yml under a fake home directory and
    return the home Path. Mirrors ~/.config/foundry/configuration.yml."""
    cfg_dir = home / ".config" / "foundry"
    cfg_dir.mkdir(parents=True, exist_ok=True)
    if profiles is None:
        profiles = [
            {
                "name": active,
                "cloud_region": region,
                "credentials": {
                    "api_client_id": "id-abc",
                    "api_client_secret": "secret-xyz",
                },
            }
        ]
    lines = [f"active_profile: {active}", "profiles:"] if active else ["profiles:"]
    for p in profiles:
        lines.append(f"  - name: {p['name']}")
        if "cloud_region" in p:
            lines.append(f"    cloud_region: {p['cloud_region']}")
        lines.append("    credentials:")
        lines.append(f"      api_client_id: {p['credentials']['api_client_id']}")
        lines.append(
            f"      api_client_secret: {p['credentials']['api_client_secret']}"
        )
    (cfg_dir / "configuration.yml").write_text("\n".join(lines), encoding="utf-8")
    return home


def test_reads_active_profile_and_maps_region(tmp_path, monkeypatch):
    _write_config(tmp_path, active="Dev", region="us-2")
    monkeypatch.setattr(action_search.Path, "home", lambda: tmp_path)

    creds = action_search.get_credentials()

    assert creds["client_id"] == "id-abc"
    assert creds["client_secret"] == "secret-xyz"
    assert creds["base_url"] == "https://api.us-2.crowdstrike.com"


def test_selects_the_active_profile_among_several(tmp_path, monkeypatch):
    profiles = [
        {
            "name": "Prod",
            "cloud_region": "eu-1",
            "credentials": {"api_client_id": "prod-id", "api_client_secret": "prod-s"},
        },
        {
            "name": "Dev",
            "cloud_region": "us-1",
            "credentials": {"api_client_id": "dev-id", "api_client_secret": "dev-s"},
        },
    ]
    _write_config(tmp_path, active="Dev", profiles=profiles)
    monkeypatch.setattr(action_search.Path, "home", lambda: tmp_path)

    creds = action_search.get_credentials()

    assert creds["client_id"] == "dev-id"
    assert creds["base_url"] == "https://api.crowdstrike.com"  # us-1


def test_falls_back_to_first_profile_without_active(tmp_path, monkeypatch):
    profiles = [
        {
            "name": "OnlyOne",
            "cloud_region": "us-1",
            "credentials": {"api_client_id": "one-id", "api_client_secret": "one-s"},
        }
    ]
    _write_config(tmp_path, active="", profiles=profiles)
    monkeypatch.setattr(action_search.Path, "home", lambda: tmp_path)

    creds = action_search.get_credentials()

    assert creds["client_id"] == "one-id"


def test_unknown_region_defaults_to_us1(tmp_path, monkeypatch):
    _write_config(tmp_path, active="Dev", region="mars-1")
    monkeypatch.setattr(action_search.Path, "home", lambda: tmp_path)

    creds = action_search.get_credentials()

    assert creds["base_url"] == "https://api.crowdstrike.com"


def test_missing_config_raises(tmp_path, monkeypatch):
    monkeypatch.setattr(action_search.Path, "home", lambda: tmp_path)
    with pytest.raises(FileNotFoundError):
        action_search.get_credentials()


# ── search_actions ─────────────────────────────────────────────────────────


def _patch_client(monkeypatch, resources, status_code=200):
    """Patch get_credentials + Workflows so search_actions runs offline."""
    monkeypatch.setattr(
        action_search,
        "get_credentials",
        lambda: {"client_id": "x", "client_secret": "y", "base_url": "https://z"},
    )
    client = _FakeWorkflows(resources, status_code)
    monkeypatch.setattr(action_search, "Workflows", lambda **_: client)
    return client


class _FakeWorkflows:
    def __init__(self, resources, status_code):
        self._resources = resources
        self._status_code = status_code

    def search_activities(self, **_kwargs):
        return {
            "status_code": self._status_code,
            "body": {"resources": self._resources},
        }


def test_search_prints_id_and_version_constraint(monkeypatch):
    _patch_client(
        monkeypatch,
        [{"id": "abc", "name": "Send Email", "semantic_version": "2.1.0"}],
    )
    out = io.StringIO()
    with redirect_stdout(out):
        action_search.search_actions("email")
    text = out.getvalue()
    assert "abc: Send Email" in text
    assert "version_constraint: ~2" in text


def test_search_version_constraint_defaults_to_zero(monkeypatch):
    _patch_client(monkeypatch, [{"id": "n", "name": "No Version"}])
    out = io.StringIO()
    with redirect_stdout(out):
        action_search.search_actions("no")
    assert "version_constraint: ~0" in out.getvalue()


def test_search_details_lists_properties(monkeypatch):
    _patch_client(
        monkeypatch,
        [
            {
                "id": "d",
                "name": "Detailed",
                "semantic_version": "1.0.0",
                "properties": {"to": {"type": "string", "required": True}},
            }
        ],
    )
    out = io.StringIO()
    with redirect_stdout(out):
        action_search.search_actions("detailed", details=True)
    text = out.getvalue()
    assert "to [string] (required)" in text
    assert "id: d" in text


def test_search_no_results_exits_zero(monkeypatch):
    _patch_client(monkeypatch, [])
    with pytest.raises(SystemExit) as exc:
        action_search.search_actions("nothing")
    assert exc.value.code == 0


def test_search_api_error_exits_one(monkeypatch):
    """A non-200 status code exits 1."""
    _patch_client(monkeypatch, [], status_code=500)
    with pytest.raises(SystemExit) as exc:
        action_search.search_actions("boom")
    assert exc.value.code == 1


# ── main / argparse ──────────────────────────────────────────────────────────


def test_main_passes_query_and_details(monkeypatch):
    """main() forwards the parsed query and --details flag to search_actions."""
    captured = {}
    monkeypatch.setattr(
        action_search,
        "search_actions",
        lambda query, details=False: captured.update(query=query, details=details),
    )
    monkeypatch.setattr(sys, "argv", ["action_search.py", "send email", "--details"])
    action_search.main()
    assert captured == {"query": "send email", "details": True}

