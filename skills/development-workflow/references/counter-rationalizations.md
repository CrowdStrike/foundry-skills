# Common Wrong Turns

Each assumption on the left has produced a broken or undeployable Foundry app. The right column is what's actually true.

| Assumption | What's true |
|------------|-------------|
| "The planning skill handles scaffolding" | Planning skills generate task lists, not Foundry artifacts — CLI scaffolding is still required |
| "I'll write manifest.yml by hand" | CLI-generated manifests include correct defaults, IDs, and schema version, and avoid schema mistakes |
| "I know this API, I'll write the OpenAPI spec" | Delegate to api-integrations — it knows Foundry-specific server variable and annotation requirements |
| "The command is probably `foundry apps init`" | It's `foundry apps create`. There is no `init` command |
| "The CLI failed, so I'll create the directories with mkdir" | Fix the command and retry; hand-made structure produces an invalid manifest |
| "This is a simple case, I don't need the sub-skill" | Foundry formats and SDK calls differ from generic patterns; load the sub-skill for the capability before writing its code |
