# Investigation Console - Full-Stack App Template

Comprehensive security investigation platform combining UI, backend logic, data storage, and automated workflows.

## App Structure

```
investigation-console/
├── manifest.yml                    # Configuration below
├── ui/
│   ├── pages/
│   │   └── investigation-console/  # Main investigation interface
│   └── extensions/
│       └── alert-context/          # Context panel for alerts
├── functions/
│   ├── gather-evidence/
│   ├── update-investigation/
│   └── search-indicators/
├── collections/
│   ├── investigations.json         # Investigation case data
│   ├── evidence-items.json         # Evidence and artifacts
│   └── investigation-templates.json
├── workflows/
│   ├── auto-investigation.yml      # Automated investigation workflow
│   └── evidence-collection.yml     # Evidence gathering automation
└── README.md
```

## Manifest Configuration

```yaml
name: investigation-console
version: "1.0.0"
description: "Full-featured security investigation platform"

# UI Components
ui:
  pages:
    - name: investigation-console
      path: "/investigations"
      title: "Investigation Console"
      description: "Security investigation management interface"
      entrypoint: "ui/pages/investigation-console/index.html"

  extensions:
    - name: alert-context
      title: "Investigation Context"
      description: "Show related investigations for alerts"
      target: "detection-details"
      entrypoint: "ui/extensions/alert-context/index.html"

# Functions - Backend API
functions:
  - name: gather-evidence
    description: "Collect evidence from multiple sources"
    language: python
    path: "functions/gather-evidence"
    environment_variables:
      LOG_LEVEL: "info"
    max_exec_duration_seconds: 60
    max_exec_memory_mb: 256
    handlers:
      - name: collect
        method: POST
        path: "/api/investigations/{id}/evidence"

  - name: update-investigation
    description: "Update investigation status and findings"
    language: python
    path: "functions/update-investigation"
    handlers:
      - name: update
        method: PUT
        path: "/api/investigations/{id}"

  - name: search-indicators
    description: "Search for IOCs across CrowdStrike data"
    language: python
    path: "functions/search-indicators"
    handlers:
      - name: search
        method: GET
        path: "/api/indicators/search"

# Collections - Data Storage
collections:
  - name: investigations
    description: "Investigation case management"
    schema: "collections/investigations.json"

  - name: evidence-items
    description: "Evidence artifacts and metadata"
    schema: "collections/evidence-items.json"

  - name: investigation-templates
    description: "Investigation playbook templates"
    schema: "collections/investigation-templates.json"

# Workflows - Automation
workflows:
  - name: auto-investigation
    description: "Automated investigation workflow"
    template: "workflows/auto-investigation.yml"
    trigger: "detection-created"

  - name: evidence-collection
    description: "Automated evidence gathering"
    template: "workflows/evidence-collection.yml"
    trigger: "investigation-created"

# OAuth Scopes - Comprehensive permissions
oauth:
  scopes:
    - "falcon-oauth:read"
    - "detects:read"
    - "incidents:read"
    - "incidents:write"
    - "hosts:read"
    - "iocs:read"
    - "users:read"
    - "rtr:read"
    - "rtr:write"

# App metadata
author: "Security Operations Team"
tags: ["investigation", "full-stack", "automation", "soc"]
category: "security-operations"
```

## Collection Schemas

### Investigations Schema
```json
{
  "type": "object",
  "properties": {
    "investigation_id": {"type": "string"},
    "title": {"type": "string"},
    "description": {"type": "string"},
    "severity": {"type": "string", "enum": ["low", "medium", "high", "critical"]},
    "status": {"type": "string", "enum": ["open", "investigating", "resolved", "closed"]},
    "assignee": {"type": "string"},
    "alerts": {"type": "array", "items": {"type": "string"}},
    "evidence_items": {"type": "array", "items": {"type": "string"}},
    "timeline": {"type": "array"},
    "findings": {"type": "array"},
    "tags": {"type": "array", "items": {"type": "string"}},
    "created_at": {"type": "string", "format": "date-time"},
    "updated_at": {"type": "string", "format": "date-time"}
  },
  "required": ["investigation_id", "title", "status", "created_at"]
}
```

### Evidence Items Schema
```json
{
  "type": "object",
  "properties": {
    "evidence_id": {"type": "string"},
    "investigation_id": {"type": "string"},
    "type": {"type": "string", "enum": ["file", "network", "process", "registry", "artifact"]},
    "source": {"type": "string"},
    "description": {"type": "string"},
    "hash": {"type": "string"},
    "file_path": {"type": "string"},
    "metadata": {"type": "object"},
    "collected_at": {"type": "string", "format": "date-time"},
    "analyst": {"type": "string"}
  },
  "required": ["evidence_id", "investigation_id", "type", "collected_at"]
}
```

## Workflow Templates

### Auto-Investigation Workflow
```yaml
name: auto-investigation
description: "Automatically create investigation for high-severity alerts"

inputs:
  - name: alert_data
    type: object
    required: true

steps:
  - name: create_investigation
    function: update-investigation
    inputs:
      title: "Auto-Investigation: {{alert_data.description}}"
      severity: "{{alert_data.severity}}"
      alerts: ["{{alert_data.alert_id}}"]

  - name: gather_initial_evidence
    function: gather-evidence
    inputs:
      investigation_id: "{{create_investigation.investigation_id}}"
      sources: ["host_data", "network_logs", "process_tree"]

outputs:
  - investigation_id: "{{create_investigation.investigation_id}}"
```

## Key Features

- **Complete Investigation Workflow** from detection to resolution
- **Multi-Source Evidence Collection** automated via workflows
- **Interactive UI** with both standalone pages and console extensions
- **Template-Based Investigations** for consistent processes
- **Real-Time Collaboration** with assignment and status tracking
- **Comprehensive CrowdStrike Integration** across all API surfaces

## Development Commands

```bash
# Create app from template
foundry apps create --template=investigation-console

# Start all development services
foundry ui run &
npm run dev &
foundry workflows watch

# Deploy full stack
foundry apps deploy

# Monitor workflow execution
foundry workflows logs auto-investigation
```

## Customization Points

- **Investigation Process** in workflow templates
- **Evidence Types** in collection schemas
- **UI Layout and Features** in pages and extensions
- **Integration Sources** in evidence gathering functions
- **Automation Triggers** in workflow configuration
