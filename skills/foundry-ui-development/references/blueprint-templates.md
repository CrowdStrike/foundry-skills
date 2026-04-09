# Blueprint Templates

The Foundry CLI scaffolds UI pages and extensions from these blueprints. Since the output is deterministic, **use the Write tool to overwrite files directly instead of Read→Edit.** This eliminates 5-7 Read calls per run.

## Vanilla JS Blueprint (`--from-template "Vanilla JS"`)

Only 2 source files. No build dependencies, no vite config, no npm install, no npm run build needed.

**src/index.html:**
```html
<!DOCTYPE html>
<html lang="en">
  <head>
    <title>Hello World</title>
    <script type="importmap">
      {
        "imports": {
          "@crowdstrike/foundry-js": "https://assets.foundry.crowdstrike.com/foundry-js@0.20.0/index.js"
        }
      }
    </script>
    <link rel="stylesheet" href="https://assets.foundry.crowdstrike.com/tailwind-toucan-base@5.0.0/toucan.css" />
  </head>
  <body class="bg-ground-floor">
    <div id="app">
      <h1 class="text-titles-and-attributes">Hello world loading...</h1>
    </div>
    <script src="./app.js" type="module"></script>
  </body>
</html>
```

**src/app.js:**
```javascript
import FalconApi from '@crowdstrike/foundry-js';

const falcon = new FalconApi();

(async () => {
  await falcon.connect();

  // your code goes here
  document.getElementById('app').innerHTML =
    '<h1 class="text-titles-and-attributes">Hello world loaded!</h1>';
})();
```

Vanilla JS does not need Vite, npm install, or npm run build. The importmap loads foundry-js from CDN. Deploy works with just the raw src/ files.

## React Blueprint (`--from-template React`)

Scaffolds a full React 19 app with routing, Shoelace, and Falcon API context.

### Dependencies (package.json)

```
@crowdstrike/falcon-shoelace: 0.4.0
@crowdstrike/foundry-js: 0.20.0
@crowdstrike/tailwind-toucan-base: 5.0.0
@shoelace-style/shoelace: 2.20.1
react: 19.2.1, react-dom: 19.2.1
react-router-dom: 7.13.0
vite: 7.1.12, @vitejs/plugin-react-swc: 3.11.0
```

### Files that work as-is (do NOT read or modify unless the user asks)

**vite.config.js** — turnkey. Do NOT read, modify, or "fix" this file. It already has `noAttr()`, `base: './'`, and `root: 'src'` — all correct. Changing any value breaks deploys.

**src/index.html** — already loads all CSS (Tailwind, Shoelace, styles.css) via link tags:
```html
<!DOCTYPE html>
<html lang="en" style="width: 100%; height: 100%">
<head>
  <title>React Blueprint for Foundry</title>
  <link rel="stylesheet" href="../node_modules/@crowdstrike/tailwind-toucan-base/index.css" />
  <link rel="stylesheet" href="../node_modules/@crowdstrike/falcon-shoelace/dist/style.css" />
  <link rel="stylesheet" href="./styles.css" />
  <script>
    // Fallback theme for local dev. FoundryJS sets theme-light/theme-dark
    // on <html> after connect(), but in local dev it may fail to connect.
    // Wait briefly, then apply system preference if no theme was set.
    setTimeout(() => {
      const h = document.documentElement;
      if (!h.classList.contains('theme-light') && !h.classList.contains('theme-dark')) {
        h.classList.add(matchMedia('(prefers-color-scheme: dark)').matches ? 'theme-dark' : 'theme-light');
      }
    }, 500);
  </script>
</head>
<body class="bg-ground-floor">
<div id="app"></div>
<script src="./app.jsx" type="module"></script>
</body>
</html>
```

**IMPORTANT:** Since `index.html` already loads `falcon-shoelace/dist/style.css` and `tailwind-toucan-base/index.css`, do NOT add CSS imports in JavaScript files. There is no `dist/themes/light.css` or `dist/themes/dark.css` — the single `dist/style.css` file includes everything.

**src/app.jsx** — sets up React Router, Falcon API context, renders routes:
```jsx
import React from "react";
import { HashRouter, Routes, Route, Outlet } from "react-router-dom";
import {
  useFalconApiContext,
  FalconApiProvider,
} from "./contexts/falcon-api-context";
import { Home } from "./routes/home";
import { About } from "./routes/about";
import ReactDOM from "react-dom/client";
import { TabNavigation } from "./components/navigation";

function Root() {
  return (
    <Routes>
      <Route
        element={
          <TabNavigation>
            <Outlet />
          </TabNavigation>
        }
      >
        <Route index path="/" element={<Home />} />
        <Route path="/about" element={<About />} />
      </Route>
    </Routes>
  );
}

function AppContent() {
  const { isInitialized } = useFalconApiContext();

  if (!isInitialized) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <div className="text-lg">Initializing Falcon API...</div>
      </div>
    );
  }

  return (
    <HashRouter>
      <Root />
    </HashRouter>
  );
}

function App() {
  return (
    <React.StrictMode>
      <FalconApiProvider>
        <AppContent />
      </FalconApiProvider>
    </React.StrictMode>
  );
}

const domContainer = document.querySelector("#app");
if (!domContainer) {
  throw new Error('Failed to find the app container element');
}
const root = ReactDOM.createRoot(domContainer);
root.render(<App />);
```

**src/contexts/falcon-api-context.js:**
```javascript
import FalconApi from '@crowdstrike/foundry-js';
import { createContext, useContext, useEffect, useMemo, useState } from 'react';

const FalconApiContext = createContext(null);

function FalconApiProvider({ children }) {
  const [isInitialized, setIsInitialized] = useState(false);
  const falcon = useMemo(() => new FalconApi(), []);
  const navigation = useMemo(() => falcon.isConnected ? falcon.navigation : undefined, [falcon.isConnected]);

  useEffect(() => {
    (async () => {
      try {
        await falcon.connect();
        setIsInitialized(true);
      } catch (error) {
        console.error('Failed to connect to Falcon API:', error);
        setIsInitialized(true);
      }
    })();
  }, [falcon]);

  return (
    <FalconApiContext.Provider value={{ falcon, navigation, isInitialized }}>
      {children}
    </FalconApiContext.Provider>
  );
}

function useFalconApiContext() {
  const context = useContext(FalconApiContext);
  if (!context) {
    throw new Error('useFalconApiContext must be used within a FalconApiProvider');
  }
  return context;
}

export { useFalconApiContext, FalconApiContext, FalconApiProvider };
```

**src/styles.css** — empty, for custom styles:
```css
/* app custom styles */
```

**src/components/navigation.jsx** — tab navigation using Shoelace:
```jsx
import React from "react";
import { useLocation } from "react-router-dom";
import { Link } from './link';
import {
  SlTab,
  SlTabGroup,
  SlTabPanel,
} from "@shoelace-style/shoelace/dist/react";

function TabNavigation({ children }) {
  const location = useLocation();

  return (
    <SlTabGroup>
      <SlTab active={location.pathname === "/"} slot="nav" panel="home">
        <Link className="no-underline" to="/">Home</Link>
      </SlTab>
      <SlTab active={location.pathname === "/about"} slot="nav" panel="about">
        <Link className="no-underline" to="/about">About</Link>
      </SlTab>
      <SlTabPanel name="home">{children}</SlTabPanel>
      <SlTabPanel name="about">{children}</SlTabPanel>
    </SlTabGroup>
  );
}

export { TabNavigation };
```

**src/components/link.jsx** — wrapper for React Router + Falcon navigation:
```jsx
import React, { useContext } from "react";
import { Link as ReactRouterLink } from "react-router-dom";
import { FalconApiContext } from "../contexts/falcon-api-context";

function Link({ children, useFalconNavigation = false, to, openInNewTab = false }) {
  const { falcon, navigation } = useContext(FalconApiContext);
  const absolutePath = falcon.bridge.targetOrigin.concat(to);

  const onClick = (e) => {
    e.preventDefault();
    navigation?.navigateTo({ path: to, type: "falcon", target: openInNewTab ? "_blank" : "_self" });
  };
  if (useFalconNavigation) {
    return <a onClick={onClick} href={absolutePath}>{children}</a>;
  }
  return <ReactRouterLink to={to}>{children}</ReactRouterLink>;
}

export { Link };
```

### File to overwrite with app-specific code

**src/routes/home.jsx** — the only file you typically need to replace:
```jsx
import React, { useContext } from "react";
import { FalconApiContext } from "../contexts/falcon-api-context";

function Home() {
  const { falcon } = useContext(FalconApiContext);

  return (
    <div className="mt-4 space-y-8">
       <p className="text-neutral">Hello {falcon.data.user.username}</p>
    </div>
  );
}

export { Home };
```

### Shoelace React Component Imports

Import Shoelace React wrappers from `@shoelace-style/shoelace/dist/react`:

```jsx
import { SlButton, SlInput, SlDetails, SlTab, SlTabGroup, SlTabPanel, SlSpinner }
  from "@shoelace-style/shoelace/dist/react";
```

### Calling API Integrations from React

```jsx
import React, { useState, useEffect, useContext } from "react";
import { FalconApiContext } from "../contexts/falcon-api-context";

function Home() {
  const { falcon } = useContext(FalconApiContext);
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    (async () => {
      const api = falcon.apiIntegration({
        definitionId: 'VendorName',   // matches name in manifest.yml api_integrations
        operationId: 'operationName'  // matches operationId in OpenAPI spec
      });
      const response = await api.execute({ request: { params: {} } });
      if (response.errors?.length > 0) {
        setError(response.errors[0].message);
      } else {
        setData(response.resources?.[0]?.response_body);
      }
      setLoading(false);
    })();
  }, [falcon]);

  if (loading) return <p>Loading...</p>;
  if (error) return <p className="text-critical">Error: {error}</p>;
  return <pre>{JSON.stringify(data, null, 2)}</pre>;
}

export { Home };
```

## Which Template to Use

| Scenario | Template | Why |
|----------|----------|-----|
| Simple data display, no complex state | Vanilla JS | No build step, 2 files, fastest to deploy |
| Complex UI with multiple views/state | React | Router, context, component composition |
| User didn't specify | React | Most sample apps use React |

## Editing Strategy

1. After `foundry ui extensions create`, do NOT touch `vite.config.js` or `manifest.yml` — they are correct as scaffolded
2. Replace `src/routes/home.jsx` with the actual UI code (API integration call, data display)
3. All other files (`app.jsx`, `index.html`, `falcon-api-context.js`, `package.json`, `vite.config.js`, `styles.css`, `link.jsx`, `navigation.jsx`) work as scaffolded — do not touch them
4. Run `npm install && npm run build` once — if the build fails, check import paths against this reference before editing
