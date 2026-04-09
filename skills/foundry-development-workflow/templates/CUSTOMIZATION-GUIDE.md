# Foundry App Template Customization Guide

This guide explains how to customize and parameterize Foundry app templates for specific use cases.

## Template Structure

Each template includes:
- **Manifest Configuration** - Complete `manifest.yml` example
- **File Structure** - Recommended project organization
- **Schema Definitions** - JSON schemas for Collections
- **Development Commands** - CLI usage patterns
- **Customization Points** - Areas for modification

## Parameterization Strategy

### App Naming and Branding
```yaml
# In manifest.yml
name: "{{APP_NAME}}"                    # Replace with your app name
description: "{{APP_DESCRIPTION}}"       # Replace with your description
author: "{{AUTHOR_NAME}}"               # Replace with your team name
```

### OAuth Scope Selection

**Minimal Scopes (Read-Only)**
```yaml
oauth:
  scopes:
    - "falcon-oauth:read"     # Required for all apps
    - "detects:read"          # Detection data access
```

**Standard Scopes (Read/Write Operations)**
```yaml
oauth:
  scopes:
    - "falcon-oauth:read"
    - "detects:read"
    - "incidents:read"
    - "incidents:write"       # Case management
    - "hosts:read"            # Host information
```

**Advanced Scopes (Full Platform Access)**
```yaml
oauth:
  scopes:
    - "falcon-oauth:read"
    - "detects:read"
    - "incidents:read"
    - "incidents:write"
    - "hosts:read"
    - "iocs:read"             # Threat intelligence
    - "rtr:read"              # Real-time response
    - "rtr:write"             # RTR execution
    - "users:read"            # User management
```

### Capability Selection

**UI-Only Configuration**
```yaml
# Remove sections not needed
# functions: (remove)
# collections: (remove)
# workflows: (remove)

ui:
  pages:
    - name: "{{PAGE_NAME}}"
      path: "/{{PAGE_PATH}}"
```

**Backend-Only Configuration**
```yaml
# Remove sections not needed
# ui: (remove)
# workflows: (remove if not needed)

functions:
  - name: "{{FUNCTION_NAME}}"
    path: "/api/{{ENDPOINT_PATH}}"

collections:
  - name: "{{COLLECTION_NAME}}"
    schema: "{{SCHEMA_FILE}}"
```

**Full-Stack Configuration**
```yaml
# Include all capabilities
ui: {...}
functions: {...}
collections: {...}
workflows: {...}  # Optional
```

## Template Customization Workflow

### 1. Choose Base Template
- **soc-dashboard-ui-only** - Simple dashboards and reporting
- **automation-backend** - API services and data processing
- **investigation-console-full-stack** - Complete investigation workflows

### 2. App Configuration
```bash
# Copy template to new location
cp -r templates/soc-dashboard-ui-only.md my-security-app/

# Edit manifest.yml with your parameters
sed -i 's/{{APP_NAME}}/my-security-app/g' manifest.yml
sed -i 's/{{AUTHOR_NAME}}/My Team/g' manifest.yml
```

### 3. OAuth Scope Adjustment
Review and modify OAuth scopes based on:
- **Data Access Needs** - What CrowdStrike APIs will you use?
- **Permission Level** - Read-only vs read/write access?
- **Security Policy** - Minimal permissions principle

### 4. Capability Customization
Remove unused capabilities from manifest.yml:
```yaml
# Comment out or remove sections not needed
# functions: [...]  # Remove if no backend logic needed
# collections: [...] # Remove if no data storage needed
# workflows: [...]   # Remove if no automation needed
```

### 5. File Structure Setup
```bash
# Create project structure based on manifest
foundry apps create --from-manifest manifest.yml

# Or manually create directories
mkdir -p ui/pages/my-page
mkdir -p functions/my-function
mkdir -p collections/
```

## Common Customization Patterns

### Security Dashboard App
- **Base Template**: soc-dashboard-ui-only
- **OAuth Scopes**: detects:read, hosts:read
- **Customization**: Add charts, filters, real-time updates
- **File Structure**: Single page app with Vue/React

### Alert Processing Service
- **Base Template**: automation-backend
- **OAuth Scopes**: detects:read, incidents:write
- **Customization**: Alert parsing, enrichment logic
- **File Structure**: Functions for processing, Collections for state

### Investigation Platform
- **Base Template**: investigation-console-full-stack
- **OAuth Scopes**: Full investigation permissions
- **Customization**: Case management workflow, evidence tracking
- **File Structure**: Complete UI + backend + automation

### Integration Connector
- **Base Template**: automation-backend
- **OAuth Scopes**: Based on integration requirements
- **Customization**: External API connectors, data sync
- **File Structure**: Functions for API calls, Collections for mapping

## Validation and Testing

### Manifest Validation
```bash
# Validate OpenAPI specs locally
npx @redocly/cli lint api-integrations/MyApi.yaml

# Check OAuth scope compatibility
foundry auth scopes add
```

### Template Testing
```bash
# Test app creation from customized manifest
foundry apps create --from-manifest manifest.yml

# Test local development
foundry ui run
foundry functions test

# Test deployment
foundry apps deploy --dry-run
```

## Best Practices

### Security
- **Minimal Scopes** - Request only required permissions
- **Input Validation** - Validate all data inputs
- **Error Handling** - Don't expose sensitive information

### Performance
- **Efficient Queries** - Optimize Collection queries
- **Caching Strategy** - Cache frequently accessed data
- **Rate Limiting** - Respect API rate limits

### Maintainability
- **Clear Documentation** - Document customization decisions
- **Version Control** - Track manifest changes
- **Testing** - Validate all customizations

### User Experience
- **Consistent Design** - Use Shoelace design system
- **Responsive Layout** - Support multiple screen sizes
- **Error Messages** - Provide helpful user feedback

## Advanced Customization

### Multi-Environment Configuration
```yaml
# Use environment-specific manifests
manifest-dev.yml    # Development configuration
manifest-prod.yml   # Production configuration
```

### Dynamic Configuration
```yaml
# Use environment variables in manifest
name: "${APP_NAME:-default-app}"
oauth:
  scopes: "${OAUTH_SCOPES}".split(",")
```

### Template Extensions
Create organization-specific template variations:
```
templates/
├── base/                  # Standard templates
│   ├── soc-dashboard/
│   └── automation-backend/
└── custom/               # Organization-specific
    ├── compliance-reporter/
    └── threat-hunter/
```

This customization guide enables teams to efficiently adapt Foundry app templates to their specific security operations needs while maintaining best practices and platform integration patterns.
