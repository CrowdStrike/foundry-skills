"""Tests for deploy_and_release.py: one call that deploys, waits, and releases.

The foundry CLI is replaced by a fake runner that replays recorded output, so
no command reaches a tenant. The table and messages match CLI 2.1.2 output.
"""

import pytest

import deploy_and_release as dr

DEPLOY_OUT = """Packaging app...
\t◦ manifest.yml
\t◦ ui/extensions/okta-users/src/app.jsx
\t◦ ui/extensions/okta-users/src/dist/assets/index-CGUYHdVn.js
\t◦ ui/extensions/okta-users/src/dist/index.html
\t◦ workflows/list_okta_users.yml

✅  Deployment v1.0.0-pre-release in progress - see https://falcon.us-2.crowdstrike.com/foundry/app-manager/7f7c?activeTab=deployments for more details
"""


def table(rows):
    lines = [
        "Deployments for App: okta-users (7f7c)",
        "┌──────────────────────────────────┬────────────────────┬───────────────┐",
        "│          DEPLOYMENT ID           │      VERSION       │     STATE     │",
        "├──────────────────────────────────┼────────────────────┼───────────────┤",
    ]
    lines += [f"│ {i} │ {v} │ {s} │" for i, v, s in rows]
    lines.append("└──────────────────────────────────┴────────────────────┴───────────────┘")
    return "\n".join(lines)


class FakeCLI:
    """Replays deploy output, then one list-deployments table per poll."""

    def __init__(self, polls, deploy=(0, DEPLOY_OUT), release=(0, "✅  Release in progress")):
        self.polls = list(polls)
        self.deploy = deploy
        self.release = release
        self.calls = []

    def __call__(self, cmd):
        self.calls.append(cmd)
        sub = cmd[2]
        if sub == "deploy":
            return self.deploy
        if sub == "list-deployments":
            return 0, self.polls.pop(0) if len(self.polls) > 1 else self.polls[0]
        if sub == "release":
            return self.release
        raise AssertionError(cmd)


@pytest.fixture(name="app_root")
def fixture_app_root(tmp_path, monkeypatch):
    (tmp_path / "manifest.yml").write_text("name: okta-users\n")
    monkeypatch.chdir(tmp_path)
    monkeypatch.setattr(dr.time, "sleep", lambda _s: None)
    return tmp_path


def test_parse_version():
    assert dr.parse_version(DEPLOY_OUT) == "v1.0.0-pre-release"
    assert dr.parse_version("no version here") is None


def test_find_deployment_matches_version_not_first_row():
    out = table([("aaa", "v1.0.1-pre-release", "🟢 Successful"),
                 ("bbb", "v1.0.0-pre-release", "In progress")])
    assert dr.find_deployment(out, "v1.0.0-pre-release") == ("bbb", "In progress")
    assert dr.find_deployment(out, "v9.9.9") is None


def test_summarize_keeps_dist_lines_and_counts_the_rest():
    text = dr.summarize_deploy(DEPLOY_OUT)
    assert "dist/assets/index-CGUYHdVn.js" in text
    assert "src/app.jsx" not in text
    assert "3 other packaged files" in text
    assert "Deployment v1.0.0-pre-release in progress" in text


def test_waits_then_releases_the_deployed_version(app_root, capsys):
    cli = FakeCLI([table([("bbb", "v1.0.0-pre-release", "In progress")]),
                   table([("bbb", "v1.0.0-pre-release", "🟢 Successful")])])
    assert dr.main(["--change-log", "Initial app"], runner=cli) == 0
    release = cli.calls[-1]
    assert release[:3] == ["foundry", "apps", "release"]
    assert release[release.index("--deployment-id") + 1] == "bbb"
    assert release[release.index("--notes") + 1] == "Initial app"
    assert "--no-prompt" in release
    assert sum(c[2] == "deploy" for c in cli.calls) == 1, "deploy must run exactly once"
    assert "Released" in capsys.readouterr().out


def test_deploy_flags(app_root):
    cli = FakeCLI([table([("bbb", "v1.0.0-pre-release", "🟢 Successful")])])
    dr.main(["--change-log", "x", "--change-type", "Major"], runner=cli)
    deploy = cli.calls[0]
    assert deploy == ["foundry", "apps", "deploy", "--no-prompt",
                      "--change-type", "Major", "--change-log", "x"]


def test_no_release_stops_after_success(app_root):
    cli = FakeCLI([table([("bbb", "v1.0.0-pre-release", "🟢 Successful")])])
    assert dr.main(["--change-log", "x", "--no-release"], runner=cli) == 0
    assert all(c[2] != "release" for c in cli.calls)


def test_failed_deployment_points_to_console_and_skips_release(app_root, capsys):
    cli = FakeCLI([table([("bbb", "v1.0.0-pre-release", "🔴 Failed")])])
    assert dr.main(["--change-log", "x"], runner=cli) == 1
    assert all(c[2] != "release" for c in cli.calls)
    assert "Show errors" in capsys.readouterr().out


def test_deploy_error_returns_its_exit_code(app_root, capsys):
    cli = FakeCLI([], deploy=(1, "Error: failed to deploy app\nvalidation failed"))
    assert dr.main(["--change-log", "x"], runner=cli) == 1
    assert len(cli.calls) == 1
    assert "validation failed" in capsys.readouterr().out


def test_timeout_reports_how_to_continue(app_root, capsys):
    cli = FakeCLI([table([("bbb", "v1.0.0-pre-release", "In progress")])])
    assert dr.main(["--change-log", "x", "--timeout", "0"], runner=cli) == 3
    out = capsys.readouterr().out
    assert "still in progress" in out
    assert "--deployment-id bbb" in out


def test_requires_app_root(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    assert dr.main(["--change-log", "x"], runner=FakeCLI([])) == 2
    assert "manifest.yml" in capsys.readouterr().out


def test_release_failure_is_reported(app_root):
    cli = FakeCLI([table([("bbb", "v1.0.0-pre-release", "🟢 Successful")])],
                  release=(1, "Error: release failed"))
    assert dr.main(["--change-log", "x"], runner=cli) == 1
