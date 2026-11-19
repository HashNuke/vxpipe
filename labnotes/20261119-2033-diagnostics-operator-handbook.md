# Passive diagnostics handbook

## Scope

Updated the existing usage operations and speech-runtime handbook pages. The
operator section covers the installation setting and allowed roles, saved versus
effective status, eligible human STT inputs, local Silero reuse/fallback, timing
labels, participant/turn segments, coverage, troubleshooting and call-owned
retention. The development section records room/node ownership, policy fences,
late evidence, bounded persistence and verification lanes.

The handbook explicitly says effective-status, measured overhead, acoustic accuracy
and live acceptance remain incomplete. It describes Scribe v2/browser as the first
live acceptance profile, not as already live-verified. It does not authorize
Telnyx tests or claim native fault isolation. No runtime or UI code changed.

## Source verification

- `Identity.DiagnosticsSettings.authorize/1`: built-in admin/superadmin browser
  sessions only; no machine, delegated or OAuth identity.
- `DiagnosticsSettingsStore.snapshot/0`, Console settings controller and
  `DiagnosticsSettingsControl`: durable value/revision, no production applied
  proof; reload after conflicts or uncertain saves.
- `TurnTiming` metric pairs and React `LatencyDiagnostics`: exact timing labels,
  run clock offsets, server-egress wording, missing values and summary exclusions.
- `Calls.Diagnostics.Coverage`: selected-window status, real stale-heartbeat and
  clock uncertainty; missing rows never become zero-latency observations.
- `LatencyRun` and `TurnDiagnostic` fixed fields plus diagnostic migration foreign
  keys: metadata-only records and cascade deletion through call/run ownership.
- Room diagnostics child specification and runtime-limits design: optional room
  subtree, source admission, separate inference/writes and lease limitations.
- Local links and heading anchors in both changed handbook pages: 9 checked, pass.
- `git diff --check`: pass. Documentation-only; no runtime suite, live-provider
  test, deployment or browser UI claim is needed for these prose changes.

Independent review identified an overbroad profile claim. Reproduced by reading
`RoomService.accept_discovery/2`: automatic attachment requires acknowledged
`scribe_v2_realtime`, no missing fields and validation against provider `:vad`
commit strategy; otherwise discovery reports `:profile_unavailable`. Both handbook
sections now state that restriction, and troubleshooting includes unsupported or
unacknowledged profiles. Provider `vad` is explicitly distinct from the local
operational Silero switch. Final Astra xhigh source review is clean after that
correction. Review confirmed settings DTO/session authorization, Superadmin URL
controls, record metadata, source intervals, timing/coverage and supervision.

Milestone F handbook checkbox is complete. Other C/E/F acceptance gates remain
open. Final checks: both handbook pages' 9 local links/anchors and the milestone's
44 relative links resolve; `git diff --check` passes.
