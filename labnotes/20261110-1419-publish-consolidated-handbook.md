# Publish consolidated handbook

## Scope and decisions

- Canonical English pages: `docs/en/usage` and `docs/en/development`; architecture
  stays inside development. Use `en`, already the website's configured locale.
- The user approved publishing `docs` now and switching to `main` after merge.
- Two installation chapters describe intended container/Railway delivery while
  preserving the current packaging hold. GHCR is the intended registry.
- The existing `../vxpipe-docs` checkout points to `HashNuke/vxpipe-web`. Its
  `main` branch has a successful Cloudflare Workers Builds integration, still
  named `vxpipe-docs` in the observed check. This work can use that integration.
- Baseline: canonical `1914be98`, clean worktrees; website starter docs have no
  substantive content. No source publication variables, secrets or website
  deploy keys were present in the initial metadata inspection.
- Inventory/proposal: 115 Markdown files, four JSON references and one experiment.
  The installation split expands the proposal from 21 to 22 public pages.

## Design review and verification

Created the milestone and reviewed source ownership, branch selection, credential
scope, ordering, packaging status and acceptance requirements separately from
implementation. Read the delivery milestone; its hold remains in effect.
Documentation work needs link/content/build/browser checks, not new runtime tests.

Known conflicts to reconcile: historical Jido selection versus current ReqLLM;
call-spec UUID wording versus numeric-string IDs; old speech-start/MCP status
claims versus implemented participant ownership and shared tools. `bin/release`
still refers to an absent server application and must not be presented as a
verified delivery command.

## Progress

- Planning committed/pushed as `0f510e25`.
- First eight pages written: index, getting started, Docker, Railway, concepts,
  configuration, administration and development workflow. Checked current runtime
  configuration, account/router/CLI contracts and sample frontend/source docs.
- Confirmed `/healthz` is an unconditional HTTP liveness response, not dependency
  readiness. Current `.tool-versions` selects Node 26; documentation links the file
  instead of perpetuating the old Node 24 prerequisite.
- Locale JSON parses; all eight pages have title, description and sidebar metadata.
  Cross-page link verification waits for the remaining chapters. No runtime changed.
- Remaining handbook chapters, importer, consolidation and publication are pending.
