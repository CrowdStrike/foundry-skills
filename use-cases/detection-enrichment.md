---
name: detection-enrichment
description: Enrich endpoint detection details with third-party API data using Foundry Extension Builder (no-code UI extensions)
source: https://www.crowdstrike.com/tech-hub/ng-siem/enrich-detections-with-falcon-foundry-extension-builder/
skills: [foundry-ui-development, foundry-functions-development]
capabilities: [ui-extension, function]
---

## When to Use

User wants to add contextual data (geolocation, threat intel, reputation scores) to the detection details panel, build a UI extension without writing code using the Extension Builder drag-and-drop interface, or display third-party API responses alongside Falcon detection data.

## Pattern

### 1. Create App and API Integration

1. Foundry > Home > Custom app. Name it and create.
2. In the App overview, click Start under Integrations > Create an API integration.
3. Select "Create API profile manually" (for APIs without an OpenAPI spec).
4. Configure the API profile:
   - Host protocol: `https`
   - Host: `ipgeolocation.abstractapi.com` (or your API's host)
   - Auth type: `API key`
   - API key parameter name: `api_key`
   - API key parameter location: `query`
5. Create an operation (e.g., `Get IP Location`, `GET /v1/`).
6. Add query parameters (e.g., `ip_address`).
7. Test with a temporary configuration and your API key.
8. **Generate response schema**: Copy test response body > Response > Response body > Generate schema. This step is critical for the Extension Builder to offer field selection.
9. **Deploy immediately** after adding the API integration.

### 2. Build the UI Extension with Extension Builder

1. Foundry > App overview > Experience > Create an extension.
2. Set extension location to a socket (e.g., `Endpoint detection details`).
3. Drag-and-drop UI components from the builder:

**Display contextual data (from the detection):**
- Drag a Container, then a Text component inside it.
- Set display text to `IP Address:` then Insert dynamic value.
- Data source: `activity.detections.details` > Variable: `Device, External_ip`.

**Display API enrichment data:**
- Drag a Label value component onto the canvas.
- Set labels (e.g., `City`, `Country`, `Timezone`).
- For each value, Insert dynamic value > select API integration > select operation > select field.
- Set the request parameter `query.ip_address` to `${contextual.device.external_ip}`.

1. Save the extension.

### 3. Deploy, Release, Install

1. Deploy with change type Major.
2. Release with change type Major.
3. View in App catalog > Install now.
4. Configure API credentials at install time (name + API key).

### 4. Verify

Navigate to Next-Gen SIEM > Detections. Click a detection, scroll to the extension section, expand it. The extension displays the IP address from detection context and the enrichment data from the third-party API.

## Key Code

```text
# Extension Builder dynamic value syntax for API request parameters
${contextual.device.external_ip}

# Data sources available in Extension Builder:
# 1. Extension contextual data - page metadata (detection details, host info)
# 2. API integration - response fields from configured operations
```

```bash
# Test the API before integrating
curl 'https://ipgeolocation.abstractapi.com/v1/?api_key={key}&ip_address={ip}'
```

```bash
# CLI alternative: create extension with code
foundry ui extensions create --name "IP Address Enrichment" \
  --from-template React --sockets "Endpoint detection details" --no-prompt
```

## Gotchas

- **Response schema required for field selection**: If you skip generating the response schema, the Extension Builder cannot offer individual fields from the API response. Always generate the schema from a real test response.
- **Deploy after API integration, before building UI**: The API integration must be deployed for the Extension Builder to reference its operations and fields.
- **Contextual data varies by socket**: The available `contextual.*` variables depend on which socket (extension location) you choose. `Endpoint detection details` provides `device.external_ip`, but other sockets provide different data.
- **Multiple API integrations**: A single app can include multiple API integrations (e.g., geolocation + VirusTotal). Use the Extension Builder's tabbed interface to display data from multiple sources.
- **API key at install time**: End users provide API credentials when installing the app from the App catalog, not at development time. The temporary test configuration is only for development.
- **Extension Builder vs CLI**: The Extension Builder creates no-code extensions via drag-and-drop. The CLI creates code-based extensions (React, Vanilla JS) for more complex UIs. Both render in the same sockets.
