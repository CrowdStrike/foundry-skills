# NG-SIEM Content APIs: Dashboards, Saved Queries, Lookup Files

Calling the `NGSIEM` content methods from a function. `SKILL.md` covers searches (`start_search`); this covers the content calls around them.

## Search domain names differ by API

The `NGSIEM` class takes a `search_domain` or `repository` on most calls, and the accepted values are not shared between APIs. Check each value against the API's swagger, not the console's labels.

| Calls | Accepted values |
|-------|-----------------|
| Dashboards and saved queries (`list_dashboards`, `get_dashboard_template`, `create_dashboard_from_template`, `list_saved_queries`, `get_saved_query_template`, `bulk_create_saved_queries_from_template`) | Search domain aliases: `all`, `falcon`, `third-party` |
| Persisted aggregations (`list_persisted_aggregations` and the rest) | A view or repository name, such as `search-all`. `all` and `falcon` give `404`, and `third-party` gives `400` |
| Searches (`start_search`, `get_search_status`) | A view, such as `search-all` (see the `search-all` gotcha in `SKILL.md`). `falcon` is not a view |

A `404` or `400` from these calls means a wrong name or ID, not a missing scope. A missing scope answers `403` for every input.

## Creating dashboards and saved queries

- **The new item's name comes from the template.** `create_dashboard_from_template` ignores its `name` parameter and uses the YAML's top-level `name:`. Rewrite that field to name a copy, and do the same for saved query templates.
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
| `list_lookup_files` | `ngsiem-lookup-files:read` | From the API swagger, not yet verified in a deployed app |
| `list_persisted_aggregations`, `bulk_create_persisted_aggregations`, `update_persisted_aggregation` | `ngsiem-persisted-aggregations:read`, `ngsiem-persisted-aggregations:write` | Verified against a live CID. Add by hand: `foundry auth scopes add` rejects these names (see `security-patterns`) |
