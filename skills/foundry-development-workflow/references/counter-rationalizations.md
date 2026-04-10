# Counter-Rationalizations and Red Flags

## Counter-Rationalizations Table

| Your Excuse | Reality |
|-------------|---------|
| "I have API experience" | Foundry APIs have platform-specific auth, discovery, and error handling |
| "Time pressure means skip sub-skills" | Sub-skills PREVENT rework that costs 10x more time |
| "I can learn patterns during implementation" | Learning while implementing = building on wrong assumptions |
| "Sub-skills are overkill for simple cases" | No Foundry capability is simple - platform complexity is hidden |
| "I'll refactor with sub-skills later" | Technical debt in multi-tenant systems never gets refactored |
| "Basic patterns are transferable" | Foundry patterns differ significantly from generic implementations |
| "Meeting deadline is more important" | Wrong implementations miss deadlines through cascading failures |
| "I can reference documentation instead" | Documentation explains what, sub-skills explain how and why |
| "The planning skill handles scaffolding" | Planning skills generate task lists, not Foundry artifacts — CLI scaffolding is still required |
| "I'll write manifest.yml by hand" | CLI-generated manifests include correct defaults and avoid schema mistakes |
| "I know this API, I'll write the OpenAPI spec" | Delegate to foundry-api-integrations — it knows Foundry-specific server variable and annotation requirements |
| "The command is probably `foundry apps init`" | It's `foundry apps create`. There is no `init` command |

## Red Flags - STOP Immediately

Stop when thinking:
- "This is just a simple API call"
- "I can implement this faster myself"
- "Sub-skills are academic overhead"
- "Time pressure justifies shortcuts"
- "I'll clean it up later"
- "My experience applies here"
- "I'll just write a quick OpenAPI spec"
- "The CLI failed, I'll create the directories manually with mkdir"
- "I'll just write manifest.yml by hand"

**STOP. Use the sub-skill. No exceptions.**

## Why Sub-Skills Are Non-Negotiable

**Foundry Platform Complexity:**
- 47 manifest.yml capability types with interdependencies
- Authentication flows across 5 cloud regions
- Schema evolution patterns affecting data migration
- Multi-tenant security boundaries and permission scoping
- Fusion orchestration with 200+ workflow operators

**Your "Experience" Doesn't Transfer:**
- Generic API patterns ≠ Falcon Platform OAuth 2.0 client credentials
- Standard REST ≠ CrowdStrike's multi-region discovery protocols
- Basic schemas ≠ Foundry's capability-aware JSON Schema extensions
- General YAML ≠ Fusion's 3-phase execution model

**Technical Debt Compounds Exponentially:**
- Wrong patterns get copy-pasted across the organization
- Integration failures cascade to dependent teams
- Security vulnerabilities affect multi-tenant platform
- Performance anti-patterns impact thousands of users
