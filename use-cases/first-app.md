---
name: first-app
description: Build and deploy a first Falcon Foundry app from scratch using the CLI or App Builder UI
source:
  - https://www.crowdstrike.com/tech-hub/ng-siem/a-practical-guide-to-building-a-falcon-foundry-app-for-the-first-time/
  - https://www.crowdstrike.com/tech-hub/ng-siem/deploy-a-foundry-app-template-in-5-easy-steps/
skills: [development-workflow]
capabilities: [ui-extension, ui-page]
---

## When to Use

User wants to create their first Falcon Foundry app, scaffold a new app from scratch, deploy a pre-built app template, or learn the full app lifecycle (create, deploy, release, install).

## Pattern

### Path A: Build from Scratch with CLI

1. **Authenticate**: `foundry login` to set up a CLI profile with API credentials.
2. **Create app**: `foundry apps create --name "My App" --no-prompt --no-git` generates `manifest.yml`.
3. **Add a UI capability** (extension or page):
   - Extension: `foundry ui extensions create --name "X" --from-template React --sockets "socket.name" --no-prompt`
   - Page: `foundry ui pages create --name "X" --from-template React --no-prompt`
   - Then add navigation: `foundry ui navigation add --name "X" --path / --ref pages.xxx`
4. **Run locally**: `foundry ui run` starts local dev server on port 25678. Enable Development mode in Falcon console via the `</>` icon.
5. **Deploy**: `foundry apps deploy --change-type Major --change-log "Initial deployment" --no-prompt`
6. **Preview**: Toggle Preview mode on in the `</>` Developer tools to verify deployed app before release.
7. **Release**: `foundry apps release --change-type Major --deployment-id <id> --notes "Initial release" --no-prompt`
8. **Install**: Go to Foundry > App catalog, find the app, and Install.

### Path B: Deploy a Pre-Built Template

1. **Browse templates**: Fusion SOAR > Content library, search for the template.
2. **Deploy**: Click the template tile > Deploy in Foundry > Deploy.
3. **Release**: Click Release from the App overview screen.
4. **Install**: View in App catalog > Install now > configure credentials.
5. **Test operations**: Foundry > App manager > Edit app > test API operations.
6. **Use in workflows**: Fusion SOAR > Workflows > add template actions.

Templates are "source available" -- after deploying, you can edit API integrations, add dashboards, functions, etc. Use `foundry apps sync` to pull code locally.

## Key Code

```bash
# Full CLI lifecycle
foundry login
foundry apps create --name "my-app" --no-prompt --no-git
cd my-app
foundry ui extensions create --name "My Extension" \
  --from-template React --sockets "Endpoint detection details" --no-prompt

# Local development
foundry ui run

# Deploy, release, install
foundry apps deploy \
  --change-type Major --change-log "Initial deployment" --no-prompt
foundry apps release \
  --change-type Major --deployment-id <id> --notes "v1.0" --no-prompt
```

```yaml
# manifest.yml structure after scaffolding
name: my-app
description: My First Foundry app
ui:
  extensions:
    - name: My Extension
      sockets:
        - Endpoint detection details
```

## Gotchas

- **Name collisions**: If deployment fails with "name already exists", change the name in `manifest.yml`.
- **Version semantics**: Minor and patch releases auto-install. Major releases require manual acceptance in App catalog.
- **Development mode**: Must toggle on the `</>` icon in Falcon console navbar to see locally-running extensions.
- **Dev CID testing**: Developer CIDs may lack detections/incidents. Create test detections or use a CID that has them.
- **Template vs Store app**: Templates are editable in Foundry; Store apps are closed source. Templates give you flexibility to customize shared actions.
- **Angular routing**: If using Angular, Foundry modifies the HTML `<base>` tag, breaking push-based routing. Use hash-based routing or delete the `<base>` tag.
- **Sockets**: Extensions render in predefined locations (sockets) within the Falcon console. Choose the correct socket for your target page.
