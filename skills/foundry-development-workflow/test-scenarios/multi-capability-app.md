# Multi-Capability App Test Scenario

## Scenario Description
Test complex app development with all Foundry capabilities: UI, Functions, Collections, Workflows, and comprehensive Falcon API integration.

## Test Objective
Verify the orchestrator can handle complex capability coordination for a full-featured incident response platform.

## Expected User Input
```
/foundry-development-workflow "Build comprehensive incident response platform with case management, automated playbooks, and real-time collaboration"
```

## Expected Skill Behavior

### Phase 1: Discovery
- [ ] Identifies all capability requirements:
  - UI Pages + UI Extensions for case management
  - Functions for case processing APIs
  - Collections for case/evidence/activity storage
  - Workflows for automated investigation playbooks
  - Comprehensive Falcon API integration (hosts, detections, RTR)
- [ ] Maps complex OAuth scope requirements
- [ ] Identifies capability dependencies and interaction patterns

### Phase 2: Scaffolding
- [ ] Creates full-stack app structure with all capability folders
- [ ] Generates comprehensive manifest.yml
- [ ] Sets up multi-language build configuration

### Phase 3: Development (Coordinated Multi-Skill Delegation)
- [ ] **foundry-ui-development**: Console extensions + standalone pages
  - Host context integration (UI Extension)
  - Detection triage integration (UI Extension)
  - Case management dashboard (UI Page)
  - Playbook editor (UI Page)

- [ ] **foundry-functions-development**: Backend API layer
  - Case CRUD operations
  - Evidence processing pipeline
  - Real-time notification system

- [ ] **foundry-collections-development**: Data layer
  - Case metadata schema
  - Evidence artifacts schema
  - Activity audit log schema

- [ ] **foundry-workflows-development**: Automation layer
  - Malware analysis playbook
  - Lateral movement detection
  - Automated containment procedures

- [ ] **foundry-functions-falcon-api**: Platform integration
  - Host Management API (host data, isolation)
  - Detection API (alert processing)
  - RTR API (evidence collection, containment)

### Phase 4: Integration
- [ ] Coordinates manifest updates across all capabilities
- [ ] Resolves OAuth scope conflicts and dependencies
- [ ] Validates capability interaction patterns
- [ ] Tests end-to-end workflows with all components

### Phase 5: Release
- [ ] Staged deployment validation
- [ ] Performance testing with multiple capabilities
- [ ] Comprehensive OAuth scope verification

## Verification Criteria

### Generated App Structure
```
incident-response/
├── manifest.yml                    # All capabilities + comprehensive scopes
├── ui/
│   ├── extensions/
│   │   ├── host-context/          # Host details integration
│   │   └── detection-triage/      # Case creation from detections
│   └── pages/
│       ├── case-management/       # Standalone dashboard
│       └── playbook-editor/       # Workflow templates
├── functions/
│   ├── case-api/                  # Go-based case operations
│   ├── evidence-processor/        # File analysis pipeline
│   └── notification-hub/          # WebSocket notifications
├── collections/
│   ├── cases/schema.json          # Case metadata
│   ├── evidence/schema.json       # Evidence artifacts
│   └── activity-log/schema.json   # Audit trail
├── workflows/
│   ├── malware-analysis.yml       # Automated investigation
│   ├── lateral-movement.yml       # Network analysis
│   └── containment.yml            # Host isolation
├── rtr-scripts/
│   ├── evidence-collection/       # Automated forensics
│   └── containment/              # Isolation procedures
├── go.mod                         # Backend dependencies
└── package.json                   # Frontend dependencies
```

### Manifest Complexity Validation
- [ ] All capability types properly configured
- [ ] OAuth scopes include all required APIs:
  - `hosts:read`, `hosts:write` (host management)
  - `detections:read` (alert processing)
  - `rtr:read`, `rtr:write` (real-time response)
  - `workflows:read`, `workflows:write` (automation)
- [ ] UI routing covers all pages and extensions
- [ ] Function endpoints properly defined
- [ ] Collection schemas properly referenced
- [ ] Workflow templates properly registered

### Sub-Skill Coordination
- [ ] All 5 sub-skills invoked in proper sequence
- [ ] No conflicts between capability implementations
- [ ] Shared dependencies (Foundry-JS, CrowdStrike SDKs) coordinated
- [ ] Build processes don't interfere with each other

### CLI State Management
- [ ] `foundry ui run` serves both extensions and pages
- [ ] Profile authentication maintained across all API integrations
- [ ] No port conflicts or server issues
- [ ] Clean build and deployment processes

## Success Criteria
- Orchestrator successfully delegates to all 5 sub-skills
- Generated app includes all expected capabilities
- Manifest validates with complex OAuth scope configuration
- No capability conflicts or build issues
- End-to-end testing shows integrated functionality

## Complex Failure Scenarios
- OAuth scope conflicts between capabilities → Debugging workflow
- Build conflicts between Functions and UI → Build coordination
- Manifest size exceeds limits → Optimization suggestions
- Multiple capability deployment failures → Rollback procedures

## Performance Expectations
- Orchestration completes within 10-15 minutes
- Context usage remains reasonable despite complexity
- CLI operations are properly batched
- No memory issues during multi-capability builds

## Success Indicators
1. **Delegation Success**: All sub-skills invoked appropriately
2. **Integration Success**: Capabilities work together seamlessly
3. **Testing Success**: End-to-end workflows function correctly
4. **Deployment Success**: App deploys and releases without issues
