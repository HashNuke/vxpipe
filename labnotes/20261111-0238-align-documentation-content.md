# Align documentation content

The user reported that Getting started shifts horizontally and vertically compared
with pages that show “On this page”. The theme applies its content width and title
padding only to pages with a table of contents, and its missing right column lets
the short page center across more space.

The website stylesheet now gives documentation pages without a table of contents
the same reading width and responsive title padding. At the theme's desktop TOC
breakpoint, it reserves the same right-column space. This is a shared layout rule,
not a page-specific offset; it leaves the homepage outside its selector.

## Verification

- Before: at 1440px, Getting started's title was at x=542.5/y=64 versus the Docker
  guide at x=398.5/y=112.
- After: both title coordinates and content widths match at 1440, 1200, 800 and
  390px. At 1440px both are x=398.5/y=112 with a 640px reading column; at 390px both
  are x=16/y=88 with a 343px reading column.
- Desktop and mobile Chrome screenshots inspected; no horizontal overflow or
  browser errors. The layout detector reported no findings.
- Website build and all 11 existing tests passed. No new CSS assertions or
  application tests were added; `git diff --check` passed.

## Publication

- Website commit `c8e31ef` is pushed to `HashNuke/vxpipe-web` `main`.
- Cloudflare build `736895c0-bc18-48d8-b57d-4ea028226143` succeeded.
- Hosted Chrome checks confirm matching title coordinates and reading widths at
  1440px and 390px for Getting started and the Docker guide. The live desktop
  screenshot matches the local result; no overflow or browser errors.
