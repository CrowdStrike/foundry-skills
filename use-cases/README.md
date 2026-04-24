# Use Cases

Real-world patterns extracted from [CrowdStrike Tech Hub](https://www.crowdstrike.com/tech-hub/ng-siem/?cspage=0&lang=English&cs-search=foundry) blog posts and sample apps. Each file captures an actionable pattern that Claude can apply when users describe similar scenarios.

## How the Orchestrator Uses These

The `development-workflow` orchestrator globs `use-cases/*.md` and scans frontmatter `description` fields to match user requests to known patterns. Sub-skills also reference specific use cases for real-world examples.

## File Format

```markdown
---
name: use-case-name
description: One-line trigger for orchestrator pattern matching
source: https://www.crowdstrike.com/tech-hub/ng-siem/...
skills: [workflows-development, functions-development]
capabilities: [api-integration, workflow, function, collection, ui-page, ui-extension]
---

## When to Use
What user request or scenario triggers this pattern.

## Pattern
Step-by-step solution using Foundry capabilities.

## Key Code
Essential snippets adapted for skill format.

## Gotchas
Known issues, platform quirks, common mistakes.
```

## Adding New Use Cases

1. Create a new `.md` file in this directory following the format above
2. Keep files under ~150 lines (actionable patterns, not full blog summaries)
3. Add `source:` URL so patterns can be traced back to original content
4. List relevant `skills:` and `capabilities:` in frontmatter
5. Cross-reference related use cases in the Pattern section
6. Add a reference link from the relevant sub-skill SKILL.md

## Additional Resources

- [Foundry Videos](https://docs.crowdstrike.com/p/foundry-videos) (Overview, API Integrations, App Lifecycle)
- [Sample App Templates](https://developer.crowdstrike.com/docs/samples/)
- [Sample App Repos](https://github.com/search?q=topic%3Afalcon-foundry+org%3ACrowdStrike+fork%3Atrue&type=repositories) (GitHub)
- [Tech Hub NG-SIEM Articles](https://www.crowdstrike.com/tech-hub/ng-siem/?cspage=0&lang=English&type=Article)
