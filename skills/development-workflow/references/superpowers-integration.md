# Superpowers Plugin Integration

When the [superpowers](https://github.com/obra/superpowers) plugin is installed, **the development-workflow skill still owns the Foundry development flow**. Superpowers skills supplement but do not replace this workflow:

| Superpowers Skill | Role in Foundry Development |
|---|---|
| `brainstorming` | **Do NOT use for Foundry app creation.** The App Creation Flow handles requirements gathering and planning. Brainstorming doesn't know about `foundry apps create` or the CLI. |
| `writing-plans` | **Do NOT use for Foundry scaffolding plans.** Plans it generates will manually create manifest.yml and boilerplate. Use the App Creation Flow instead. |
| `test-driven-development` | **CAN supplement.** Useful for TDD discipline when writing function handlers or UI component logic. |
| `requesting-code-review` / `code-reviewer` | **CAN supplement.** Useful for reviewing completed implementations. |
| `finishing-a-development-branch` | **CAN supplement.** Useful for git workflow after implementation is complete. |
| `subagent-driven-development` | **Use with caution.** If used, each subagent task MUST use CLI commands for scaffolding, not manual file creation. The hook injects CLI requirements as a safety net. |

## Safety Net: PreToolUse Hook

A `PreToolUse` hook (`hooks/superpowers-foundry-bridge.sh`) fires whenever a superpowers planning skill is invoked in a Foundry project directory. It injects CLI scaffolding requirements into the planning skill's context. A separate `PreToolUse` hook in `hooks/foundry-skill-router.sh` injects a non-blocking advisory reminder when Foundry development intent is detected.

## What superpowers:writing-plans MUST Do Differently for Foundry

When `writing-plans` generates an implementation plan for a Foundry app, it MUST structure scaffolding tasks around CLI commands:

**Task pattern for new apps:**
```bash
foundry apps create --name "app-name" --description "description" --no-prompt --no-git
cd app-name
```

**Task pattern for API integrations:**
```bash
# Delegate ALL OpenAPI spec work to the api-integrations sub-skill.
foundry api-integrations create --name "MyApi" --description "desc" --spec /tmp/MyApi.yaml
```

**Task pattern for UI pages:**
```bash
foundry ui pages create --name "my-page" --description "Page description" --from-template React --homepage --no-prompt
foundry ui navigation add --name "My Page" --path / --ref pages.my-page
# Edit the generated source files in ui/pages/my-page/src/ with app-specific UI logic
```

**Task pattern for workflows:**
```bash
# Write workflow YAML to /tmp/My_workflow.yml — NOT inside the project directory
foundry workflows create --name "My Workflow" --spec /tmp/My_workflow.yml
# Edit the project copy at workflows/My_workflow.yml if needed
```

**Task pattern for functions:**
```bash
foundry functions create --name "my-function" --language python \
  --description "Process data" --handler-name process \
  --handler-method POST --handler-path /api/process --no-prompt
# Edit the handler implementation at functions/my-function/main.py
```

**Task pattern for collections:**
```bash
# Collection names: letters, numbers, underscores ONLY (no hyphens)
foundry collections create --name "my_collection" --schema /tmp/my_schema.json \
  --description "App data" --no-prompt --wf-expose --wf-tags "tag1,tag2"
```

## What Plans Must NOT Do

- Do NOT create `manifest.yml` manually — `foundry apps create` generates it
- Do NOT manually add entries to `manifest.yml` for capabilities — CLI commands update it
- Do NOT scaffold UI boilerplate (index.html, package.json, vite.config.js) — `foundry ui pages create --from-template React --no-prompt` does this
- Do NOT manually create function directory structure — `foundry functions create` does this
- Do NOT `mkdir` capability directories (api-integrations/, workflows/, etc.) — CLI commands create them
- Do NOT write spec/schema files directly into the project — write to `/tmp/` and let CLI copy them in
- Do NOT manually add auth scopes to `manifest.yml` for CLI-created artifacts — Foundry manages permissions automatically

## What Plans MUST Write by Hand

The CLI scaffolds structure but cannot generate domain-specific content:
- **OpenAPI spec content** — delegate to api-integrations sub-skill
- **Workflow YAML logic** — triggers, actions, conditions, loops, variable references
- **UI component code** — React/Vue/JS application logic
- **Function handler logic** — the actual Python/Go implementation
- **Collection schema content** — JSON Schema properties, indexable fields

## When superpowers Is NOT Installed

The skill handles the full lifecycle itself using the same CLI commands. The phases (Discovery → Scaffolding → Development → Integration → Release) apply regardless. The only difference is that superpowers adds structured planning documents and review checkpoints between phases.

## When to Use Superpowers Skills

Superpowers skills are useful AFTER scaffolding is complete, during the implementation phase:
- `superpowers:test-driven-development` — for TDD discipline when writing function handlers, UI tests
- `superpowers:requesting-code-review` — for reviewing completed capability implementations
- `superpowers:finishing-a-development-branch` — for git workflow after all capabilities are implemented
