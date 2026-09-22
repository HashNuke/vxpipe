# Separate development launchers

- `bin/dev --tailscale` previously asked Goreman to start `docs`, so missing
  Astro dependencies stopped the application stack. Goreman accepts commented
  Procfile lines, but commenting out `docs:` still left `bin/dev` requesting the
  removed process.
- The initial focused launcher test failed because `bin/dev` still required
  Goreman. The requested scope then became two direct launchers: `bin/dev` for
  Elixir and `bin/site-dev` for Astro, each with optional `--tailscale`.
- Moved the existing Tailscale discovery and certificate staging into a shared
  command wrapper. `bin/dev` exports a shell-compatible root `.env` for Mix;
  Astro starts separately and keeps its own live reload. Removed the unused
  Procfile, Watchman restart scripts, and their old shell test.
- The new launcher test passes for normal and Tailscale modes, including command
  selection, `.env` loading, TLS environment, and invalid arguments. Bash syntax
  and diff checks pass.
- `mix assets.setup` was needed before the Console asset watcher could resolve
  its workspace packages. `npm --prefix vxpipe-docs ci` was needed to run Astro.
  A live `bin/dev --tailscale` run served the Console over HTTPS with HTTP 200 on
  port 4000, with no listener on port 4321. A separate live
  `bin/site-dev --tailscale` run served Astro over HTTPS with HTTP 200 on port
  4321, with no listener on port 4000.
- Format, warnings-as-errors compilation, strict Credo, and unused-dependency
  checks pass. The long umbrella test suite was not rerun, following the user's
  earlier request to avoid unrelated full-suite testing. Rendered browser
  inspection was unavailable because `agent-browser` is not installed; the live
  HTTPS and asset-build checks establish server startup and responses only.
