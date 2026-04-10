# SOC Dashboard - UI Only App Template

A simple security operations dashboard that provides real-time visibility into detection data through a clean web interface.

## App Structure

```
soc-dashboard/
├── manifest.yml          # Configuration below
├── ui/
│   └── pages/
│       └── dashboard/
│           ├── index.html
│           ├── dashboard.js
│           └── dashboard.css
└── README.md
```

## Manifest Configuration

```yaml
name: soc-dashboard
version: "1.0.0"
description: "Real-time SOC dashboard for detection monitoring"

# UI Pages - Standalone web application
ui:
  pages:
    - name: dashboard
      path: "/dashboard"
      title: "SOC Dashboard"
      description: "Real-time security operations dashboard"
      entrypoint: "ui/pages/dashboard/index.html"

# Minimal OAuth scopes for reading detection data
oauth:
  scopes:
    - "falcon-oauth:read"
    - "detects:read"

# App metadata
author: "Security Team"
tags: ["monitoring", "dashboard", "detections"]
category: "security-operations"
```

## Key Features

- **Single page application** with Vue.js/React framework
- **CrowdStrike Falcon integration** for detection data
- **Responsive design** using Shoelace components
- **Real-time updates** via API polling
- **Minimal permissions** - read-only access to detections

## Development Commands

```bash
# Create app from template
foundry apps create --template=soc-dashboard

# Local development
foundry ui run
npm run dev

# Deploy to cloud
foundry apps deploy
```

## Customization Points

- **App name and branding** in manifest.yml
- **Dashboard layout** in ui/pages/dashboard/
- **Data refresh intervals** in dashboard.js
- **Color scheme and styling** in dashboard.css
