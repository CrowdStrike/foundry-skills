# Performance Optimization and Token Management

## Context Efficiency Patterns
- **Precise Sub-Skill Invocation**: Provide exact context requirements to sub-skills
- **Minimal Context Transfer**: Transfer only essential information between skill phases
- **Batched Operations**: Group related CLI commands and file operations
- **Targeted Tool Usage**: Use specific tools rather than broad exploration

## Token-Efficient Delegation
- **Capability-Specific Context**: Send only relevant requirements to each sub-skill
- **Incremental Context Building**: Build context progressively rather than front-loading
- **Focused Scope Transfer**: Limit sub-skill context to their specific domain
- **Efficient Handoff Generation**: Create precise handoff statements without redundancy

## CLI Command Optimization
- **Profile Management**: Cache profile status to avoid repeated validation
- **Server State Coordination**: Maintain single `foundry ui run` instance across phases
- **Batch Command Execution**: Group related Foundry CLI operations
- **State Verification Efficiency**: Use targeted commands for CLI state validation

## Resource Management
- **Memory Usage**: Limit concurrent sub-skill execution to prevent context bloat
- **Process Management**: Coordinate CLI processes to avoid conflicts
- **File Operation Batching**: Group file reads/writes for efficiency
- **Context Cleanup**: Release unused context between development phases

## Performance Targets
- **Orchestrator Startup**: < 30 seconds to begin productive delegation
- **Sub-Skill Invocation**: < 45 seconds per capability development phase
- **CLI State Management**: < 10 seconds for profile/server validation
- **Context Transfer**: < 60 seconds for complete cross-session handoff
- **Token Usage**: < 25K tokens for complete multi-capability app lifecycle

## Efficiency Monitoring
- Track context usage across skill invocations
- Monitor CLI command execution patterns
- Measure sub-skill delegation overhead
- Optimize based on actual usage patterns
