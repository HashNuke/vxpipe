# Hide empty hero image

## Scope

Hide the empty `.hero-image` wrapper emitted by `starlight-theme-black` and add
a restrained CSS signal pattern behind the landing-page hero copy.

## Progress

- Confirmed the built homepage contains an empty `.hero-image` inside a
  `data-layout="media-left"` hero even though the page frontmatter has no image.
- Initially added a focused source-level assertion, confirmed it failed for the
  missing rule, then removed it at the user's request not to test this CSS-only
  change.
- The existing homepage structure test independently fails because it looks for
  literal `Built on Elixir & OTP` while the MDX contains
  `Built on Elixir &amp; OTP`; this task does not alter that unrelated assertion.
- Hid only empty hero-image wrappers so a future configured image remains
  visible.
- Added low-contrast concentric signal lines using theme tokens, with a fade at
  the top and bottom to keep the hero copy legible in both color modes.

## Verification

- `npm run build` passes. Astro reports its existing missing `i18n` collection,
  missing `docs → 404` entry, and absent sitemap `site` option warnings.
- Rendered the built site in headless Chrome at 1440x1000 and 390x844. The hero
  copy remains centered, the signal rings stay behind the text, and the layout
  does not overflow.
- Checked both dark and light themes at desktop width. The token-based surface
  and ring contrast remain restrained and the text stays legible.
- Confirmed the theme-generated `.hero-image` computes to `display: none` when
  empty.
- The Impeccable design hook flagged the initial 12px hero radius; changed it to
  the documented 8px radius. Its remaining 24px heading-size finding predates
  this task and is protected by the existing homepage hierarchy assertion, so
  it was left unchanged. The hook also reported the existing stale design
  sidecar; no unrelated design-system files were refreshed.
