# vxpipe-docs

One Astro project for the Vxpipe landing page and documentation, using the minimal
starter. Use Node.js 24 and npm.

## Develop

From the repository root:

```shell
npm --prefix vxpipe-docs ci
bin/dev
```

This starts Astro alongside the application. See the
[development setup](../docs/development.md) for the stack's prerequisites.
Open `http://localhost:4321/docs/en/` for the docs or `http://localhost:4321/` for
the landing page. Ctrl-C stops the stack, including Astro.

For Tailscale access, run `bin/dev --tailscale` and open
`https://<machine-fqdn>:4321/` or `https://<machine-fqdn>:4321/docs/en/`.
Astro uses the same discovered Tailscale address and certificate as the Console;
its port remains 4321 and live reload stays enabled.

To run just the site, use `npm --prefix vxpipe-docs run dev` from the repository
root.

Run `npm --prefix vxpipe-docs test` to check the development configuration.

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
