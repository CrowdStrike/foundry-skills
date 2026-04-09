# Error Recovery and Debugging Test Scenario

## Scenario Description
Test systematic error recovery and debugging workflows for common Foundry development failures.

## Test Objective
Verify the debugging workflows can systematically diagnose and recover from common failure patterns.

## Test Scenarios

### Scenario A: Manifest Validation Failures

**Trigger:**
```
/foundry-debugging-workflows "app deployment failing with manifest schema validation errors"
```

**Expected Debugging Flow:**
1. **CLI Health Check**
   - [ ] Verify `foundry profile list` shows active profile
   - [ ] Validate authentication status
   - [ ] Check CLI version compatibility

2. **Manifest Analysis**
   - [ ] JSON schema validation against Foundry manifest spec
   - [ ] OAuth scope conflict detection
   - [ ] File path validation (referenced files exist)

3. **Step-by-Step Isolation**
   - [ ] Test individual capability sections
   - [ ] Identify specific validation failures
   - [ ] Provide targeted error explanations

4. **Recovery Strategy**
   - [ ] Incremental manifest rebuilding
   - [ ] Scope conflict resolution
   - [ ] File structure corrections

### Scenario B: Falcon API Integration Failures

**Trigger:**
```
/foundry-debugging-workflows "falcon api calls returning 403 forbidden in functions"
```

**Expected Debugging Flow:**
1. **Scope Verification**
   - [ ] Compare manifest OAuth scopes to API requirements
   - [ ] Identify missing or incorrect scopes
   - [ ] Check scope syntax and formatting

2. **Profile Validation**
   - [ ] Verify correct environment (US-1, US-2, EU-1, etc.)
   - [ ] Validate profile permissions and access levels
   - [ ] Check authentication token validity

3. **API Testing**
   - [ ] Isolate API calls outside Functions context
   - [ ] Test with minimal API client
   - [ ] Verify endpoint URLs and parameters

4. **Integration Recovery**
   - [ ] Update manifest with correct scopes
   - [ ] Re-deploy with proper authentication
   - [ ] Validate complete API integration flow

### Scenario C: Development Server Issues

**Trigger:**
```
/foundry-debugging-workflows "foundry ui run server not starting, port conflicts"
```

**Expected Debugging Flow:**
1. **Port Conflict Detection**
   - [ ] Identify processes using ports 3000-3010
   - [ ] Check for existing `foundry ui run` instances
   - [ ] Detect other development servers

2. **Server Health Check**
   - [ ] Validate Foundry CLI installation
   - [ ] Check Node.js/npm dependencies
   - [ ] Verify project structure requirements

3. **Resolution Steps**
   - [ ] Kill conflicting processes safely
   - [ ] Start server on alternative port
   - [ ] Update console development mode configuration

4. **Prevention Strategies**
   - [ ] Server lifecycle management patterns
   - [ ] Automated port selection
   - [ ] Health monitoring during development

### Scenario D: Cross-Session Handoff Recovery

**Trigger:**
```
/foundry-debugging-workflows "handoff context missing CLI state and development server"
```

**Expected Debugging Flow:**
1. **State Assessment**
   - [ ] Check CLI profile status and authentication
   - [ ] Identify missing development server processes
   - [ ] Assess project state vs. handoff expectations

2. **Context Recovery**
   - [ ] Restore CLI profile and authentication
   - [ ] Restart development servers in proper state
   - [ ] Validate project structure and dependencies

3. **Continuity Verification**
   - [ ] Test basic CLI operations
   - [ ] Verify UI development server functionality
   - [ ] Confirm API integration still works

4. **Handoff Improvement**
   - [ ] Identify gaps in handoff generation
   - [ ] Suggest improvements for future handoffs
   - [ ] Document state requirements

## Verification Criteria

### Debugging Skill Loading
- [ ] `foundry-debugging-workflows` skill loads without errors
- [ ] Contains systematic procedures for each error category
- [ ] Provides clear step-by-step instructions
- [ ] Includes recovery and rollback strategies

### Error Pattern Recognition
- [ ] Correctly identifies CLI issues vs. manifest issues vs. API issues
- [ ] Provides targeted diagnostics for each category
- [ ] Maps error symptoms to root causes
- [ ] Offers multiple resolution paths when appropriate

### Recovery Effectiveness
- [ ] Debugging procedures actually resolve the issues
- [ ] Recovery strategies don't introduce new problems
- [ ] Solutions are sustainable (not just temporary fixes)
- [ ] Includes prevention guidance for future development

### Integration with Main Workflow
- [ ] Main orchestrator properly delegates debugging scenarios
- [ ] Debugging skill integrates with other sub-skills
- [ ] Recovery procedures maintain TDD discipline
- [ ] Solutions preserve existing working functionality

## Success Criteria

### Systematic Approach
1. **Diagnosis Phase**: Identifies root cause systematically
2. **Isolation Phase**: Separates symptoms from causes
3. **Recovery Phase**: Implements targeted solutions
4. **Prevention Phase**: Provides guidance to avoid recurrence

### Error Categories Covered
- [ ] CLI and Profile Issues
- [ ] Manifest Validation Errors
- [ ] API Integration Problems
- [ ] Development Server Conflicts
- [ ] Build and Deployment Failures
- [ ] Cross-Session State Loss

### Quality Standards
- [ ] Debugging procedures are complete and accurate
- [ ] Error messages are clear and actionable
- [ ] Recovery steps are specific and verifiable
- [ ] Integration with TDD workflow is preserved

## Failure Recovery Testing

### Inject Common Failures
1. **Corrupt manifest.yml**: Test schema validation recovery
2. **Wrong OAuth scopes**: Test API permission debugging
3. **Port conflicts**: Test development server recovery
4. **Authentication expiry**: Test profile refresh procedures

### Measure Recovery Success
- [ ] Time to diagnosis (should be < 2 minutes)
- [ ] Solution effectiveness (should resolve issue completely)
- [ ] Prevention guidance quality (should reduce recurrence)
- [ ] Integration preservation (TDD workflow maintained)

## Expected Outcomes
- Debugging workflows handle all common failure patterns
- Recovery procedures are systematic and reliable
- Integration with main orchestrator is seamless
- Error prevention guidance improves development experience
