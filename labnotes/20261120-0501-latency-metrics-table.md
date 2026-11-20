# Latency metrics table

- User reviewed the Metrics story and found the separate collapsed Latency
  diagnostics panel redundant beside the metrics table; approved folding it in.
- Conflict found: an earlier user rule (labnote 20261119-0608) keeps STT rows as
  one summarized row per participant. Resolved by adding a separate VAD row per
  observed human after their STT row; VAD rows expand per turn, STT rows do not.
- Implemented in `@vxpipe/react`: `latencyRows.ts` (grouping by participant and
  full profile, median/p95/valid counts, Room/Participant VAD labels),
  `useLatencyRows.ts` (bounded reads: 4 report pages, 4 turn pages per run,
  revision-safe merge, 5 s live refresh, denial clears data), `LatencyCells.tsx`
  (summary cells, per-turn cells, click-opened evidence popovers). `Metrics`
  takes an optional `latency` prop; `CallConsole` passes the host loader.
  Removed `LatencyDiagnostics`, `useLatencyReport`, their stories and tests;
  kept `BargeInEvidence`/`AcousticSegments` unit tests.
- Red-green: 21 new tests in `latencyMetrics.test.tsx` failed first (no latency
  prop), then passed. Header badge and Room/Participant VAD labels were each
  red-tested before the change.
- User follow-ups mid-task: the badge ("operational reuse · incomplete") was
  jargon; user chose to remove it in favour of an info icon. Popovers name the
  source as Room VAD or Participant VAD. User asked not to extend the live browser
  test for UI; its admin latency-UI assertions were removed instead, since the
  TypeScript tests cover the UI. Stored-report checks in that test are unchanged.
- Storybook: Console host consumes the built package, so each rebuild needs a
  restart with cleared `node_modules/.vite` and `.cache/storybook`. Port 6007 is
  the Tailscale proxy; start with `STORYBOOK_PORT=6008 bin/storybook` in tmux
  session `vxpipe-storybook`.
- Browser inspection (headless Chrome, agent-browser): Metrics story at 1440x1000
  collapsed, expanded and with turn/observation popovers; 390x844 with no page
  overflow; light theme. All latency stories render their state (available,
  loading, retry, large, participants, barge-in).
- Not run: the live browser test (needs live provider credentials).
