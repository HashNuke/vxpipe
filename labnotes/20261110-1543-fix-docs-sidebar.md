# Fix docs sidebar

The user reported broken hover backgrounds and excessive spacing on wrapped
sidebar titles, then requested larger links and section headings.

The theme fixed every desktop link at 30px high while its inherited line-height
was 22.4px. Two-line text exceeded its background and overlapped neighboring rows.
Website commit `2e2bbc5` overrides those rows in `src/styles/docs.css`: automatic
height, full row width, 6px vertical padding, 14px text and a 1.4 line-height.
Section headings use 14px semibold text. The theme's absolute hover span now fits
its owning row instead of retaining a separate fixed width.

Verification: Astro build and all 11 existing Node tests pass. Headless Chrome
checks at 1440px and 390px cover wrapped/current/hovered rows, scrolling, menu
navigation and page overflow. No browser errors or detector findings; no new
automated tests. A representative two-line row is 51.1875px high and contains its
text. The live site confirms the same computed font and line-height after the
successful Cloudflare build `030f6684-a583-4a89-b2c3-b55c11e957bd`.
