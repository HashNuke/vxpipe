# Barge-in edge acceptance

## Scope and outcome

Audit the milestone's remaining barge-in edge acceptance line against the shipped
capture/projection implementation. Add only missing focused acceptance coverage.
No production behavior changed: the new tests passed against the existing code,
so no implementation fix or artificial failing assertion was necessary. The
original feature checkpoint retains its red-green implementation evidence.

The edge checklist can be closed after independent review of this checkpoint.
This does not close live acceptance, acoustic accuracy or broader performance
measurement. Direct configured operational-reuse barge-in coverage was assessed
but not added to this checkpoint: existing reuse acceptance and remaining mode
validation are separate from this edge checklist.

## Requirement-to-evidence mapping

| Requirement | Concrete evidence |
| --- | --- |
| Delayed stop changes duration; cancellation does not | `BargeInTimingTest` changes stop by 10,000 us and duration from 15,000 to 25,000 us; changing observer confirmation or interruption-request time leaves duration at 15,000 us. `OutputTest` holds sink acknowledgement and bounds its receipt after explicit release. The configured cross-human test separately holds provider cancellation and proves persisted stop precedes its release. |
| Missing acknowledgement | New `OutputTest` returns `sink_unavailable` without a receipt and rejects a late reply. New TTS diagnostic test emits transient `stop_unavailable` with nil stop, retains ordinary `audio_output_failed` termination, and cannot fabricate a report without accepted input start. New InputTurns test proves interruption failure emits neither public nor diagnostic accepted-start event. |
| No agent playback | Existing unstarted-request test returns unavailable evidence; new idle-capability test produces no playback evidence and leaves capture empty. |
| Stale/wrong output | New TTS diagnostic test rejects wrong sink and stale turn callbacks before the positive current callback. Existing wrong-turn stop test has nil stop and `stop_unavailable`. Interrupted-output identity remains separate from the interrupting input. |
| Multiple human sources | The configured cross-human test at the preceding checkpoint uses real separate A/B input allocations: B's stored run/clock/connection contains A's old output/source/connection/turn identity, while A's report has no borrowed barge-in record. |
| Duplicate callbacks | New TTS test duplicates playback start and proves the retained timestamp remains within the first callback's receipt interval. LiveReport's existing replay test preserves identical evidence and rejects conflicting duplicate stop receipts. |
| Late Silero confirmation | Existing projection test accepts confirmation after playback stop while subtracting acoustic onset. Existing LiveReport test revises the same canonical row from missing onset to available duration. |
| Source replacement | New TTS test closes the source handoff while sink acknowledgement is held, creates a replacement handoff, then releases the sink. Ordinary interruption succeeds, old evidence is discarded and replacement capture stays empty. Existing LiveReport foreign-generation guard rejects cross-generation evidence. |
| Incompatible/uncertain clocks | Existing projection test rejects unmapped acoustic time. New before-run playback test produces nil duration with `before_run`; missing or incomplete sample intervals remain `source_interval_unavailable`. Run generation and handoff fencing prevent importing another source's receipt clock. |
| Passive and bounded | New full-handoff scenario records one overflow while interruption succeeds unchanged and emits no unbounded metadata. Existing revoked-source case also preserves the operational result. New projection test retains 32 of 33 output entries and explicitly reports one omission. |

## Missing-ack limitation is intentional

A sink failure occurs before InputTurns accepts the new human turn. TTS can offer
a transient `stop_unavailable` packet, but no canonical accepted-start/completion
exists, so LiveReport does not invent a durable turn row. The tested outcome is
absence of a fabricated duration/turn, not a claim that every rejected interruption
has a durable unavailable row. Changing call control merely to record diagnostics
would violate the passive feature contract and is not part of this checkpoint.

## Verification

Five focused Engine files pass **67/67**, seed 731977:
`text_to_speech_diagnostics_test.exs`, `text_to_speech_output_test.exs`,
`input_turn_diagnostics_test.exs`, `barge_in_timing_test.exs`, and
`live_report_test.exs`. Log: `vxpipe-barge-edge-final.log`.
The initial audit selection passed 65/65 before the two bounded/clock cases were
added; the expected timeout termination log is now locally captured by its test.
Changed files are formatted and `git diff --check` passes. All sessions are
terminal. No full suite, native inference, live providers, Telnyx, deployment or
commit during implementation. Independent GPT-6 Astra xhigh review subsequently
reran the same 67 tests with seed 731977 and found no blocking issues. The parent
marked the edge acceptance checklist complete; live and acoustic gates stay open.
