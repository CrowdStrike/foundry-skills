"""The release bundle accepts a Git ref with a slash in its name and checks portal-required fields."""

import json
import shutil
import subprocess
from pathlib import Path

INTERFACE = {
    "composerIcon": "./assets/logo.png",
    "logo": "./assets/logo.png",
    "supportURL": "https://example.com/support",
}


def _bundle(tmp_path, interface, ref="feature/slash"):
    repo = Path(__file__).resolve().parents[1]
    shutil.copy2(repo / "release.sh", tmp_path / "release.sh")
    (tmp_path / ".codex-plugin").mkdir()
    (tmp_path / "assets").mkdir()
    (tmp_path / "skills" / "example").mkdir(parents=True)
    (tmp_path / "use-cases").mkdir()
    (tmp_path / ".codex-plugin" / "plugin.json").write_text(json.dumps({"interface": interface}))
    shutil.copy2(repo / "assets" / "crowdstrike-logo.png", tmp_path / "assets" / "logo.png")
    (tmp_path / "skills" / "example" / "SKILL.md").write_text("# Example\n")
    (tmp_path / "use-cases" / "example.md").write_text("# Example\n")
    for name in ("LICENSE", "README.md", "requirements.txt"):
        (tmp_path / name).write_text(f"{name}\n")

    def git(*args):
        subprocess.run(["git", *args], cwd=tmp_path, check=True, capture_output=True)

    git("init", "-q")
    git("add", ".")
    git("-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-qm", "Test bundle")
    git("branch", ref)

    return subprocess.run(["bash", "release.sh", "--bundle", ref],
                          cwd=tmp_path, capture_output=True, text=True, check=False)


def test_bundle_from_slash_branch_uses_a_flat_filename(tmp_path):
    result = _bundle(tmp_path, INTERFACE)
    assert result.returncode == 0, result.stdout + result.stderr
    assert (tmp_path / "crowdstrike-falcon-foundry-feature-slash.zip").is_file()


def test_bundle_fails_without_a_support_url(tmp_path):
    """The portal rejected the v1.7.0 upload with "support URL is required"."""
    interface = {k: v for k, v in INTERFACE.items() if k != "supportURL"}
    result = _bundle(tmp_path, interface)
    assert result.returncode != 0
    assert "interface.supportURL missing" in result.stdout + result.stderr


def test_repo_manifest_has_a_support_url():
    manifest = Path(__file__).resolve().parents[1] / ".codex-plugin" / "plugin.json"
    assert json.loads(manifest.read_text())["interface"]["supportURL"].startswith("https://")
