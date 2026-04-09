# Cross-Session Handoff Test Scenario

## Scenario Description
Test that skills ecosystem maintains context and CLI state across session boundaries using handoff generation and resume capabilities.

## Test Objective
Verify that Foundry development can be seamlessly continued across multiple Claude Code sessions without losing context or CLI state.

## Test Flow

### Session 1: Initial Development
**Start development work:**
```
/foundry-development-workflow "Create incident response dashboard with case management"
```

**Expected Session 1 Behavior:**
1. **Discovery Phase**: Map requirements to UI + Functions + Collections
2. **Scaffolding Phase**: Create app structure, manifest.yml
3. **Partial Development**: Begin UI and Functions development
4. **CLI State Establishment**:
   - `foundry ui run` server active
   - Profile authenticated and validated
   - Development build processes running

**Generate Handoff (Session 1 End):**

Document current CLI state, manifest configuration, development progress, and next steps.

**Expected Handoff Content:**
- [ ] Current development phase and progress
- [ ] Active CLI state (profile, server status)
- [ ] Manifest configuration and capabilities
- [ ] File structure and dependencies
- [ ] Next steps and continuation plan

### Session 2: Resume Development
**Resume from handoff:**
```
# Load handoff context and continue development
[Context from handoff statement provides continuation instructions]
```

**Expected Session 2 Behavior:**
1. **Context Recovery**: Restore understanding of project state
2. **CLI State Validation**: Verify profile, restart servers if needed
3. **Development Continuation**: Resume from exact point left off
4. **Integration Preservation**: Maintain TDD workflow and quality

**Continue Development:**
- Complete Functions implementation
- Finish UI components
- Test integration between capabilities

### Session 3: Final Integration
**Continue to completion:**
```
# Continue based on Session 2 state
```

**Expected Session 3 Behavior:**
1. **Integration Testing**: Complete end-to-end functionality
2. **Deployment Preparation**: Validate manifest and OAuth scopes
3. **Release Process**: Deploy and release to catalog
4. **Project Completion**: Generate final documentation

## Verification Criteria

### Handoff Quality
- [ ] **Context Completeness**: All relevant project state captured
- [ ] **CLI State Documentation**: Profile, servers, authentication status
- [ ] **Progress Tracking**: Clear indication of completed vs. remaining work
- [ ] **File Structure**: Current project layout and key files
- [ ] **Dependencies**: Required tools, packages, configurations
- [ ] **Next Steps**: Specific, actionable continuation instructions

### State Preservation
- [ ] **Project Understanding**: New session understands project goals
- [ ] **Technical Context**: Architecture decisions and patterns preserved
- [ ] **Quality Standards**: TDD methodology maintained across sessions
- [ ] **CLI Integration**: Profile and server state properly restored

### Continuation Effectiveness
- [ ] **Immediate Productivity**: Can resume work without re-discovery
- [ ] **No Duplicate Work**: Doesn't repeat already completed tasks
- [ ] **Quality Consistency**: Maintains same development standards
- [ ] **Integration Success**: Components work together properly

### Session Boundaries
- [ ] **Clean Handoffs**: Sessions end at logical breakpoints
- [ ] **Complete Transfers**: All necessary context transferred
- [ ] **Restart Capability**: New sessions can start immediately
- [ ] **State Validation**: Can verify and correct any state drift

## Test Scenarios

### Scenario A: Mid-Development Handoff
- **Trigger Point**: During UI component development
- **State Elements**: Partial code, active servers, authentication
- **Recovery Test**: Resume UI development seamlessly
- **Success Criteria**: No lost work, servers restart properly

### Scenario B: Pre-Deployment Handoff
- **Trigger Point**: After development, before testing
- **State Elements**: Complete code, ready for deployment
- **Recovery Test**: Execute deployment and testing phase
- **Success Criteria**: Deployment works without reconfiguration

### Scenario C: Error State Handoff
- **Trigger Point**: During debugging workflow
- **State Elements**: Error diagnosis, partial recovery
- **Recovery Test**: Continue debugging and implement solutions
- **Success Criteria**: Error resolution continues smoothly

### Scenario D: Multi-Day Development
- **Trigger Point**: End of work day with partial progress
- **State Elements**: Mixed completion states across capabilities
- **Recovery Test**: Resume next day with full context
- **Success Criteria**: No time lost on re-orientation

## Technical Requirements

### CLI State Capture
```bash
# Handoff should document:
foundry profile list           # Current profile
ps aux | grep "foundry ui"     # Server processes
ls -la manifest.yml           # Project configuration
git status                    # Version control state
```

### Project State Documentation
- **Manifest Configuration**: Current OAuth scopes and capabilities
- **File Structure**: Created directories and key files
- **Dependencies**: Installed packages and versions
- **Build State**: Current build configuration and status

### Continuation Instructions
- **Immediate Next Steps**: Specific tasks to resume work
- **Context Restoration**: Commands to restore CLI/server state
- **Validation Steps**: How to verify everything is working
- **Integration Points**: Where different capabilities connect

## Success Metrics

### Handoff Generation
- **Completeness Score**: All critical state elements included
- **Clarity Score**: Instructions are clear and actionable
- **Accuracy Score**: State description matches reality

### Session Transitions
- **Resume Time**: How long to get back to productive work
- **Context Loss**: Amount of re-discovery required
- **Error Recovery**: Ability to handle state drift or changes

### Development Continuity
- **Quality Maintenance**: TDD and other standards preserved
- **Integration Success**: Components still work together
- **Progress Preservation**: No duplicate or lost work

## Expected Outcomes
- Handoff statements enable seamless session transitions
- CLI state restoration is reliable and predictable
- Development quality and progress are preserved
- Multi-session development feels like continuous work
