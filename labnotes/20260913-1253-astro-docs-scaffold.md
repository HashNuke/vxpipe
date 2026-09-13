# Astro docs scaffold

## Scope and setup

- Create the requested Astro project as `vxpipe-docs/` inside the existing
  repository. Use the official minimal template with npm and strict TypeScript,
  without initializing a nested Git repository or generating agent instructions.
- This is a project scaffold, not a documentation migration or publishing task.
  Preserve the user's staged moves from `docs/` to `old-docs/` and leave the
  archived documentation and current README unchanged.
- Checked Astro's current Node requirements and the registry versions before
  scaffolding: create-astro 5.2.4 generates Astro 7.3.2, compatible with the
  available Node.js 24.18.0. Use the generated package lock and ignore rules for
  dependencies, Astro-generated files, and build output.
- The user clarified that one Astro project serves both the landing page at `/`
  and documentation at `/docs/<lang>/`, with `en` as the default. Keep the minimal
  template and scaffold `/` and `/docs/en/` with a shared page shell. Configure
  `/docs` to redirect to `/docs/en/`. Additional documentation languages can use
  sibling page directories without changing existing English URLs or the landing
  page path. No documentation theme or content migration is included.
- Replace the template README with the local development/build commands and route
  structure. Mark the `vxpipe-docs` site package private.
- The change uses the framework's existing scaffold and static copy/configuration;
  no custom runtime behavior or dependency-owned behavior tests are introduced.

## Verification

- Dependency installation and `npm run build` passed. The static build includes
  the landing page, English documentation page, and default-language redirect.
- Inspected the rendered landing and documentation placeholders in headless
  Chrome using `agent-browser` at 1280×800 and 390×844. Text and links fit both
  viewports. The landing page's Documentation link opens `/docs/en/`; visiting
  `/docs/` redirects there, and the document language is `en`. Closed the test
  browser session and stopped the preview server after inspection.
- All five required umbrella checks passed with `MIX_ENV=test`: formatting,
  compilation with warnings as errors, strict Credo, tests, and unused dependency
  checking. ExUnit reported 996 tests, zero failures, and 15 excluded tests.
- `git diff --check` passed. Generated dependencies and build output are ignored.
  The final worktree contains only the untracked site and this labnote. The
  documentation moves staged at the start are no longer present; this task did
  not modify the documentation tree or Git index.
