# Google STS resumption handles

The user explicitly requested Google resumption-handle support. Implement
directly; no delegation, billable calls or commits. Google production selection
remains gated. This checkpoint does not add fresh-session conversation replay.

## Contract review

The official Live API reference requires `setup.sessionResumption` to enable
updates, identifies `newHandle` plus `resumable`, and warns that using a previous
token during generation/tools loses data. The current adapter does not request
updates on initial setup, ignores revocation, accepts old-socket input while a
replacement starts, and has no unexpected-disconnect resumption. Its existing
renewal test sleeps and only asserts that another socket was created.

Primary references: https://ai.google.dev/api/live and
https://ai.google.dev/gemini-api/docs/live-api/session-management (checked
2026-09-22). The lifecycle decision and limitations are in
`docs/sts-context-restoration.md`.

New tests use explicit go-away events and provider acknowledgements, not sleeps.
They require opt-in setup, strict token decoding/revocation, latest-handle use,
paused input before replacement setup acknowledgement, stale-socket fencing,
idle disconnect recovery, no replay of accepted input, private status, and a
bounded replacement deadline with supervised cleanup and no fresh fallback.

## Red-green evidence

The initial codec/session group failed six tests for missing setup opt-in,
revocation decoding, keeping the old connection alive during handoff, refusing
idle-disconnect recovery and leaving an unacknowledged replacement open past
its deadline. A separate shared-output test failed because successful consumer
settlement sent no provider notification.

Implemented a same-allocation `STSResumption` controller with a single 5-second
attempt budget (positive private override up to 15 seconds), socket-qualified
timers, strict checkpoint invalidation and no replay/fallback. The provider is
notified once after validated consumer playback settlement. The initial
codec/session/output group passed 28 tests (seed 0).

The user clarified that reconnection must not replay the conversation to the
caller. Added explicit assertions that the replacement sends only setup with
the handle, no historical input, no new turn/audio, and later accepts only the
new input. Added a generation-complete-but-playback-pending handoff test and a
rejected-setup cleanup test. The expanded Google session group passed 16 tests.

A further red test showed that applying the short reconnect budget while a
longer reply was still playing could end a viable call unnecessarily. The
codec now preserves `goAway.timeLeft`; pending playback may finish until that
deadline or local connection expiry, whichever is earlier. The actual reconnect
keeps its separate 5-second maximum, never extending the original deadline.
The regression uses a 50 ms reconnect budget and explicitly proves the pending
reply survives beyond it before settling; it does not use sleeps.

The timing regression and codec change were both red before the repair. The
Google codec/session group now passes 24 tests (seed 0). The final broader
Google/shared-output/capability/output-STT/ten-session group passed 63 tests
(seed 264975), including the timing refinement. Root format,
warnings-as-errors compile, strict Credo, unused-lock
and whitespace checks pass on the refined implementation. The final root run
passed 2,151 tests with zero failures (42 excluded, seed 0), including the
repaired native WebRTC transfer fixtures. Hosted Google checks were not run;
the broader milestone's load, UI and review acceptance remains open.

No real key, hosted model request or resumption token was used. Fake handles
remain fixture strings; the production handle is neither public configuration
nor a durable record. The implementation deliberately cannot reconstruct a
provider process after that process itself dies.
