# Timing acceptance audit

## Scope

Audit the two remaining C timing requirements against current room-service code:
matching response text/audio landmarks (including silent/tool-only, interruption
and multi-agent routing), and a configured persisted report with late confirmation
and termination while diagnostics drain. This does not close settings propagation,
failure/load parity, acoustic accuracy or live acceptance. No runtime changes.

## Requirement-to-evidence mapping

| Requirement | Current evidence |
| --- | --- |
| Observe published response without gating output | ResponseTiming.observe offers bounded CaptureHandoff work, ignores admission result, and remembers the first publication even if diagnostics is full. AgentOutput calls it after text publication; full/revoked-capture tests still receive ordinary text. Configured inference crash/hang tests independently preserve two canonical turns and model responses. |
| Matching text and acknowledged audio | input_turn_diagnostics_test asserts exact correlation, command and output IDs and monotonic stamps; duplicate callbacks do not become new first landmarks. Configured transfer tests persist text first, assert audio absent before sink acknowledgement, then persist first_audio_started for the same response command. |
| Silent/tool-only replies | Boundary tests publish completion/tool events without fabricated response landmarks. The configured transfer's original tool-only input persists in the surviving input run with nil response_turn_id and absent text/audio landmarks. |
| Interruption | The test registers the exact speech request, verifies it is targeted, receives cancellation acknowledgement and rejects that request's late text/playback. Prior independent positive-control evidence verifies it was capable of producing a landmark before interruption. |
| Multi-agent routing | Both local-Silero modes exercise a real configured model transfer with destination preparation held while human PCM continues. The original worker/run/source/clock survives; the destination output command and acknowledged audio stay linked to the original participant-owned run. Retired-capability and unrelated-command boundary tests prevent borrowed evidence. |
| Late acoustic confirmation | The configured Scribe test holds inference across canonical turn completion, reads a pending persisted row, then releases inference and observes a higher revision of the same row with separately ordered provider end and observer confirmation. A second turn establishes available coverage. |
| Call ends while persistence drains | The configured test stops the actual room authority, observes room and collector DOWN, and deliberately holds the terminal diagnostic repository write. The stored run is still open and the writer still active at that point. Releasing the write ends the writer normally, closes the run and preserves both turn revisions. This proves lifecycle separation; it is not an inference-error or live-provider claim. |

## Current verification

From the Console child, `mix test test/integration/configured_latency_diagnostics_test.exs:208:1289`
passes 3/3 (late-confirmation/drain plus both transfer modes). From Engine, the
input_turn_diagnostics_test, diagnostics/live_report_test and diagnostics/turn_timing_test
selection passes 44/44. Logs: `/tmp/vxpipe-timing-audit-configured.log` and
`/tmp/vxpipe-timing-audit-boundaries.log`. Existing source/tests required no changes.

Independent review confirms both scoped tasks are complete. The two timing checkboxes remained
open after cutover, but the later configured continuity checkpoint replaced the
old agent-owned retirement expectation and supplies the previously missing routing
acceptance. Keep historical evidence as history rather than duplicate that work.
The separate intermittent mixed-STT/STS startup readiness failure remains recorded
in the storage-isolation labnote; this focused selection does not resolve it.

Documentation links and git diff --check pass. This documentation-only checkpoint
records current verified acceptance rather than changing behavior; full umbrella
tests and deployment remain deferred until the milestone's remaining work finishes.
