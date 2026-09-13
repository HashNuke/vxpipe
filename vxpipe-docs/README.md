# vxpipe-docs

One Astro project for the Vxpipe landing page and documentation, using the minimal
starter. Use Node.js 24 and npm.

## Develop

From the repository root:

```shell
cd vxpipe-docs
npm ci
npm run dev
```

Open the local URL printed by Astro, normally `http://localhost:4321`.

## Routes

| URL | Source | Purpose |
| --- | --- | --- |
| `/` | `src/pages/index.astro` | Landing page |
| `/docs/en/` | `src/pages/docs/en/index.astro` | English documentation |
| `/docs/` | Redirect in `astro.config.mjs` | Default to English |

Documentation pages belong under `src/pages/docs/<lang>/`. English (`en`) keeps
its language prefix even as the default. The shared HTML shell is
`src/layouts/Page.astro`. The pages are starter placeholders; no documentation
theme or archived content has been added.

## Build and preview

From this directory:

```shell
npm run build
npm run preview
```

The static site is generated in `dist/`. Astro emits an HTML redirect for `/docs/`
in a static build; the development server also handles the configured redirect.
