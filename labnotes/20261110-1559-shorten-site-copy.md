# Shorten site copy

The user requested a shorter product description and landing hero, then asked for
Getting started to replace the redundant documentation contents page.

- Use “Self-hostable voice agent platform” for the product description/hero and
  the user's shorter telephony, recordings and analytics tagline on the homepage.
  Recording and per-call usage reporting are documented capabilities.
- Move the guide to `docs/en/index.md`, remove its former duplicate route, and
  update relative links. The handbook now has 21 pages.
- The website sidebar starts with Getting started under Usage; remove the
  Documentation group. Keep the website's landing prose separate from imported
  canonical documentation.
- Remove two obsolete exact-copy assertions from the existing homepage structure
  test. Its checks for actions, badges and section order remain; no new tests.
- Local verification: 21 canonical pages have valid relative links; the importer,
  Astro build and all 11 existing tests pass. Chrome at 1440px/390px shows the
  shorter hero without overflow. The docs root renders the actual guide, with
  Usage/Development groups and Getting started selected. No browser errors or
  design-detector findings.

Publish the website navigation change before pushing the canonical move so the
source publication workflow imports into a site that understands the new route.

Published canonical commit `7bd1662c` and website commit `1147451`. Source
publication run `42850786020` and Cloudflare build
`ce29affd-5ae6-4852-a1b9-e83bfdee20e5` succeeded. Live Chrome confirms the new hero,
Getting started at `/en/docs/`, exactly 21 sidebar page links, and only Usage and
Development groups. Built HTML has no broken page/anchor links; the old separate
guide route is absent. Both repositories were clean after publication.
