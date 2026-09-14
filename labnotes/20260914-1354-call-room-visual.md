# Call room visual

## Task

Animated call-room visual on the vxpipe-docs homepage (`vxpipe-docs`), based on
`docs/architecture.md` room/participant/caller/agent/capability terminology.
Room alone; caller AudioInput arrives over an external pseudo wire.

Prior attempt (`labnotes/20260914-1226-call-room-visual.md`, static SVGs with
transfer states) was rejected by the user; this is a fresh build per the new
brief, not an iteration of that artwork (its files are already gone).

## What was built

- `vxpipe-docs/src/components/CallRoomVisual.astro` — static Astro component,
  zero JS. Room container with `call room` header + live pill; external dashed
  `pseudo wire · audio in` stub feeding the caller card over an animated wire;
  caller participant (`audio input`, `speech-to-text`); agent participant
  (`model inference`, `text-to-speech`, `guardrails`); turn lane between them
  with `caller turn` / `agent turn` crossfade and traveling pulses.
- `vxpipe-docs/src/styles/call-room.css` — all motion CSS-only on an 8s
  turn-taking loop (caller 0–45%, agent 48–95%): eq bars, speaking pills,
  capability glow sweep, wire flow + dropping audio dot, lane pulses.
  Stacks vertically ≤42rem with a vertical lane; `prefers-reduced-motion`
  freezes to a static caller-speaking state.
- Wired into `src/content/docs/index.mdx` below the trust badges.
- `vxpipe-docs/test/call-room-visual.test.mjs` — red-first focused test
  (failed before the component existed, passes now).

## Verification evidence

- `npm run build`: 4 pages, complete.
- `npm test`: 3/3 pass (2 pre-existing + 1 new).
- Headless-Chrome inspection of served `dist/` at 1280px and 390px.
- Animation proven via computed-style sampling across the loop: agent phase
  (`turnA=1`, return dot x 686→663 moving agent→caller) and caller phase
  (`turnC=1`, outbound dot visible, caller eq opaque, agent eq dimmed).
- Fixes from inspection: wire moved out of the stub flex row (was zero-width,
  dashes invisible); turn pill made fully opaque (track bled through);
  external stub wraps instead of truncating; crossfade window tightened
  (46–50% overlap ghosted); avatars enlarged.
- Docs-only change: umbrella `mix` suite not applicable; pre-existing worktree
  changes (call engine/gateway) untouched and uncommitted.
