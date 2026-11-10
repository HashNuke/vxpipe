# Consolidated handbook and publication

Status: implementation in progress. Approved scope: 2026-11-10.

## Outcome and prerequisites

The canonical handbook lives in `docs/en/usage` and `docs/en/development` in
`HashNuke/vxpipe`. A documentation push publishes it to the Astro/Starlight site
in `HashNuke/vxpipe-web`, using its existing Cloudflare build integration.
Architecture is part of development. English uses `en`, with a layout that can
add other languages without moving English pages.

Sources: [topic inventory](../../docs/_TOC.md), the current implementation and
the website's Astro configuration. The
[delivery milestone](embedded-and-container-delivery.md) remains separate:
writing planned Docker/Railway instructions does not implement or release it.
No runtime feature milestone blocks documenting the behavior already present.

## Approved contracts

- Publish from the `docs` branch now. A repository variable selects the source
  branch; change it to `main` after merge. Do not merge as part of this work.
- Use Markdown with Starlight YAML frontmatter: title, description and sidebar
  order. Keep source links usable in GitHub and convert local handbook links to
  site routes during import. Preserve heading fragments and downloadable assets.
- The website owns its presentation and import script. The application repository
  owns all handbook prose and locale metadata. Generated copies are not edited.
- Replace the old handbook after its current contracts are incorporated. Update
  active references; retain dated evidence through labnotes or pinned Git history,
  without publishing an archive of superseded designs.
- Publish two installation guides under `usage/install`: Docker and Railway.
  Use `ghcr.io/hashnuke/vxpipe` as the intended image repository. Label unbuilt
  packaging and unverified hosting instructions clearly; link the runnable source
  workflow. This task neither packages nor deploys the Vxpipe application.
- Render Mermaid as SVG in the website; use diagrams only where they clarify
  ownership or flow. Ordinary pages should not load the diagram renderer.
- Keep publishing credentials scoped to writing the website repository. Never
  copy a personal GitHub token into the workflow or commit credentials.

## Tasks

### Handbook

- [ ] Index and two reading paths.
- [ ] Getting started.
- [ ] Install with Docker (planned delivery contract).
- [ ] Install on Railway (planned delivery contract).
- [ ] Core concepts.
- [ ] Configuration.
- [ ] Accounts, tenants and access.
- [ ] Integrations and credentials.
- [ ] Call specs and variables.
- [ ] Telephony and transfers.
- [ ] Agents, tools and MCPs.
- [ ] HTTP API and platform MCP.
- [ ] Operations and troubleshooting.
- [ ] Development workflow and documentation authoring.
- [ ] Architecture.
- [ ] Call runtime and lifecycle.
- [ ] Speech and media runtime.
- [ ] Agent runtime, tools and outbound MCP.
- [ ] Identity, persistence and security boundaries.
- [ ] Adding providers and integrations.
- [ ] Console and client development.
- [ ] Testing and verification.

### Consolidation and website

- [ ] Reconcile conflicting old claims against code, including call-spec IDs,
  current ReqLLM runtime, speech start, shared tools and MCP ownership.
- [ ] Remove superseded docs, preserve useful JSON references/experiment outside
  handbook prose, and repair repository links.
- [ ] Import localized Markdown/assets into the website with deterministic links
  and ordering; retain the marketing homepage.
- [ ] Add Mermaid support and confirm a rendered SVG on desktop and mobile.
- [ ] Add branch-selected publication and its restricted credential; document
  the merge-time branch switch and a failed-build recovery procedure.

### Acceptance

- [ ] Check every handbook page's frontmatter, local links and code examples
  against source; identify intended delivery behavior explicitly.
- [ ] Build the website and check generated routes, links and downloadable assets.
  Run the website's existing relevant checks; add no tests that merely mirror prose.
- [ ] Inspect navigation, representative guides, code blocks, diagram and search in
  a rendered browser on desktop/mobile, including console errors.
- [ ] Verify an actual `docs` push runs publication, updates the website repository,
  completes Cloudflare's build and serves the changed page. Record commit/build
  evidence before checking off this milestone and its index entry.

## Design review — 2026-11-10

The initial inventory covers 120 source files. Splitting installation makes 22
published pages. No extra architecture folder, provider-specific guide tree,
translation service, docs database or deployment system is needed. A deterministic
copy script and the existing website build are sufficient.

Dependencies: write canonical content and establish import rules before replacing
old content; verify the website locally before enabling automatic publication;
then prove the hosted path. A website deploy key avoids a broad personal token.
The source branch is an explicit setting rather than a second hard-coded workflow.
The delivery hold applies to packaging the app, not to this handbook/site work.

This is a design review, not implementation or acceptance evidence. Progress and
verification are recorded in the
[checkpoint labnote](../20261110-1419-publish-consolidated-handbook.md).
