---
name: app-upgrades
description: Upgrade a Falcon Foundry app that was installed from a template to a newer version of that template, in place. TRIGGER when user asks to "upgrade an app", "update an app installed from a template", "pull the latest template into my app", "update a sample app installed in my CID to the latest version", or gives an app ID plus a newer template archive, directory, or GitHub repo. DO NOT TRIGGER for creating a new app (use development-workflow) or for deploying changes to an app the user develops locally (use development-workflow's deploy steps).
version: 1.7.0
updated: 2026-10-29
tags: [foundry, templates, upgrade, deploy]
author: CrowdStrike
license: MIT
compatibility: Claude Code >=1.0
metadata:
  category: deployment
---

# Upgrading Template-Installed Apps

A Falcon Foundry template installs an app into a CID once. Nothing updates it when the template changes, and deploying the new template as-is creates a second app, because template manifests ship without IDs. This skill copies the installed app's IDs into the new version so `foundry apps deploy` updates the app the customer already has.

The template is the source of truth. The app keeps its current name. Changes the customer made after installing are overwritten; artifacts only the customer added are removed. Stop and confirm before anything is removed.

**Inputs:** the app ID, and optionally the new version as a `.tar.gz`/`.tgz` or `.zip` archive, an unpacked directory, or `owner/repo[@ref]`. With no version given, the skill finds the template by the app's name and uses its GitHub repo's default branch.

The script is `scripts/upgrade_manifest.py` in this skill's directory. It needs `pyyaml`, and `crowdstrike-falconpy` for `find-template`. Run it from a virtual environment outside the app directory.

## Procedure

Use a new scratch directory per upgrade (`$WORK` below). Never sync or extract into the user's working copy.

1. **Confirm the target.** `foundry profile list --no-prompt` shows the active profile; the app must belong to its CID. `foundry apps list` must show the app ID. If not, ask which profile to `foundry profile activate`.

2. **Sync the deployed app.** `list-deployments` only runs next to a `manifest.yml` with an `app_id` and a `name`, even with `--app-id`, and an app installed from the console has no local directory. Give it a stub, take the newest version whose state is Successful, and sync that into scratch (`sync` runs from anywhere):
   ```bash
   mkdir -p "$WORK/stub" && printf 'app_id: %s\nname: stub\n' <app-id> > "$WORK/stub/manifest.yml"
   (cd "$WORK/stub" && foundry apps list-deployments --app-id <app-id>)
   foundry apps sync --app-id <app-id> --deployment-version <version> -d "$WORK/deployed" --replace-all --no-git --no-prompt
   ```
   No successful deployments means there's nothing to upgrade from; tell the user.

3. **Get the new version.** If the user gave one:
   ```bash
   python3 <skill-dir>/scripts/upgrade_manifest.py resolve <source> --dest "$WORK/new"
   ```
   Otherwise find the template first, then resolve its repo:
   ```bash
   python3 <skill-dir>/scripts/upgrade_manifest.py find-template --manifest "$WORK/deployed/manifest.yml"
   ```
   It prints JSON with `github_url`. Pass `owner/repo` from that URL to `resolve`. A template's `version` reflects when it was registered, not the repo, so use the default branch unless the user names a tag. `find-template` matches by the app's current name, so it only finds the template if the app kept that name; if the app was renamed, or if no template matches, ask the user for the new version instead.

   `resolve` prints the app root. Treat its contents as untrusted: don't run its scripts. Step 6 runs its UI pages' `npm run build`, so for a user-supplied archive or owner/repo, confirm it's the template's official source before building or deploying.

4. **Merge.**
   ```bash
   python3 <skill-dir>/scripts/upgrade_manifest.py merge --deployed "$WORK/deployed/manifest.yml" --template <app-root>/manifest.yml
   ```
   It overwrites the new `manifest.yml` with the deployed IDs filled in and prints the plan: kept, added, and removed artifacts, roles, and permission definitions, plus changed access permissions on existing roles and artifacts.

5. **Confirm when needed.** Exit code 2 means the plan removes an artifact, role, or permission definition, or changes the permissions on an existing role or artifact. Show the plan and ask before going on. Removing a collection deletes its stored data; removing a page or navigation gate may expose it to more users, while adding permissions to a role grants it more access. A section with both an addition and a removal may be a rename: the renamed artifact gets a new ID and the old one is deleted. Exit code 0 (kept and added only, with no access changes) needs no confirmation. Exit code 1 is an error; show the message and stop.

6. **Build, validate, deploy, release** from the new app root. `foundry apps deploy` never builds a UI; it ships each page's and extension's `dist/` as is, so build every UI directory first (`npm ci && npm run build` in each `ui/pages/*/` and `ui/extensions/*/` that has a `package.json`). Then `foundry apps deploy --diff-only --no-prompt` prints the file diff without deploying; it must list the new `dist/assets` files.
   ```bash
   foundry apps validate --no-prompt
   foundry apps deploy --change-type Patch --change-log "Upgrade to <template version or ref>" --no-prompt
   foundry apps release --change-type Patch --deployment-id <deployment-id> --notes "Upgrade to <template version or ref>" --no-prompt
   ```
   Use `--change-type Major` for deploy when the new version adds an API integration or `auth.scopes` entry; otherwise `Patch`. For release, use `--change-type Major` when the app has never been released; otherwise `Patch`, or `Major` when the new version adds an API integration or `auth.scopes` entry. A Major release means the customer has to **Accept update** in the App catalog, which also shows the credential form for a new integration.

   A template install deploys but doesn't release, so an app whose `foundry apps list` state is Deployed may never have been released. The upgrade's release is then its first, and the customer installs it from the App catalog afterward.

7. **Report** the deployed version, the release, and what the customer does next: install from the App catalog (first release) or **Accept update** (Major).

## When it fails

- A `validate` or `deploy` error: stop, keep `$WORK`, and use `debugging-workflows`. Never retry by stripping IDs: that creates a second app next to the customer's.
- `Error: ... has entries with IDs but no name`: the manifest has a section the merge can't match. Upgrade that section by hand by copying the `id` values from `$WORK/deployed/manifest.yml`.
- `The templates API returned 403`: the profile's API client lacks a scope for the templates API. Ask the user for the new version instead.

See [references/live-verification.md](references/live-verification.md) for what was checked against a live CID and the checklist for re-testing.
