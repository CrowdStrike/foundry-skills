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

**CORRECT -- use falcon-shoelace.** It ships one stylesheet, `dist/style.css`, that holds both themes (there is no `dist/themes/` folder):
```typescript
import '@crowdstrike/falcon-shoelace/dist/style.css';
```

## Dark/Light Mode Support

The Falcon console supports both dark and light modes. Every Foundry app must respect the user's theme preference.

### Theme Detection

`falcon.connect()` sets `theme-light` or `theme-dark` on `<html>` and swaps it live when the user changes the console theme, and `falcon-shoelace` styles off exactly those two classes. You don't need theme code for Shoelace components. Don't derive the theme from `prefers-color-scheme` or toggle `sl-theme-dark`: the console theme is independent of the OS setting, and `falcon-shoelace` never reads `sl-theme-*` classes (verified with falcon-shoelace 0.4.0, 2026-10-23). For your own CSS, key off `.theme-dark` or watch `<html>`'s class (see `SKILL.md`).

### Using with FalconApi SDK

With foundry-js there is nothing to call. `connect()` adds `theme-dark` or `theme-light` to `<html>` (from `falcon.data.theme`) and swaps it on every console theme change, and `@crowdstrike/falcon-shoelace` styles off exactly those classes. There is no `falcon.theme()` method.

```javascript
import FalconApi from '@crowdstrike/foundry-js';

const falcon = new FalconApi();
await falcon.connect();   // <html class="theme-dark"> or "theme-light" from here on
falcon.events.on('data', (data) => console.log('console theme is now', data.theme));
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

## Shoelace Icons and the CSP

The default page CSP already allows `https://cdn.jsdelivr.net` and `data:` in `connect-src`, even when the manifest's `connect-src` lists only `assets.foundry.crowdstrike.com` (observed on US-2, 2026-10-23). So `setBasePath('https://cdn.jsdelivr.net/npm/@shoelace-style/shoelace@2.x/dist/')` works with no manifest change, and the `system` icons Shoelace draws itself (dialog close button, select and dropdown carets, details chevrons) render, because they're `data:` URLs.

Don't serve icons from the app's own package. The deploy excludes every `.svg` file, and `connect-src` doesn't include the app's asset host, so a relative base path or a custom icon library pointing at `./icons/` fails with a `connect-src` violation. For a custom icon, inline the SVG markup.
