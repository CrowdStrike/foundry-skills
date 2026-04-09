# Automation Backend - Functions + Collections Template

A serverless automation engine that processes security alerts and maintains investigation state using CrowdStrike APIs.

## App Structure

```
automation-backend/
├── manifest.yml              # Configuration below
├── functions/
│   ├── process-alerts/
│   │   └── main.py           # Alert processing logic
│   └── get-investigations/
│       └── main.py           # Investigation retrieval
├── collections/
│   ├── alert-tracking.json   # Alert state schema
│   └── investigations.json   # Investigation schema
└── README.md
```

## Manifest Configuration

```yaml
name: automation-backend
version: "1.0.0"
description: "Serverless backend for security alert automation"

# Functions - REST API endpoints
functions:
  - name: process-alerts
    description: "Process incoming security alerts"
    language: python
    path: "functions/process-alerts"
    max_exec_duration_seconds: 30
    handlers:
      - name: process
        method: POST
        path: "/api/alerts/process"

  - name: get-investigations
    description: "Retrieve investigation data"
    language: python
    path: "functions/get-investigations"
    handlers:
      - name: list
        method: GET
        path: "/api/investigations"

# Collections - Data storage
collections:
  - name: alert-tracking
    description: "Track alert processing state"
    schema: "collections/alert-tracking.json"

  - name: investigations
    description: "Investigation case data"
    schema: "collections/investigations.json"

# OAuth scopes for API access
oauth:
  scopes:
    - "falcon-oauth:read"
    - "detects:read"
    - "incidents:read"
    - "incidents:write"

# App metadata
author: "Automation Team"
tags: ["automation", "backend", "api"]
category: "automation"
```

## Collection Schemas

### Alert Tracking Schema
```json
{
  "type": "object",
  "properties": {
    "alert_id": {"type": "string"},
    "status": {"type": "string", "enum": ["new", "processing", "completed", "failed"]},
    "created_at": {"type": "string", "format": "date-time"},
    "updated_at": {"type": "string", "format": "date-time"},
    "metadata": {"type": "object"}
  },
  "required": ["alert_id", "status", "created_at"]
}
```

### Investigations Schema
```json
{
  "type": "object",
  "properties": {
    "investigation_id": {"type": "string"},
    "title": {"type": "string"},
    "severity": {"type": "string", "enum": ["low", "medium", "high", "critical"]},
    "status": {"type": "string", "enum": ["open", "in_progress", "resolved", "closed"]},
    "alerts": {"type": "array", "items": {"type": "string"}},
    "findings": {"type": "array"},
    "created_at": {"type": "string", "format": "date-time"}
  },
  "required": ["investigation_id", "title", "status", "created_at"]
}
```

## Key Features

- **Serverless Functions** in Python/Go for scalable processing
- **Structured Data Storage** with JSON Schema validation
- **CrowdStrike API Integration** for alert and incident data
- **RESTful API Design** for external integrations
- **State Management** through Collections

## Development Commands

```bash
# Create app from template
foundry apps create --template=automation-backend

# Local function testing (requires Docker)
foundry functions run

# Deploy to cloud
foundry apps deploy
```

## Customization Points

- **Processing Logic** in function implementations
- **Data Models** in collection schemas
- **API Endpoints** routes and methods
- **OAuth Scopes** based on required permissions
