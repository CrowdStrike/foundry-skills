# Simple UI-Only App Test Scenario

## Scenario Description
Test complete development lifecycle for a simple SOC dashboard with UI-only architecture.

## Test Objective
Verify the foundry-development-workflow orchestrator can:
1. Map simple UI requirements to appropriate sub-skills
2. Delegate to foundry-ui-development correctly
3. Coordinate Falcon API integration for data access
4. Manage CLI state throughout development
5. Generate proper manifest.yml with minimal scopes

## Expected User Input
```
/foundry-development-workflow "Create SOC dashboard for threat hunting with detection data visualization"
```

## Expected Skill Behavior

### Phase 1: Discovery
- [ ] Orchestrator recognizes UI + data visualization requirements
- [ ] Maps to UI Pages capability (not UI Extensions)
- [ ] Identifies Falcon Detection API requirements
- [ ] Selects appropriate OAuth scopes (detections:read)

### Phase 2: Scaffolding
- [ ] Runs `foundry apps create` with appropriate template
- [ ] Generates manifest.yml with UI pages configuration
- [ ] Sets up basic project structure

### Phase 3: Development
- [ ] Delegates to `foundry-ui-development` for dashboard components
- [ ] Delegates to `foundry-functions-falcon-api` for Detection API
- [ ] Coordinates manifest updates for routing and scopes
- [ ] Manages `foundry ui run` server state

### Phase 4: Integration
- [ ] Validates manifest schema and OAuth scopes
- [ ] Tests UI components with live API integration
- [ ] Verifies `foundry ui run` serves components correctly

### Phase 5: Release
- [ ] Coordinates `foundry apps deploy` for cloud testing
- [ ] Validates deployment success
- [ ] Provides options for `foundry apps release`

## Verification Criteria

### Generated App Structure
```
soc-dashboard/
├── manifest.yml                    # UI pages + minimal scopes
├── ui/pages/dashboard/
│   ├── package.json               # Foundry-JS + Shoelace deps
│   ├── src/
│   │   ├── components/
│   │   │   ├── AlertsTable.vue    # Detection data display
│   │   │   └── FilterPanel.vue    # Detection filtering
│   │   └── services/
│   │       └── falconApi.js       # Detection API client
│   └── vite.config.js             # Foundry UI build config
└── README.md                      # Generated documentation
```

### Manifest Validation
- [ ] Contains UI pages configuration
- [ ] Includes detections:read OAuth scope
- [ ] Proper routing configuration for dashboard
- [ ] No unnecessary capabilities or scopes

### CLI State Validation
- [ ] `foundry ui run` started and maintained
- [ ] Correct profile used throughout development
- [ ] No conflicting server processes
- [ ] Clean deployment without CLI errors

## Success Criteria
- Orchestrator completes all phases without errors
- Generated app structure matches expectations
- Manifest validates successfully
- UI components load in Falcon console development mode
- API integration works with proper authentication

## Failure Scenarios to Test
- Invalid OAuth profile → Should detect and request profile fix
- Port conflicts for `foundry ui run` → Should resolve automatically
- Manifest validation errors → Should delegate to debugging workflow
- API authentication failures → Should provide clear troubleshooting

## Execution Time
Expected completion: 3-5 minutes for full lifecycle
(Excludes actual coding time, focuses on orchestration)
