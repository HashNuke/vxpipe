# Landing hero background

## Progress

- The original repeating-radial background was attached to `.hero`, which made
  its rectangular clipping edge visible around only the headline and tagline.
- Added a focused CSS-contract test first and confirmed it failed because the
  page did not own a themed backdrop and the hero still owned `::before`.
- Moved the atmosphere to the landing page body, extended it behind the fixed
  header and through the badges, CTAs, and call-room visual, and used an opaque
  bottom gradient to return cleanly to the page background before the feature
  content.
- Kept separate dark/light backdrop values. The Starlight theme swaps the
  meanings of `--sl-color-white` and `--sl-color-black`, so ripple contrast uses
  the semantic `--foreground` token instead.
- Browser evidence: inspected dark and light themes at 1440x1000 and 390x844.
  The first capture happened during the theme transition; settled captures
  confirmed readable controls and header content in both themes.
