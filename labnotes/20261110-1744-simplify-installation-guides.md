# Simplify installation guides

## Scope and decisions

- Getting started offers Railway and Docker image cards and links the existing
  configuration reference. Source setup stays in Development; the provider-backed
  playground moved there without changing its commands.
- Public installation guides explain setup without planned/intended-delivery
  notices, as requested. The delivery milestone remains unchecked and retains
  release packaging, migration command, real image and media acceptance work.
- The README now points to installation choices and source development separately.
- Use `ghcr.io/vxpipe/vxpipe` while retaining `HashNuke/vxpipe` as the source repository.
  GitHub's [Container registry documentation](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
  permits organization-owned images independently of a source repository. The
  authenticated user has active admin membership in `vxpipe`. Cross-owner uploads
  need organization publishing permission; a classic `write:packages` token is
  an available mechanism. No token was created and no image was published.
- Cards use ordinary Markdown links in an HTML wrapper and website-owned CSS.
  Existing import/link rewriting remains sufficient; no MDX or new dependency.

## Verification

- Website import and build succeeded: 21 handbook pages, 23 total site routes.
- All 11 existing website tests passed; no prose assertions or new tests added.
- Chrome at 1440×900 and 390×844: two equal desktop cards, stacked mobile cards,
  readable wrapping and no horizontal overflow. Screenshots inspected.
- Keyboard focus displays a visible card outline; Tab/Enter opens Docker.
- Impeccable detector reported no findings for the changed stylesheet.
- A selector click on a description was intercepted by the intentional full-card
  anchor overlay; a coordinate-based click on the description opened Railway.
- Dark-mode mobile rendering passed; the browser reported no errors.
- All 21 canonical pages' local targets and built handbook routes/anchors passed
  a one-off link check; `git diff --check` passed.
- These checks validate documentation and presentation, not application container
  startup. No Vxpipe runtime deployment or container packaging was performed.
