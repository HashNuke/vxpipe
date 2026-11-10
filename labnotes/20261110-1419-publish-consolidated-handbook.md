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

- Usage checkpoint: all 12 usage pages drafted. Checked call-spec schema/ID,
  canonical API routes, key/session separation, credential resolution and Oban
  timestamp implementation. The source editor does not launch test calls; the
  quickstart now uses the actual managed playground and explicitly provisions its
  `default` bindings (Console bindings use provider names). No sample-prototype
  behavior is presented as a production call launcher.

- All 22 handbook chapters are drafted with current contracts and concise rationale.
  Architecture and activation ownership use two Mermaid diagrams.
- Moved the four unchanged directory JSON references into `docs/assets/integrations`.
  The production validator and existing tests read those assets, so their paths
  move together. This is a mechanical reference change; no new tests are added.
  Existing required code checks will run before this checkpoint is complete.

- Consolidated all 115 old Markdown documents into the 22-page handbook. Removed
  superseded prose; retained historical evidence through 516 pinned links across
  117 reference files. Moved the experiment to labnotes/experiments; four JSON
  references are byte-identical at their new asset paths.
- All handbook frontmatter, relative files and heading fragments checked. Generated
  site links/anchors and four asset downloads checked without errors.
- Website import/build and all 11 existing tests pass; Wrangler deployment dry-run
  passes. Desktop (1440px) and mobile (390px) Chrome inspection found a theme issue:
  nested installation links disappeared on mobile and long pagination labels
  overflowed. Flattened those navigation entries and allowed labels to wrap;
  confirmed navigation, search, diagram rendering and ordinary-page lazy loading.
  Impeccable's scoped UI detector reports no findings. No new automated tests.
- Canonical format, warnings-as-errors compilation and strict Credo pass. The full
  umbrella suite is still running; its Call Engine lane has one failure in the
  untouched STS transfer-resumption test (held error after tool failure).
  Follow-up verification will record whether it reproduces.
- Configured DOCS_PUBLISH_BRANCH=docs. Website deploy key ID 169410306 has write
  access only to HashNuke/vxpipe-web; its private key is stored solely in the
  source repository's Actions secret. No personal token was copied.

## Publication and final verification

- Canonical consolidation committed as `0bee1abf`; website importer/presentation
  as `086adbc`; publication workflow as `16f3b38e`. All pushed.
- [Publication run 42840418903](https://github.com/HashNuke/vxpipe/actions/runs/42840418903)
  succeeded from `docs`, imported all 22 pages, built the website and created
  website commit `422c38f`. Its source metadata records `16f3b38e`. The local
  website checkout was fast-forwarded to that generated commit.
- Repeated import is byte-identical. Generated HTML checks cover all 22 pages,
  internal destinations/fragments and four JSON downloads: no broken links.
  Desktop/mobile Chrome shows both Mermaid SVGs without page overflow. Ordinary
  guides do not load Mermaid core. Search finds the handbook, code blocks expose
  copy controls, the landing page renders and browser error output is empty.
- Root checks: format, compile with warnings as errors, strict Credo and unused
  dependency check pass. Full umbrella run: 5,213 tests, one failure, 376 excluded.
  The failure is the existing STS failed-transfer resumption assertion returning
  `{:error, :held}`. The same assertion failed in the earlier integration-move
  run before this documentation work. The focused six-test STS transfer file
  passes with the same seed (570288). All Console tests, including moved schema
  consumers, pass. No speech behavior or test was changed to hide that result.
- Cloudflare successfully built/deployed generated website commit `422c38f`:
  [build 7fc5824c-6c60-4a1b-bac5-d97d2076eaee](https://dash.cloudflare.com/98ceddea8225e2c34f6ccbdd842aa6be/workers/services/view/vxpipe-docs/production/builds/7fc5824c-6c60-4a1b-bac5-d97d2076eaee),
  version `dd7e2122-3aec-4e05-9430-e2f6e8030120`. The initial website commit also
  deployed successfully. No Vxpipe application deployment was performed.
- Hosted-page verification remains pending: the check exposes its dashboard URL,
  not a public site URL. Requested that URL from the user; retain the final
  acceptance checkbox until the actual hosted page is inspected.
