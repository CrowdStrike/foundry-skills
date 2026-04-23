# Falcon Theming for Foundry UI

## falcon-shoelace Theme Package

All Foundry UI **must** use CrowdStrike's `falcon-shoelace` theme package, not vanilla Shoelace theming.

**Installation:**
```bash
npm install @crowdstrike/falcon-shoelace
```

**Why this matters:**
- Provides Falcon-specific design tokens (colors, spacing, typography)
- Tokens match the Falcon console's visual language
- Both dark and light mode variants are included
- Design tokens resolve correctly in both themes automatically

**WRONG -- vanilla Shoelace themes do not match Falcon console styling:**
```typescript
import '@shoelace-style/shoelace/dist/themes/light.css';
```

**CORRECT -- use falcon-shoelace:**
```typescript
import '@crowdstrike/falcon-shoelace/dist/themes/light.css';
import '@crowdstrike/falcon-shoelace/dist/themes/dark.css';
```

## Dark/Light Mode Support

The Falcon console supports both dark and light modes. Every Foundry app must respect the user's theme preference.

### Theme Detection Utility

```typescript
// utils/theme.ts
export const initFalconTheme = () => {
  const applyTheme = () => {
    // Check for Falcon console's theme class on document root
    const prefersDark = document.documentElement.classList.contains('sl-theme-dark') ||
                        document.body.classList.contains('dark-theme') ||
                        window.matchMedia('(prefers-color-scheme: dark)').matches;

    document.documentElement.classList.toggle('sl-theme-dark', prefersDark);
    document.documentElement.classList.toggle('sl-theme-light', !prefersDark);
  };

  // Watch for theme changes from Falcon console
  const observer = new MutationObserver(applyTheme);
  observer.observe(document.documentElement, {
    attributes: true,
    attributeFilter: ['class']
  });

  // Also watch body for some console versions
  observer.observe(document.body, {
    attributes: true,
    attributeFilter: ['class']
  });

  // Apply initial theme
  applyTheme();

  // Return cleanup function
  return () => observer.disconnect();
};
```

### Using in Vue

```typescript
// main.ts
import { initFalconTheme } from './utils/theme';
initFalconTheme();
```

### Using in React

```typescript
// App.tsx
import { useEffect } from 'react';
import { initFalconTheme } from './utils/theme';

export const App: React.FC = () => {
  useEffect(() => {
    return initFalconTheme();
  }, []);
  // ...
};
```

### Using with FalconApi SDK

The FalconApi SDK provides a simpler theme method:

```javascript
import FalconApi from '@crowdstrike/foundry-js';

const falcon = new FalconApi();
await falcon.connect();

const theme = await falcon.theme();
document.documentElement.classList.add(`sl-theme-${theme}`);
```

## Design Tokens

Use Shoelace CSS custom properties for all styling. These tokens automatically adapt to dark/light mode:

```css
/* CORRECT - uses design tokens */
.my-component {
  color: var(--sl-color-neutral-900);
  background: var(--sl-color-neutral-0);
  padding: var(--sl-spacing-medium);
  border-radius: var(--sl-border-radius-medium);
  font-size: var(--sl-font-size-medium);
}

/* WRONG - hardcoded values break in dark mode */
.my-component {
  color: #1a1a1a;
  background: #ffffff;
  padding: 16px;
}
```

### Token Reference

| Token Category | Examples | Purpose |
|----------------|----------|---------|
| `--sl-color-primary-*` | `--sl-color-primary-500`, `--sl-color-primary-600` | Brand/action colors |
| `--sl-color-neutral-*` | `--sl-color-neutral-0` through `--sl-color-neutral-900` | Text, backgrounds, borders |
| `--sl-color-danger-*` | `--sl-color-danger-500` | Error states |
| `--sl-color-warning-*` | `--sl-color-warning-500` | Warning states |
| `--sl-color-success-*` | `--sl-color-success-500` | Success states |
| `--sl-spacing-*` | `--sl-spacing-small`, `--sl-spacing-medium`, `--sl-spacing-large` | Consistent spacing |
| `--sl-font-size-*` | `--sl-font-size-small`, `--sl-font-size-medium`, `--sl-font-size-large` | Typography scale |
| `--sl-border-radius-*` | `--sl-border-radius-small`, `--sl-border-radius-medium` | Corner rounding |
| `--sl-shadow-*` | `--sl-shadow-small`, `--sl-shadow-medium`, `--sl-shadow-large` | Elevation |

### Neutral Color Scale (Dark/Light Mapping)

| Token | Light Mode | Dark Mode | Usage |
|-------|-----------|-----------|-------|
| `--sl-color-neutral-0` | White | Near-black | Page background |
| `--sl-color-neutral-50` | Very light gray | Dark gray | Card backgrounds |
| `--sl-color-neutral-200` | Light gray | Medium-dark gray | Borders |
| `--sl-color-neutral-500` | Medium gray | Medium gray | Secondary text |
| `--sl-color-neutral-700` | Dark gray | Light gray | Primary text |
| `--sl-color-neutral-900` | Near-black | White | Headings |

## Tailwind with Toucan (Alternative)

For projects using Tailwind CSS, use `tailwind-toucan-base` to get equivalent Toucan design tokens:

```bash
npm install @crowdstrike/tailwind-toucan-base
```

```javascript
// tailwind.config.js
module.exports = {
  presets: [
    require('@crowdstrike/tailwind-toucan-base')
  ],
};
```

**When to use:**
- Project already uses Tailwind CSS
- Building custom layouts beyond Shoelace components
- Team prefers utility-first CSS

`tailwind-toucan-base` provides design tokens for Tailwind utilities. If also using Shoelace components, still install `falcon-shoelace` for component theming. Both packages coexist.

**Prebuilt CSS limitations:** When using `tailwind-toucan-base/index.css` as a prebuilt stylesheet (without running Tailwind's build process), only the predefined utility classes are available. Arbitrary values like `max-h-[400px]`, `w-[36rem]`, or `grid-cols-[1fr_2fr]` will NOT work because they require Tailwind's JIT compiler. Use inline styles instead:

```jsx
// WRONG — arbitrary value not in prebuilt CSS
<div className="max-h-[400px] overflow-auto">

// CORRECT — use inline style for values not in prebuilt CSS
<div className="overflow-auto" style={{ maxHeight: "400px" }}>
```

**Reference:** [tailwind-toucan-base on GitHub](https://github.com/CrowdStrike/tailwind-toucan-base)

## Shoelace Icon CSP Requirements

When using `setBasePath()` to load Shoelace icons from CDN, the manifest's Content Security Policy must allow the CDN domain:

```yaml
# manifest.yml — under the page's content_security_policy
content_security_policy:
  connect-src:
    - cdn.jsdelivr.net
  img-src:
    - cdn.jsdelivr.net
```

Without these CSP entries, Shoelace icons will fail to load silently (no console error, just missing icons).
