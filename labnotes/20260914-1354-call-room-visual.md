# Call room visual

## Task

Animated call-room visual on the vxpipe-docs homepage (`vxpipe-docs`), based on
`docs/architecture.md` room/participant/caller/agent/capability terminology.
Room alone; caller AudioInput arrives over an external pseudo wire.

Prior attempt (`labnotes/20260914-1226-call-room-visual.md`, static SVGs with
transfer states) was rejected by the user; this is a fresh build per the new
brief, not an iteration of that artwork (its files are already gone).

## Design (current)

The room manages the call; participants plug capabilities into it. No
turn-taking centerpiece.

- `vxpipe-docs/src/components/CallRoomVisual.tsx` — presentational React,
  rendered statically (no `client:*` directive, no astro-island in output).
  Props seam (`services`, `callerCapabilities`, `agentCapabilities` with
  defaults) reserved for the future live room monitor.
- Room container: `call room` header + live pill, then a `managed by the room`
  strip (`room authority` emphasized, `call variables`, `transcript router`,
  `call recording`), then caller and agent participant cards joined by a lane
  with a `room mixer` node and continuous bidirectional media pulses.
- Caller card owns its ingress: dashed `audio in · pseudo wire · external`
  box with animated flow into `speech-to-text`. Agent card:
  `model inference`, `text-to-speech`, `guardrails`.
- `vxpipe-docs/src/styles/call-room.css` — all motion CSS-only, both
  equalizers live, `prefers-reduced-motion` freezes to static. Caller blue is
  hardcoded (`#7aa2ff`): the theme accent variable computes near-black here.
- Wired into `src/content/docs/index.mdx` below the trust badges.
- `vxpipe-docs/test/call-room-visual.test.mjs` — red-first focused test
  covering terminology, wire-inside-caller ordering, no turn pills, no footer
  tagline, two avatar icons, React file + hydration-free MDX usage.

## Verification evidence

- `npm run build`: 4 pages, complete. `dist/index.html` contains the visual
  with zero `astro-island` markers.
- `npm test`: 3/3 pass (2 pre-existing + 1 new).
- Headless-Chrome inspection of served `dist/` at 1280px and 390px.
- Fixes from inspection: wire moved out of the stub flex row (was zero-width);
  turn pill made opaque; external stub wraps; crossfade tightened; avatars
  enlarged; caller blue hardcoded after computed-style diagnosis
  (`oklch(0.269 0 0)` invisible on dark); removed footer tagline; scoped
  `margin: 0` reset for Starlight's `li + li` 4px leak that offset chips.
- Animation proven via rect sampling (lane dot x 586→696 over 2s).
- Follow-up: participant badges removed; audiogram moved into the card
  headers (red-first test). Re-verified desktop render + 3/3 tests.
- Follow-up: agent badge renamed `model inference` → `LLM` (red-first test,
  aria-label updated, render verified; remaining page copy untouched).
- Redesign: room manages, agents share one turntable contact. Caller header
  holds avatar halo-ring + inline `audio in · pseudo wire` (no separate flow
  line) + telephony leg with incoming icon + indicative +1 (415) 555-0132.
  Three profile cards (concierge / billing / human specialist) ride an
  `offset-path` orbit loop and take turns docking at the mixer contact;
  concierge carries a dashed `MCP tools` chip, specialist is the transfer
  target with `private briefing`. 12s loop, one shared glow window with
  staggered clocks (per-card windows were proven to light all cards at once).
  Verified dock exclusivity + contact proximity at three cycle points,
  desktop + 390px renders, 3/3 tests. Caller card top-aligns to kill dead
  space; visual narrowed to 54rem max.
- Follow-up: orbit travelers collapse to icon+name pills; capabilities and
  kind note render only on the docked card (clock-synced `display` keyframes
  sharing each card's negative-delay clock). Verified expanded 210px vs pill
  76px widths and caps display flip across the cycle, desktop + mobile.
- Follow-up: orbit dropped for a free-floating vertical stack (no agent
  container card). Equal-height rows, full caps always visible, one shared
  glow window with staggered clocks (activation top→middle→bottom), and a
  bead sliding on a rail to the active row. Verified marker travel +
  exclusive highlight at three cycle points, desktop + 390px, 3/3 tests.
- Follow-up: collapsed pills read as detached, so the deck keeps full cards:
  in-flow column, -10px tucks, front green with z3, behind dimmed. Verified
  positions (equal 373px widths, 67px rhythm) and front rotation with caps
  always visible, desktop + mobile.
- Follow-up: true depth deck per references — cards share one footprint fanned
  upward (front bottom, behind peeking top edges with names readable),
  back card blurred like the reference. Verified staggered tops, exclusive
  front rotation, desktop + 390px, 3/3 tests.
- Follow-up: front card opaque (`#0b1712`) so behind cards can't bleed
  through (red-first opacity assertion), render verified, 3/3 tests.
- Follow-up: sticky-blur root-caused to base `filter: blur(1px)` leaking
  through front windows that never reset it; fixed with `filter: none` in
  front windows + base blur removed (red-first assertion). Verified
  `filter(none)` on every front card across a full cycle.
- Follow-up: pseudo wire + audio-in removed from the caller card entirely
  (test contract updated, ingress styles deleted); caller keeps avatar,
  telephony leg, speech-to-text.
- Follow-up: MCP tools badge removed from concierge (test term dropped,
  chip variant deleted); telephony row removed, number moved into a call-icon
  badge beside speech-to-text for a compact caller card. Verified render,
  3/3 tests. (Note: pseudo-wire text never existed in docs/apps — it came
  from the original brief; the :4321 afterimage is the stale dev server.)
- Docs-only change: umbrella `mix` suite not applicable; pre-existing worktree
  changes (call engine/gateway) untouched.
- Follow-up: deck cascades down-right from top-left front (16px steps),
  inactive blurred not transparent, number badge spans fixed icon alignment.
  Verified positions, cycle exclusivity, desktop + mobile, 3/3 tests.

## Open threads

- Monitor idea: same component driven by live room events (LiveView or React
  console subscribing to domain events/journal). Ingredients exist
  (exporters, console boundary); nothing room-semantic exists in OTP itself
  (`:observer`, `:dbg`/`recon_trace`, LiveDashboard are all generic).
- Detail expansions deferred: transport legs, provider badges, supervision
  tree, CallVariables read/write. User to pick 1–2.
