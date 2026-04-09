# Foundry Development Workflow - Usage Examples

## Complete Usage Scenarios

### Example 1: Simple UI-Only SOC Dashboard

**Scenario:** Create a threat hunting dashboard that displays detection data with filtering and visualization.

**Requirements:**
- UI Pages for standalone dashboard access
- Falcon Detection API integration for alert data
- Shoelace components for consistent Falcon console styling
- No backend storage (read-only dashboard)

**Usage:**
```bash
/foundry-development-workflow "Create a SOC dashboard for threat hunting with detection data visualization"
```

**Expected Flow:**
1. **Discovery:** Orchestrator identifies UI + Falcon API requirements
2. **Scaffolding:** Creates app with `foundry apps create`, configures minimal manifest
3. **Development:** Delegates to `foundry-ui-development` and `foundry-functions-falcon-api`
4. **Integration:** Validates OAuth scopes, tests with `foundry ui run`
5. **Release:** Deploys for testing, releases to catalog

**Generated Structure:**
```
soc-dashboard/
├── manifest.yml              # UI pages + Detection API scopes
├── ui/pages/dashboard/       # Vue.js dashboard components
├── ui/pages/dashboard/src/
│   ├── components/
│   │   ├── AlertsTable.vue   # Shoelace data table
│   │   ├── FilterPanel.vue   # Detection filtering
│   │   └── MetricsCards.vue  # Summary statistics
│   └── services/
│       └── falconApi.js      # Detection API client
└── package.json              # Foundry-JS + Shoelace deps
```

**Key Learning:** Simple UI apps still benefit from Foundry patterns for authentication and API integration.

### Example 2: Backend Functions + Collections App

**Scenario:** Build an IOC enrichment service that accepts indicators, enriches them via third-party APIs, and stores results.

**Requirements:**
- REST API endpoints for IOC submission and retrieval
- Collections for persistent IOC storage with search capability
- External API integration (VirusTotal, etc.)
- Go Functions for performance with concurrent API calls

**Usage:**
```bash
/foundry-development-workflow "Build IOC enrichment service with external API integration and persistent storage"
```

**Expected Flow:**
1. **Discovery:** Maps to Functions + Collections + external API patterns
2. **Scaffolding:** Creates backend-focused app structure
3. **Development:**
   - `foundry-functions-development`: REST endpoints and business logic
   - `foundry-collections-development`: IOC data modeling and storage
4. **Integration:** Tests API endpoints with collection operations
5. **Release:** Validates performance and deploys

**Generated Structure:**
```
ioc-enrichment/
├── manifest.yml              # Functions + Collections + external HTTP
├── functions/
│   ├── submit-ioc/           # POST /ioc endpoint
│   ├── get-enrichment/       # GET /ioc/{id} endpoint
│   └── enrich-worker/        # Background enrichment job
├── collections/
│   └── ioc-results/          # JSON schema for IOC data
│       └── schema.json       # Structured IOC + enrichment data
└── go.mod                    # CrowdStrike Go SDK dependencies
```

**Key Learning:** Backend apps benefit from Collections for structured data and async processing patterns.

### Example 3: Full-Stack Investigation Console App

**Scenario:** Complete incident response application with case management UI, automated investigation workflows, and real-time collaboration.

**Requirements:**
- UI Extensions embedded in Falcon console for context
- UI Pages for standalone case management
- Functions for case processing and external integrations
- Collections for case data, evidence, and user activity
- Workflows for automated investigation playbooks
- Falcon API integration for host data, detections, and RTR

**Usage:**
```bash
/foundry-development-workflow "Build comprehensive incident response platform with case management, automated playbooks, and real-time collaboration"
```

**Expected Flow:**
1. **Discovery:** Identifies all capability types, complex OAuth scope requirements
2. **Scaffolding:** Creates full-capability app structure
3. **Development:** Delegates to ALL sub-skills in coordinated phases:
   - `foundry-ui-development`: Console extensions + standalone pages
   - `foundry-functions-development`: Case processing APIs
   - `foundry-collections-development`: Case, evidence, and activity schemas
   - `foundry-workflows-development`: Investigation playbook automation
   - `foundry-functions-falcon-api`: Host, detection, and RTR APIs
4. **Integration:** Complex manifest coordination, end-to-end testing
5. **Release:** Staged deployment with rollback planning

**Generated Structure:**
```
incident-response/
├── manifest.yml              # All capabilities + comprehensive scopes
├── ui/
│   ├── extensions/
│   │   ├── host-context/     # Host details page integration
│   │   └── detection-triage/ # Detection page case creation
│   └── pages/
│       ├── case-management/  # Standalone case dashboard
│       └── playbook-editor/  # Workflow template editor
├── functions/
│   ├── case-api/             # CRUD operations for cases
│   ├── evidence-processor/   # File analysis and storage
│   └── notification-hub/     # Real-time updates via webhooks
├── collections/
│   ├── cases/                # Case metadata and status
│   ├── evidence/             # Evidence artifacts and analysis
│   └── activity-log/         # User actions and audit trail
├── workflows/
│   ├── malware-analysis/     # Automated malware investigation
│   ├── lateral-movement/     # Network traversal detection
│   └── containment/          # Automated host isolation
└── rtr-scripts/
    ├── evidence-collection/  # Automated evidence gathering
    └── containment/          # Host isolation procedures
```

**Key Learning:** Full-stack apps require careful manifest coordination and phased development to manage complexity.

## Integration with TDD Workflow

### Example: Adding New Feature to Existing App

**Scenario:** Add threat intelligence correlation to existing SOC dashboard from Example 1.

**Usage with Test-Driven Development:**
```bash
# Step 1: Plan the feature
# Identify required capabilities, manifest changes, and OAuth scopes

# Step 2: Implement with Foundry patterns
# Use the appropriate sub-skills for each capability
/foundry-functions-falcon-api "integrate Threat Intelligence API for IOC correlation"
/foundry-ui-development "add TI correlation panel to dashboard"
```

**TDD Integration Points:**
- **RED:** Write failing tests for TI API integration before implementing
- **GREEN:** Use `foundry-functions-falcon-api` patterns for TI API
- **REFACTOR:** Optimize API calls and UI performance

**Key Learning:** Foundry skills enhance, don't replace, established TDD discipline.

## CLI State Management Examples

### Example: Multi-Environment Development

**Scenario:** Develop app locally, test in US-2 staging, deploy to EU-1 production.

**Profile Management:**
```bash
# Check available profiles
foundry profile list

# Development on US-2
foundry profile activate --name us-2-dev
/foundry-development-workflow "continue work on incident response app"

# Testing phase - switch to staging
foundry profile activate --name us-2-staging
foundry apps deploy

# Production deployment
foundry profile activate --name eu-1-prod
foundry apps release
```

**Orchestrator Behavior:**
- Validates profile authentication before development phases
- Manages `foundry ui run` server across profile switches
- Coordinates deployment commands with appropriate profiles

### Example: Development Server Management

**Scenario:** UI development with live testing in Falcon console.

**Server Lifecycle:**
```bash
# Start development (orchestrator manages this)
/foundry-ui-development "build detection alert viewer component"

# Server automatically started:
# foundry ui run (running on http://localhost:3000)

# Live testing:
# 1. Enable development mode in Falcon console
# 2. Navigate to your app - loads from localhost
# 3. Code changes hot-reload automatically

# Server cleanup (automatic or manual)
# Skills handle server lifecycle across sub-skill delegation
```

## Debugging Workflow Examples

### Example: Manifest Validation Errors

**Problem:** App deployment fails with manifest schema validation errors.

**Systematic Debugging:**
```bash
/foundry-debugging-workflows "manifest validation failing with oauth scope errors"
```

**Debugging Flow:**
1. **CLI Health Check:** Validate profile and authentication
2. **Manifest Analysis:** JSON schema validation and scope conflict detection
3. **Step-by-Step Isolation:** Test individual capability sections
4. **Recovery Strategy:** Incremental manifest rebuilding

### Example: API Integration Failures

**Problem:** Falcon API calls returning 403 errors in Functions.

**Debugging Approach:**
```bash
/foundry-debugging-workflows "falcon api calls failing with 403 in functions"
```

**Resolution Pattern:**
1. **Scope Verification:** Check manifest OAuth scopes match API requirements
2. **Profile Validation:** Verify correct environment and permissions
3. **API Testing:** Isolate API calls outside Functions context
4. **Integration Validation:** Test complete flow with proper authentication

## Performance Optimization Examples

### Example: Large Dataset Handling

**Scenario:** SOC dashboard loading slowly with large detection datasets.

**Optimization Patterns:**
- **Client-Side:** Virtualized tables with Shoelace components
- **API Layer:** Pagination and filtering in Functions
- **Caching:** Collections for frequently accessed data
- **Real-Time:** WebSocket connections for live updates

**Implementation:**
```bash
/foundry-ui-development "optimize large detection dataset display with virtualization and caching"
```

### Example: API Rate Limit Management

**Scenario:** Functions hitting Falcon API rate limits during bulk operations.

**Optimization Strategy:**
- **Batching:** Group API calls efficiently
- **Caching:** Store API responses in Collections
- **Queue Processing:** Async job handling for bulk operations
- **Retry Logic:** Exponential backoff for rate limit recovery

## Security Pattern Examples

### Example: Minimal OAuth Scope Implementation

**Scenario:** Investigation app requesting excessive API permissions.

**Scope Minimization:**
```yaml
# manifest.yml - minimal scopes
oauth:
  scopes:
    - "detections:read"      # Only read access to detections
    - "hosts:read"           # Only read access to host data
    # NOT: "admin:write" or broad wildcard scopes
```

**Implementation Pattern:**
- Analyze exact API endpoints needed
- Request minimal required scopes
- Test functionality with restricted permissions
- Document scope requirements for each feature

### Example: Input Validation in Collections

**Scenario:** Case management app accepting arbitrary user input.

**Validation Pattern:**
```json
{
  "type": "object",
  "properties": {
    "case_id": {"type": "string", "pattern": "^[A-Z0-9-]+$"},
    "severity": {"type": "string", "enum": ["low", "medium", "high", "critical"]},
    "description": {"type": "string", "maxLength": 1000}
  },
  "required": ["case_id", "severity"],
  "additionalProperties": false
}
```

**Security Benefits:**
- Prevents injection attacks via structured validation
- Enforces data consistency across app
- Provides clear error messages for invalid input

## Next Steps

1. **Try Simple Example:** Start with UI-only dashboard (Example 1)
2. **Explore Templates:** Review `skills/foundry-development-workflow/templates/`
3. **Practice Integration:** Add features to existing apps using TDD
4. **Study Debugging:** Use debugging workflows for systematic troubleshooting
5. **Optimize Performance:** Apply patterns from performance examples
