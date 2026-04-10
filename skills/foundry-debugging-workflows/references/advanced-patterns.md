# Advanced Debugging Patterns Reference

> Parent skill: [foundry-debugging-workflows](../SKILL.md)

## Performance Optimization

### Efficient Diagnostic Procedures
- Start with fastest diagnostic commands first
- Use targeted CLI commands instead of broad exploration
- Batch related CLI operations to minimize overhead
- Cache CLI authentication status to avoid repeated checks

### Resource-Efficient Debugging
- Focus on specific error categories to avoid context bloat
- Use minimal reproduction cases for testing
- Implement systematic rather than trial-and-error approaches
- Limit concurrent debugging sessions to prevent resource conflicts

### Context Management for Debugging
- Maintain focused scope on specific error patterns
- Use precise tool invocation rather than broad exploration
- Document findings efficiently to avoid re-investigation
- Preserve debugging context for cross-session continuity

### CLI Command Optimization
- Use `foundry` command flags to get specific information
- Batch CLI operations where possible (e.g., profile + auth status)
- Avoid redundant validation commands during debugging
- Implement efficient error recovery without excessive CLI calls

## Integration with Support Resources

### Documentation Links
- [Foundry CLI Reference](https://falcon.crowdstrike.com/foundry/docs/cli)
- [Manifest Schema](https://falcon.crowdstrike.com/foundry/docs/manifest)
- [API Documentation](https://falcon.crowdstrike.com/foundry/docs/api)

### Community Resources
- GitHub Issues: Common problem patterns
- [Foundry Developer Forum](https://community.crowdstrike.com/forums/foundry-developer-forum-35): Community debugging help
- Support Portal: Enterprise issue escalation

### Escalation Paths
1. **Level 1**: CLI `--help` and local documentation
2. **Level 2**: Community forums and GitHub issues
3. **Level 3**: CrowdStrike support portal
4. **Level 4**: Engineering escalation (critical bugs)
