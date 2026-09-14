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
Open `http://localhost:4321/en/docs/` for the docs or `http://localhost:4321/` for
the landing page. Ctrl-C stops the stack, including Astro.

For Tailscale access, run `bin/dev --tailscale` and open
`https://<machine-fqdn>:4321/` or `https://<machine-fqdn>:4321/en/docs/`.
Astro uses the same discovered Tailscale address and certificate as the Console;
its port remains 4321 and live reload stays enabled.

To run just the site, use `npm --prefix vxpipe-docs run dev` from the repository
root.

Run `npm --prefix vxpipe-docs test` to check the development configuration.

## Routes

| URL | Source | Purpose |
| --- | --- | --- |
| `/` | `src/content/docs/index.mdx` | English landing page |
| `/en/docs/` | `src/content/docs/en/docs/index.md` | English documentation |
| `/en/docs/getting-started/` | `src/content/docs/en/docs/getting-started.md` | Getting started guide |
| `/en/` | Redirect in `astro.config.mjs` | Use the English landing page at `/` |
| `/docs/` | Redirect in `astro.config.mjs` | Default to English |
| `/docs/en/` | Redirect in `astro.config.mjs` | Preserve the previous docs URL |

Starlight renders the entire site with `starlight-theme-black`. Localized
documentation pages belong under `src/content/docs/<locale>/docs/`, producing
URLs such as `/en/docs/`. English (`en`) is the primary and only published
language for now. The root landing page remains English-only.

Provider logos use `@lobehub/icons`, rendered as static markup through Astro's
React integration. Logos missing from LobeHub live directly in `src/assets/logos/`.

## Build and preview

From this directory:

```shell
npm run build
npm run preview
```

The static site is generated in `dist/`. Astro emits an HTML redirect for `/docs/`
in a static build; the development server also handles the configured redirect.
