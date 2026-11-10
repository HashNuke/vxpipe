# Consolidated handbook and publication

Status: complete. Handbook, automatic publication, Cloudflare deployment and hosted
browser acceptance verified on 2026-11-10. Approved scope: 2026-11-10.

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

- [x] Getting started at the handbook root, with Usage and Development navigation.
- [x] Getting started.
- [x] Install with Docker (planned delivery contract).
- [x] Install on Railway (planned delivery contract).
- [x] Core concepts.
- [x] Configuration.
- [x] Accounts, tenants and access.
- [x] Integrations and credentials.
- [x] Call specs and variables.
- [x] Telephony and transfers.
- [x] Agents, tools and MCPs.
- [x] HTTP API and platform MCP.
- [x] Operations and troubleshooting.
- [x] Development workflow and documentation authoring.
- [x] Architecture.
- [x] Call runtime and lifecycle.
- [x] Speech and media runtime.
- [x] Agent runtime, tools and outbound MCP.
- [x] Identity, persistence and security boundaries.
- [x] Adding providers and integrations.
- [x] Console and client development.
- [x] Testing and verification.

### Consolidation and website

- [x] Reconcile conflicting old claims against code, including call-spec IDs,
  current ReqLLM runtime, speech start, shared tools and MCP ownership.
- [x] Remove superseded docs, preserve useful JSON references/experiment outside
  handbook prose, and repair repository links.
- [x] Import localized Markdown/assets into the website with deterministic links
  and ordering; retain the marketing homepage.
- [x] Add Mermaid support and confirm a rendered SVG on desktop and mobile.
- [x] Add branch-selected publication and its restricted credential; document
  the merge-time branch switch and a failed-build recovery procedure.

### Acceptance

- [x] Check every handbook page's frontmatter, local links and code examples
  against source; identify intended delivery behavior explicitly.
- [x] Build the website and check generated routes, links and downloadable assets.
  Run the website's existing relevant checks; add no tests that merely mirror prose.
- [x] Inspect navigation, representative guides, code blocks, diagram and search in
  a rendered browser on desktop/mobile, including console errors.
- [x] Verify an actual `docs` push runs publication, updates the website repository,
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

## Acceptance evidence — 2026-11-10

Source publication run `42840418903` succeeded and produced website commit
`422c38f`. Cloudflare deployed it successfully. The user subsequently authorized
renaming the same Worker to `vxpipe-web`; website commit `2e2bbc5` deployed through
the retained build connection and fixes wrapped sidebar rows and typography.

The initial [published handbook](https://vxpipe-web.akash-98c.workers.dev/en/docs/)
served all 22 pages and four reference downloads. Chrome verification covers actual
content, pinned source links, Mermaid rendering and the updated sidebar. Existing
website tests pass; canonical CI run `42841140567` also passes. Publication remains
selected from `docs`, with the switch to `main` documented for after merge.

Reader feedback removed the redundant contents-only landing page: Getting started
now lives at `docs/en/index.md` and `/en/docs/`, first under Usage. The standalone
Documentation sidebar group is removed. This leaves 21 pages; canonical links and
the website import follow the new location.
