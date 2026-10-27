# Live Verification

Results of checks against a live CID (Foundry CLI 2.1.2, US-2).

## Template-created apps

- `foundry apps create --from-template` takes the template name: `--from-template "Category Blocking"`. The name form succeeded on the first try; the ID fallback was not needed.
- Apps created from a template, by CLI, appear in `foundry apps list` and sync with `foundry apps sync --app-id`.
- `foundry apps deploy` and `foundry apps release` both succeed for a template-created app using the CLI profile's existing credentials, with no extra auth step. The deploy went from "In progress" to "Successful" in about a minute; no retry was needed.
- Apps installed from Foundry > Templates in the console list, sync, and carry the same ID paths as CLI-created ones; the synced manifests differ only in `name`. Right after a console install the app's state is Deployed, not Released, with one `v1.0.0-pre-release` deployment.

## ID paths in a synced manifest

- `app_id`
- `ui.pages.<page-key>.id`
- `ui.navigation.id`
- `functions[].id`
- `docs.id`

Not present in this template's manifest: `collections[].id` (collections carry no `id` field, only `workflow_integration.system_action`/`tags`), any `id` under `api_integrations` (empty list for this app), and `workflow_integration.id` under function handlers (all handlers had `workflow_integration: null`).

## Upgrade checklist

1. Create an app from a template, deploy, release.
2. Make a customer-style edit (change a function description) and deploy it.
3. Upgrade from a newer `.tar.gz`, then from a `.zip`, then from `owner/repo@ref`.
4. After each: the app ID is unchanged, kept artifacts keep their IDs, the release shows in the App catalog.
5. Upgrade across a version that removes a collection: the skill stops for confirmation.

## CLI behavior outside an app directory

- `foundry apps list-deployments` fails with `no manifest file detected` unless the current directory has a `manifest.yml`, even with `--app-id`. A stub with only `app_id` fails with `app name is required`; a stub with `app_id` and any `name` works.
- `foundry apps sync --app-id` works from any directory. Without `--no-git` it initializes an empty `.git` in the target.
- `foundry apps create --from-template` writes IDs into the new manifest before the first deploy, so a manifest with IDs isn't proof the app was deployed.
- `foundry apps list` has no `--no-prompt` flag and no JSON/verbose output with version numbers; it only prints app ID, name, and state.
- An early `merge` copied the template's `name` into the merged manifest. `merge` now keeps the deployed app's name, so a customer's rename survives an upgrade.

## Results

End-to-end test against a live CID (CLI 2.1.2, US-2), two apps installed from the same template: one CLI-created and previously released, one console-installed and never released. The newer template version used for both runs added one collection and changed one function's log message; it was built from the template's GitHub source rather than from the template's registered `main`, because `main` matched what was already installed and produced "no changes detected."

- Source `.tar.gz` (CLI-created app, already Released): `merge` exited 0 (kept + added only, no confirmation needed); `validate`, `deploy --change-type Patch`, and `release --change-type Patch` all succeeded; the new deployment reached state Successful and the app reached state Released. Kept artifact IDs (app, function, UI page, navigation, docs) matched the synced deployed manifest; the added collection had no `id` key before deploy. No duplicate app appeared in `foundry apps list`.
- Source `.zip` (console-installed app, never released): `merge` exited 0; `validate`, `deploy --change-type Patch`, and `release --change-type Major` (its first release) all succeeded; same ID and no-duplicate-app checks passed. The CLI has no command or flag that reports a release's version number, so the result was confirmed by state (Released) rather than by version string.
- Source `owner/repo` with no ref (template's default branch), paired with `find-template`: run against the console-installed app's upgraded deployment to check the removal-prompt path, since the default branch lacks the collection that run had just added. `find-template` returned the template's GitHub URL; `resolve` downloaded the default branch; `merge` exited 2 and printed `WARNING: removing collection 'upgrade_check' deletes its stored data.` as expected. Not deployed, per the test plan.
- App catalog, checked in a browser afterward: neither app had ever been installed, so both showed Not installed. Each installed from its upgraded release (first release v1.0.0 for the console-installed app, v1.0.1 for the CLI-created one), one at a time, with no errors; two copies of this template coexist in one CID. Both app pages rendered all five tabs, and the CLI-created app's page URL kept the page ID it had before any upgrade.
- The page's host-group list stayed empty on both apps. The template's function returns `500` with `KeyError: 'resources'` when the CID has no host groups; the upgrade changed only a log line in that function, so this is a bug in the template, not in the upgrade.
