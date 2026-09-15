# Call room visual fixes (landing artwork)

Three small requests on the docs landing visual (`vxpipe-docs`, `CallRoomVisual` + `call-room.css`):

1. Hide badges on inactive agent deck cards.
2. Vertically center the room mixer between caller/agent cards on desktop.
3. Phone-number badge must match the speech-to-text chip size.

## What worked

- Red-green: added failing assertions to `vxpipe-docs/test/call-room-visual.test.mjs`
  (badge-hide opacity, grid centering, tel-number inherit), confirmed red, then fixed
  `vxpipe-docs/src/styles/call-room.css` and got green. Full docs suite: 4/4 pass.
- Fixes (all in `call-room.css`):
  - `.crv-profile .crv-cap` gains `opacity: calc(1 - var(--dim))` alongside the existing
    `grayscale(var(--dim))`, so back-deck badges fade out with the shared dim state
    while layout stays stable (opacity keeps card height).
  - `.crv-grid` uses `align-items: center`; `.crv-participant--caller` uses
    `align-self: center`; `.crv-lane` uses `align-self: stretch` with
    `min-height: 8rem` instead of the circular `min-height: 100%`.
  - `.crv-cap--tel` no longer shrinks to `0.625rem`; new `.crv-tel-number`
    rule sets `font-size: inherit`.

## Barriers / findings (measured on the live page)

- Phone number computed to **15px** vs chip **10.88px** / STT **11.52px**. Cause: Starlight's
  `.sl-markdown-content *` rule sets every span to 15px and nothing guarded
  `.crv-tel-number`, so the number ignored its parent chip. Fix verified with a
  production-order cascade replica: tel == chip == STT at 11.52px.
- Mixer center sat **~16px below row center / ~22px below caller center**. Cause: the
  `min-height: 100%` lane shifted down inside the stretched grid. After the fix the
  harness measures mixer == lane == grid == caller == deck center exactly.
- Inactive badge text (e.g. LLM peeking behind the front card) confirmed in screenshots;
  after the fix only blurred card edges remain, computed back-badge opacity is 0.

## Workarounds

- `astro dev` on :4321 kept serving the stale `_astro/ec.0dixj.css` bundle (same hash after
  edits; touch + cache-bypass reload did not rebuild), so the live page does not reflect
  the fix yet. Verified instead with `agent-browser` (isolated headless Chrome) against a
  `/tmp/crv-harness/index.html` replica that links the real `call-room.css` on disk plus a
  Starlight-cascade replica, at 1440x900. Restarting `astro dev` should pick the fix up.
- Drove verification with the `agent-browser` skill (own headless Chrome) rather than the
  user's personal Chrome via chrome-devtools MCP.

## Verification evidence

- `node --test test/call-room-visual.test.mjs` -> pass (was red before the CSS fix).
- `node --test` (vxpipe-docs) -> 4 pass, 0 fail.
- Harness screenshots: `/tmp/crv-harness/screenshot-1789441571409.png` (desktop, fixed).
- `git status`: only `vxpipe-docs/src/styles/call-room.css`,
  `vxpipe-docs/test/call-room-visual.test.mjs`, plus labnotes.
