# Astro Tailscale access

- The user requested that `bin/dev --tailscale` also make Astro reachable over
  Tailscale without changing ports. The launcher already starts Astro and exports
  the discovered host, IPv4 address, TLS mode, and certificate paths to Goreman.
- Configure Astro to consume that existing environment, bind to the Tailscale
  address, and reuse the certificate for HTTPS on port 4321. Ordinary development
  retains localhost HTTP, even if stale Tailscale variables are present.
- Preserve unrelated worktree changes, including the database setup edits in
  `docs/development.md`. This is a development-tooling change, outside the pending
  packaging and retention milestones.
- Add focused Node tests at the Astro configuration boundary before changing
  configuration. The existing shell suite already verifies the launcher's
  process selection and exported environment.
- Checked the installed Astro config types and dev-server merge, alongside the
  official [Astro configuration reference](https://docs.astro.build/en/reference/configuration-reference/#serverhost)
  and [Vite HTTPS options](https://vite.dev/config/server-options.html#server-https).
- Red: `node --test test/astro-config.test.mjs` from `vxpipe-docs` passed the
  ordinary-development test and failed the Tailscale test because the existing
  configuration supplied neither the Tailscale listener nor HTTPS certificate.

## Verification

- Green: `npm test` from `vxpipe-docs` passed both configuration tests;
  `bash test/bin/dev_test.sh` passed the launcher integration checks.
  `npm run build` from `vxpipe-docs` generated the static site successfully.
- All five umbrella completion checks passed from the repository root with
  `MIX_ENV=test`: formatting, compilation with warnings as errors, strict Credo,
  the default ExUnit suite, and unused dependency checking.
- Started the real Astro Procfile process through Goreman with its RPC server
  disabled and the launcher's Tailscale environment. Verified its listener bound
  only to the machine's Tailscale IPv4 address on 4321. Curl accepted the real
  certificate without bypassing verification and received the `/docs/` redirect.
- Headless Chrome through `agent-browser` opened the landing page and followed
  `/docs/` to `/docs/en/` on the real HTTPS FQDN. Inspected desktop (1280 by 720)
  and mobile (390 by 844) screenshots. Both rendered correctly, with no browser
  errors, and the Vite live-reload WebSocket connected over the same port.
- An edit-triggered reload could not be verified: touching the page and making
  a temporary text edit did not update the loaded page in this environment.
  A verification-only retry with `CHOKIDAR_USEPOLLING=true` behaved the same.
  The browser's waiting commands also stalled. Restored the page exactly and
  left the project's file-watching settings unchanged; only WebSocket connection,
  not end-to-end edit propagation, is verified. Stopped the verification server.
- Local Tailscale installation barriers prevented running the full unmodified
  launcher for the live check: invoking its macOS app through the installed CLI
  symlink crashed with an unknown bundle identifier, and the direct app executable
  could not write certificate files into the repository. The direct executable
  could discover the address; redirecting its documented certificate/key stdout
  outputs into ignored, private runtime files allowed HTTPS verification. No
  certificate/key contents were displayed or staged. The launcher and system
  installation were not modified for these unrelated local issues.
