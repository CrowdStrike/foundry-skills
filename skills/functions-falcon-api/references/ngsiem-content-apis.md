# Falcon Next-Gen SIEM Content APIs: Dashboards, Saved Queries, Lookup Files

Calling the `NGSIEM` content methods from a function. `SKILL.md` covers searches (`start_search`); this covers the content calls around them.

## Search domain names differ by API

The `NGSIEM` class takes a `search_domain` or `repository` on most calls, and the accepted values are not shared between APIs. Check each value against the API's swagger, not the console's labels.

| Calls | Accepted values |
|-------|-----------------|
| Dashboards and saved queries (`list_dashboards`, `get_dashboard_template`, `create_dashboard_from_template`, `list_saved_queries`, `get_saved_query_template`, `bulk_create_saved_queries_from_template`) | Search domain aliases (`all`, `falcon`, `third-party`) or a view name such as `search-all`, which returns the same items as `all` |
| Lookup files (`list_lookup_files`, `create_lookup_file`, and the rest under `/ngsiem-content/`) | The same aliases plus `parsers-repository`, `dashboards`, and `query-audit`, or a view name such as `search-all`. Required, though the swagger marks it optional: leaving it out gives `400` `missing search_domain query param`. `upload_file` is a `/humio/` call and takes a repository name |
| Persisted aggregations (`list_persisted_aggregations` and the rest) | A view or repository name, such as `search-all`. `all` and `falcon` give `404`, and `third-party` gives `400` |
| Searches (`start_search`, `get_search_status`) | A view, such as `search-all` (see the `search-all` gotcha in `SKILL.md`). `falcon` is not a view |

`search-all` worked on every read call above. A `404` or `400` from these calls means a wrong name or ID, not a missing scope (an unknown search domain answers `404` `view or repository not found`). A missing scope answers `403` `access denied, scope not permitted` for every input, including a malformed filter that would otherwise be a `400`.

queryjobs (`start_search`) is the exception: a real repository it won't search, such as `fusion`, answers `403` while `search-all` and other repositories work with the same credentials. From a function the message is `scope not permitted`. From an API client it is `The supplied authentication is not authorized to access this resource`. `falcon` isn't a view at all and answers `404` `could not find view=falcon`. Switch to `search-all` before adding scopes, since a new scope forces a major release.

## Creating dashboards and saved queries

- **The new item's name comes from the template.** `create_dashboard_from_template` names the dashboard from the YAML's top-level `name:`, not from its `name` parameter. Still pass `name`: FalconPy 1.6.6 uses it as the upload's filename and raises `KeyError: 'name'` without it. Rewrite the YAML field to name a copy, and do the same for saved query templates.
- **Each search domain has an asset limit per type.** At the limit, creates fail with `400` `maximum supported number of assets already exist in this search domain`. The console doesn't apply the same check, so a domain can already hold more items than the API will create, and deleting a few doesn't help until the count is under the limit. Offer another search domain, or tell the user.
- **Bulk saved query creates answer `200` even when items are refused.** Read `success` and `error` on each item in `resources`, not the status code.
- **FalconPy 1.6.6 `create_saved_query` fails** with `400` `missing or empty yaml_template file content`, because it sends the template without a filename. Use `bulk_create_saved_queries_from_template(search_domain=..., saved_query_items=[{"yaml_template": yaml_text}])` with one item, and recheck when you upgrade FalconPy.

## Lookup files and saved query functions are view-scoped

- A lookup file resolves only from a view whose search domain stores it. A query copied into another search domain can fail with `Can't find "<name>". Verify the file name is correct and try again.` `$name()` saved query functions are scoped the same way.
- A missing file fails at `get_search_status`. A missing function fails at `start_search`.
- `create_lookup_file` refuses a name that contains `/` (`path traversal characters not allowed`), so a packaged file can't be copied under its own name.

## Scopes

| Methods | Scope(s) | Verified |
|---|---|---|
| `list_dashboards`, `get_dashboard_template`, `create_dashboard_from_template` | `ngsiem-dashboards:read`, `ngsiem-dashboards:write` | Verified against a live CID |
| `list_saved_queries`, `get_saved_query_template`, `bulk_create_saved_queries_from_template` | `ngsiem-saved-queries:read`, `ngsiem-saved-queries:write` | Verified against a live CID |
| `list_lookup_files`, `create_lookup_file` | `ngsiem-lookup-files:read`, `ngsiem-lookup-files:write` | From the API swagger and docs, not yet verified in a deployed app |
| `upload_file` (a `/humio/` path, not `/ngsiem-content/`) | `humio-auth-proxy:write` | foundry-sample-ngsiem-importer (see `SKILL.md`) |
| `list_persisted_aggregations`, `bulk_create_persisted_aggregations`, `update_persisted_aggregation` | `ngsiem-persisted-aggregations:read`, `ngsiem-persisted-aggregations:write` | Verified against a live CID. Add by hand: `foundry auth scopes add` rejects these names (see `security-patterns`) |
