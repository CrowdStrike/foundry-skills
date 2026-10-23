# Shoelace Component Reference for Foundry UI

## Component Import Pattern

Import individual Shoelace components to keep bundle size small:

```typescript
// Import only what you use
import '@shoelace-style/shoelace/dist/components/button/button.js';
import '@shoelace-style/shoelace/dist/components/card/card.js';
import '@shoelace-style/shoelace/dist/components/alert/alert.js';
import '@shoelace-style/shoelace/dist/components/spinner/spinner.js';
import '@shoelace-style/shoelace/dist/components/badge/badge.js';
import '@shoelace-style/shoelace/dist/components/details/details.js';
import '@shoelace-style/shoelace/dist/components/tag/tag.js';
import '@shoelace-style/shoelace/dist/components/icon/icon.js';
import '@shoelace-style/shoelace/dist/components/input/input.js';
import '@shoelace-style/shoelace/dist/components/select/select.js';
import '@shoelace-style/shoelace/dist/components/option/option.js';
import '@shoelace-style/shoelace/dist/components/dialog/dialog.js';
import '@shoelace-style/shoelace/dist/components/drawer/drawer.js';
import '@shoelace-style/shoelace/dist/components/tab-group/tab-group.js';
import '@shoelace-style/shoelace/dist/components/tab/tab.js';
import '@shoelace-style/shoelace/dist/components/tab-panel/tab-panel.js';
```

Set the base path for Shoelace icons and assets:

```typescript
import { setBasePath } from '@shoelace-style/shoelace/dist/utilities/base-path';
setBasePath('https://cdn.jsdelivr.net/npm/@shoelace-style/shoelace@2.x/dist/');
```

## Commonly Used Components

### Buttons

```html
<sl-button variant="primary">Primary Action</sl-button>
<sl-button variant="default">Secondary</sl-button>
<sl-button variant="danger">Delete</sl-button>
<sl-button loading>Processing...</sl-button>
<sl-button disabled>Disabled</sl-button>
<sl-button size="small">Small</sl-button>
```

### Cards

```html
<sl-card>
  <div slot="header">Card Title</div>
  Card content here.
  <div slot="footer">
    <sl-button variant="primary">Action</sl-button>
  </div>
</sl-card>
```

### Alerts

```html
<sl-alert variant="primary" open>Informational message.</sl-alert>
<sl-alert variant="success" open closable>Operation succeeded.</sl-alert>
<sl-alert variant="warning" open>Caution needed.</sl-alert>
<sl-alert variant="danger" open>Error occurred.</sl-alert>
```

### Form Inputs

```html
<sl-input label="Hostname" placeholder="Enter hostname" clearable>
  <sl-icon name="search" slot="prefix"></sl-icon>
</sl-input>

<sl-select label="Severity" placeholder="Select severity">
  <sl-option value="low">Low</sl-option>
  <sl-option value="medium">Medium</sl-option>
  <sl-option value="high">High</sl-option>
</sl-select>

<sl-textarea label="Description" rows="4" resize="auto"></sl-textarea>

<sl-checkbox>Enable notifications</sl-checkbox>

<sl-switch>Dark mode</sl-switch>
```

### Data Display

```html
<!-- Status indicators: falcon-shoelace does not style sl-badge or sl-tag (see below) -->
<span class="status status--danger">Critical</span>
```

```css
/* Toucan tokens follow the console theme */
.status { font-weight: 600; }
.status--danger { color: var(--critical); }
.status--warning { color: var(--medium); }
.status--success { color: var(--positive); }
```

```html

<!-- Spinners for loading states -->
<sl-spinner></sl-spinner>
<sl-spinner style="font-size: 3rem;"></sl-spinner>

<!-- Details/Accordion -->
<sl-details summary="Click to expand">
  Hidden content revealed on click.
</sl-details>
```

### Dialogs and Drawers

```html
<sl-dialog label="Confirm Action" class="dialog-confirm">
  Are you sure you want to proceed?
  <sl-button slot="footer" variant="primary">Confirm</sl-button>
</sl-dialog>

<sl-drawer label="Settings" placement="end">
  Drawer content here.
</sl-drawer>
```

Open/close programmatically:

```javascript
const dialog = document.querySelector('.dialog-confirm');
dialog.show();  // Open
dialog.hide();  // Close
```

**Dialogs follow the theme.** With falcon-shoelace 0.4.0 an `sl-dialog` panel is dark in dark mode (`#2c2c30`) with no overrides. If an older version or a custom panel shows white, set `--sl-panel-background-color: var(--ground-floor)` on the element.

**Guard dialog events with `event.target`.** `sl-show`, `sl-hide`, `sl-after-hide`, and `sl-request-close` bubble, so an `SlDetails`, `SlAlert`, or `SlDropdown` inside a dialog fires the dialog's handlers. An unguarded `onSlAfterHide={() => setOpen(false)}` closes the dialog when a details section inside it collapses:

```jsx
<SlDialog open={open}
  onSlAfterHide={(e) => { if (e.target === e.currentTarget) setOpen(false); }}
  onSlRequestClose={(e) => { if (e.target === e.currentTarget) setOpen(false); }}>
```

### Components falcon-shoelace doesn't style

falcon-shoelace 0.4.0 has no rules for `sl-tag` or `sl-badge`, and it doesn't define the `--sl-color-<variant>-*` tokens their variants use, so every variant renders the same: transparent background and body-text color (`variant="success"` and `variant="danger"` look identical). Use a styled `<span>`, or style `::part(base)` yourself with the console's own color tokens. Before using a component not shown in this file, check `@crowdstrike/falcon-shoelace/dist/style.css` for its tag name.

### Form control quirks

- **`sl-option` values can't contain spaces.** Shoelace replaces them with underscores and logs `Option values cannot include a space`, so `value="two words"` comes back as `two_words`. Use slugs.
- **`sl-radio-group` has two tab stops after a click.** The first radio keeps `tabindex="0"` while nothing is chosen, and clicking another radio gives that one `tabindex="0"` too without clearing the first. Arrow keys fix it. After the value changes, await the group's and radios' `updateComplete`, then set `tabindex` to `0` on the checked radio and `-1` on the rest.
- **`sl-radio` doesn't reflect `checked`.** It sets the `checked` property and `aria-checked`, never the attribute, so a `sl-radio[checked]` selector matches nothing. Select on `[aria-checked="true"]`.

### Tabs

```html
<sl-tab-group>
  <sl-tab slot="nav" panel="overview">Overview</sl-tab>
  <sl-tab slot="nav" panel="details">Details</sl-tab>
  <sl-tab slot="nav" panel="history">History</sl-tab>

  <sl-tab-panel name="overview">Overview content</sl-tab-panel>
  <sl-tab-panel name="details">Details content</sl-tab-panel>
  <sl-tab-panel name="history">History content</sl-tab-panel>
</sl-tab-group>
```

## Toast Notifications

```typescript
// utils/notifications.ts
export const showToast = (
  message: string,
  variant: 'primary' | 'success' | 'warning' | 'danger' = 'primary',
  duration = 3000
) => {
  const icons: Record<string, string> = {
    primary: 'info-circle',
    success: 'check2-circle',
    warning: 'exclamation-triangle',
    danger: 'exclamation-octagon',
  };

  const alert = Object.assign(document.createElement('sl-alert'), {
    variant,
    closable: true,
    duration,
    innerHTML: `
      <sl-icon name="${icons[variant] || 'info-circle'}" slot="icon"></sl-icon>
      ${escapeHtml(message)}
    `,
  });

  document.body.append(alert);
  return alert.toast();
};
```

## CSS Customization

Override Shoelace component styles using CSS parts and custom properties:

```css
/* Override card styling */
sl-card::part(base) {
  border: 1px solid var(--sl-color-neutral-200);
}

sl-card::part(header) {
  background: var(--sl-color-neutral-50);
}

/* Override button styling */
sl-button::part(base) {
  border-radius: var(--sl-border-radius-medium);
}

/* Override input styling */
sl-input::part(base) {
  border-color: var(--sl-color-neutral-300);
}

sl-input::part(base):focus-within {
  border-color: var(--sl-color-primary-500);
  box-shadow: 0 0 0 3px var(--sl-color-primary-100);
}
```

## React-Specific Shoelace Imports

React wraps Shoelace web components for proper event handling:

```tsx
import {
  SlButton,
  SlCard,
  SlAlert,
  SlSpinner,
  SlInput,
  SlSelect,
  SlOption,
  SlDialog,
  SlDetails,
  SlIcon,
} from '@shoelace-style/shoelace/dist/react';
```

Use these React wrappers instead of raw HTML tags (`<SlButton>` not `<sl-button>`) in JSX for correct event binding.

**Alternative: Raw web component tags** also work in React JSX (`<sl-button>`, `<sl-icon>`, etc.) for most use cases. React wrappers are only required when you need proper React event binding (e.g., `onSlChange` instead of `addEventListener`). For display-only or simple click-handler components, raw tags are simpler and avoid import overhead.
