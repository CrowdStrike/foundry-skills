---
name: publishing-certified-apps
description: Publish a Foundry app to the app catalog as a certified app via the GitHub-based review workflow
source: https://www.crowdstrike.com/tech-hub/ng-siem/publishing-certified-apps-on-falcon-foundry/
skills: [development-workflow]
capabilities: []
---

## When to Use

User wants to distribute a Foundry app to other CrowdStrike customers or partners via the
app catalog, or asks about the certification/publishing process, review requirements, or
update workflow for certified apps.

## Pattern

### Prerequisites (all four required before publishing)

1. **Certified app creator access** -- submit a support ticket via the CrowdStrike Support Portal.
2. **GitHub account** with a verified email address (review happens via GitHub PRs).
3. **App must be deployed, released, AND installed** in your Falcon tenant first.
4. **Good documentation** -- include purpose, installation steps, and screenshots. No secrets or data files.

### Developer profile setup

1. Navigate to **Foundry > Developer profile** in the Falcon console.
2. Enter your organization name (appears in the app catalog).
3. Authorize GitHub access (creates private repos in the CrowdStrike-Foundry org).
4. Verify your email address via the confirmation link.

### Publication workflow

1. Navigate to **Foundry > App manager**, select your app.
2. Click **Publish latest release**.
3. Optionally toggle **Open source** to make the GitHub repo public.
4. Foundry creates a private GitHub repo and opens a PR with your app contents.
5. Track status: Pending Review > Review in Progress > Approved > Publishing > Successful.

### After approval

1. **Access is not automatic.** CrowdStrike controls visibility.
2. First enable for a few test CIDs to verify installation experience.
3. Then enable for all CIDs when ready for broad rollout.

### Publishing updates

1. Deploy, release, and install the new version in your tenant.
2. Click **Publish latest release** again -- a new PR is created in the same repo.
3. Same review cycle applies. Approved versions are immutable.
4. **Minor/patch updates** auto-apply to installed instances.
5. **Major updates** show "Update Available" and require user acceptance.

## Key Code

No code artifacts. This is a process/workflow pattern.

### Supported artifact types

All Foundry artifact types are supported **except RTR scripts**:
- Functions
- Workflows
- UI extensions
- Collections
- Falcon LogScale repositories

### Cross-cloud replication

Certified apps are replicated across: US-1, US-2, EU-1, Gov-1.

### Version numbering

Release versions (in app manager) are separate from publish versions (for global distribution).
Release v1.5 might become publish v2.

## Gotchas

- **RTR scripts are not supported** in certified apps. If your app uses RTR scripts, they will be excluded or block publication.
- **App must be installed, not just deployed.** Foundry gates on installation status. Deploy > Release > Install from app catalog before you can publish.
- **Review focuses on security**, not business logic. Reviewers check for vulnerabilities, appropriate API permissions, and customer risk. They won't deep-dive into your domain-specific logic.
- **Changes requested = full cycle.** If reviewers request changes, you must fix the code, then repeat the deploy/release/install/publish cycle. Changes appear in the same PR.
- **No secrets in app code.** Especially important if you toggle the open-source option. Scan your app package for API keys, credentials, and data files before publishing.
- **Test on a non-owner CID first.** Before broad rollout, verify the installation experience from a customer's perspective. Partners should work with their CrowdStrike account team.
- **GitHub email must be verified.** The publication process requires a verified email on your GitHub account.
- **Reference example**: [CrowdStrike-Foundry/chromeos-device-actions](https://github.com/CrowdStrike-Foundry/chromeos-device-actions) demonstrates the certified app workflow.
