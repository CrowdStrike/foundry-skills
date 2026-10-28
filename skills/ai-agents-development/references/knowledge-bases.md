# Knowledge Bases — File Sourcing, Encryption, and Packaging

Deep reference for the `ai.knowledge_bases` capability. The `SKILL.md` covers the common path; this covers the edges.

## What a knowledge base is

A named directory of files under `knowledge-bases/<path>/`, recorded in `manifest.yml` as one entry in `ai.knowledge_bases`. It has no schema, no chunking config, no embedding config, and no data-source block — those concepts do not exist in the CLI. A KB is exactly: an id, a name, a description, an encrypt flag, a path, and a list of bare filenames. How the files are indexed and embedded is entirely server-side.

## Sourcing files

`--files` accepts two kinds of value:

- **Local paths** — `./docs/runbook.md`, `/tmp/iocs.csv`. Copied into the KB directory under their basename.
- **HTTP(S) URLs** — downloaded once, at create time, and written under the URL's basename.

URLs are not live references. The file content is frozen at the moment you run `create`. To refresh it before the KB's first deploy, re-download and overwrite. After a deploy, files are write-once: see [Changing a deployed knowledge base](#changing-a-deployed-knowledge-base). Pass multiple files as a comma-separated list or by repeating the flag.

Only the basename is stored in the manifest, so two sources with the same basename collide in the KB directory. Rename before adding.

## Encryption

`--encrypt` sets `encrypt: true` in the manifest. The CLI does nothing else with it — no local encryption, no validation, no restriction. It is a passthrough hint the platform honors at deploy/install time. Set it for KBs holding sensitive reference material; there is no cost to leaving it `false` for public docs.

## File constraints

The CLI enforces almost nothing, which means the platform enforces it later:

- **At least one file** is required. `knowledge base "X" must have at least one file`.
- **Bare filenames only** in the manifest. A `/` in a `files` entry fails validation: `file "f" must be a filename only, not a path`. KB directories cannot contain subdirectories.
- **No extension allowlist** in the CLI. `.md`, `.txt`, `.csv`, `.pdf`, `.json` are all accepted. Whether the platform can actually index a given type is a server-side question — prefer text-based formats (Markdown, plain text, CSV) for reliable retrieval.
- **No per-file size check** in the CLI.
- **Name and description are barely validated on the manifest.** The name floor is one character and the description is not checked at all, because the AI platform imposes no restriction the CLI would be adding on top of. The `kb create` flags are stricter (name 5–100, description 3–500), so the looser rules only matter for a manifest you inherit or hand-write.

## Deleting a knowledge base

```bash
foundry knowledge-bases delete --name "Threat Intel Docs" --no-prompt
```

Removes the manifest entry and the `knowledge-bases/<path>/` directory. Notes:

- **`--name` is required under `--no-prompt`** (`flag --name is required when --no-prompt flag is used`), and must match the manifest name.
- **Referenced KBs are protected.** `cannot delete knowledge base "X": still referenced by agent(s): A` — delete the agent, or remove the KB from its `knowledge_bases` list, first.
- The manifest is saved before the directory is removed. If removal fails you get an explicit orphaned-directory message naming the path to clean up by hand.
- The empty `knowledge-bases/` parent directory is left in place after the last KB is deleted. Harmless.

There is no `knowledge-bases list` or `edit`. Before a KB's first deploy, change its files by editing the `files` list and the directory contents together, or delete and re-create it. After it has been deployed, see the next section.

## Changing a deployed knowledge base

Files in a deployed knowledge base are write-once. Changing a file's content under the same name and deploying again fails the KB with:

```
{"code":409,"message":"a file with name '<file>' already exists in this knowledge base"}
```

Every agent that lists the KB then fails as a dependent artifact (`Dependent artifact failed (400)`, "Fix the failed dependent Knowledge base with name ..."). The reason appears only in App manager "Show errors", not in the CLI.

To ship new text, deploy it as a new knowledge base:

1. Set the entry's `name` to a new name and `path` to the sanitized new name (every character outside `[a-zA-Z0-9-_]` becomes `_`, then leading and trailing `_` are trimmed, so `Threat Intel Docs (v2)` becomes `Threat_Intel_Docs__v2`). Rename the directory under `knowledge-bases/` to match `path`.
2. Delete the entry's `id` key so the next `foundry apps validate` or `foundry apps deploy` assigns a new one.
3. Update `knowledge_bases` on every agent that lists the KB, and any system prompt text that names it.

The old KB stays in the tenant, unreferenced. Delete it in the console when nothing needs it.

## Deploy packaging gotchas

`foundry apps deploy` walks the whole app directory and bundles everything not in the ignore list. Two rules bite KB files specifically:

- **Any path containing `svg` is ignored.** The packager always appends the pattern `(?i).*?.svg`, which is unanchored and has an unescaped dot, so it matches any character followed by `svg` in any case anywhere in the file's path, not just `.svg` files. A KB file such as `diagram.svg` or `svg-guide.md`, or any file in a KB whose path contains `svg`, passes `foundry apps validate` but is silently dropped from the deployed bundle, and the agent behaves as if it were never there. Rename such files, and convert diagrams to PNG or describe them in text.
- **25 MB total package cap.** Every artifact shares one budget. Large PDF corpora in a KB can push the whole app over the limit: `package total size is over limit [N bytes], you need to ignore or remove unused files before deploy`. Trim or split.

Unlike function assets, KB binaries (PDF, etc.) are **not** skipped by the binary-file filter — they do get packaged. Only the SVG rule and the size cap apply.

## Migrating an older app

The KB directory name changed over the capability's development:

- Files now live in `knowledge-bases/` (hyphen). An early build used `knowledge_bases/` (underscore).
- Files now resolve against the manifest `path` field. An earlier build resolved against `name`.

An app scaffolded on an old CLI may have a `knowledge_bases/` directory or a name-based path and will fail validation on a current CLI with a file-not-found error. Fix by renaming the directory to `knowledge-bases/` and setting each entry's `path` to the sanitized name (every character outside `[a-zA-Z0-9-_]` replaced with `_`, then leading and trailing `_` trimmed).

## No RBAC

Knowledge bases have no `permissions` field and are not run through the permission validator. There is no OAuth scope specific to KBs. Access control is entirely server-side; deploy credentials are the only requirement to ship one.

## Minimal valid entry

The smallest KB the validator accepts — `id` is filled in by the next `foundry apps validate` or `foundry apps deploy`, `description` is optional:

```yaml
ai:
    knowledge_bases:
        - name: Threat Intel Docs
          path: Threat_Intel_Docs
          files:
            - overview.md
```

Requires `knowledge-bases/Threat_Intel_Docs/overview.md` to exist on disk.
