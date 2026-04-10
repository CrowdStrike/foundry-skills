# Foundry Development Workflow - Skills Documentation

## Overview

The **Foundry Development Workflow Skills** provide a comprehensive, battle-tested skill ecosystem for end-to-end CrowdStrike Foundry app development. This hub-and-spoke architecture includes a main orchestrating skill that manages the complete development lifecycle, plus specialized sub-skills for each Foundry capability type.

## Architecture

```
foundry-development-workflow (Main Orchestrator)
├── foundry-ui-development
├── foundry-functions-development
├── foundry-collections-development
├── foundry-workflows-development
├── foundry-api-integrations
├── foundry-functions-falcon-api
└── foundry-debugging-workflows
```

## Getting Started

### Prerequisites

1. **Foundry CLI installed and configured:**
   ```bash
   brew tap crowdstrike/foundry-cli && brew install foundry
   foundry login
   foundry profile list
   ```

2. **Skills system available** in your Claude Code environment

3. **Basic understanding** of Foundry app architecture (UI, Functions, Collections, Workflows)

### Basic Usage

**Start any Foundry development project:**

```bash
# In Claude Code
/foundry-development-workflow "build a SOC dashboard for threat hunting"
```

The orchestrator will:
1. **Discovery Phase:** Gather requirements and map to Foundry capabilities
2. **Scaffolding Phase:** Create app structure using `foundry apps create`
3. **Development Phase:** Delegate to appropriate sub-skills for each capability
4. **Integration Phase:** Coordinate manifest.yml and testing
5. **Release Phase:** Deploy and release to catalog

### Integration with Other Skills

The Foundry skills integrate with each other through the orchestrator:

- **Planning:** The orchestrator handles manifest dependency ordering and OAuth scope planning
- **Execution:** Review checkpoints between capability phases catch integration issues early
- **Testing:** Each sub-skill includes Foundry-specific testing patterns
- **Handoff:** CLI state preservation (profiles, authentication, `foundry ui run` status) across sessions

### Sub-Skill Usage

**Direct sub-skill invocation for focused work:**

```bash
# UI-focused development
/foundry-ui-development "create investigation dashboard with Shoelace components"

# Backend development
/foundry-functions-development "build REST API for IOC enrichment with Go"

# Data modeling
/foundry-collections-development "design schema for threat intelligence storage"

# Automation
/foundry-workflows-development "create incident response automation pipeline"

# External API integration
/foundry-api-integrations "integrate VirusTotal API via OpenAPI spec"

# Falcon API from Functions
/foundry-functions-falcon-api "call Detection API from Function handler"
```

## CLI State Management

The skills coordinate Foundry CLI state throughout development:

- **Profile Management:** Validates and switches profiles as needed
- **Development Server:** Manages `foundry ui run` lifecycle
- **Deployment Coordination:** Handles `foundry apps deploy` and `foundry apps release`

**Important:** Keep `foundry ui run` running during UI development for live testing.

## Troubleshooting

### Common Issues

**Profile Authentication Issues:**
```bash
# Check profile status
foundry profile list
# Re-authenticate if needed
foundry login
```

**Development Server Problems:**
```bash
# Kill existing server and restart
pkill -f "foundry ui"
foundry ui run
```

**Manifest Validation Errors:**
- Use `/foundry-debugging-workflows` for systematic error resolution
- Check OAuth scopes match your API usage
- Verify file paths in manifest correspond to actual files

### Debug Mode

For detailed troubleshooting, use the debugging skill:
```bash
/foundry-debugging-workflows "manifest validation failing with schema errors"
```

### Getting Help

1. **Check skill files** for specific patterns: `skills/foundry-*/SKILL.md`
2. **Review templates** for working examples: `skills/foundry-development-workflow/templates/`
3. **Use debugging workflow** for systematic issue resolution
4. **Check Foundry documentation** in `falcon_foundry_docs/` directory

## Performance Considerations

- **Context Management:** Skills use efficient delegation to minimize token usage
- **CLI Command Batching:** Groups related CLI operations to reduce overhead
- **Development Server Reuse:** Maintains `foundry ui run` state across sub-skills

## Security Best Practices

- **Minimal OAuth Scopes:** Request only required API permissions
- **Secret Management:** Never commit credentials (CLI handles authentication)
- **Input Validation:** Use JSON Schema validation for all data inputs

## File Structure

```
skills/foundry-development-workflow/
├── SKILL.md                 # Main orchestrator skill
├── README.md               # This documentation
├── EXAMPLES.md             # Usage examples
└── templates/              # App templates
    ├── soc-dashboard-ui-only/
    ├── automation-backend/
    └── investigation-console-full-stack/
```

## Next Steps

1. **Read EXAMPLES.md** for complete usage scenarios
2. **Try a simple project** with the main orchestrator
3. **Explore sub-skills** for capability-specific development
4. **Review templates** for architectural patterns
