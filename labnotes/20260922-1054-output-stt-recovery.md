# Output STT recovery

## Reproduction and diagnosis

From `apps/vxpipe_call_engine`, run
`PGHOST=/var/run/postgresql mix test test/vxpipe/call_engine/capability/speech_to_speech_output_stt_test.exs --seed 0`.
Before changes this failed at the 5-second completion assertion. Strengthening
the existing loss/recovery test with provider and capability monitors also failed
before implementation. The capability crashed in `carry_stt_counters/2`: map-update
syntax tried to update `restart_attempts` and `retry_scheduled?`, absent from the
fresh recognition state. Redacted GenServer logs concealed the exception detail;
the stack location and monitored exit revealed the broken restart boundary.

Initializing those keys alone did not fix recovery. A failed audio push discarded
the allocation identity and buffered the remaining utterance for a replacement.
That prevented matching the old allocation's close notification, and replaying a
truncated Morse waveform could fail the replacement, exhaust retries, and leave
the next turn without recognition. Diagnostic state snapshots confirmed repeated
replacement failure and `output_stt: nil`; those temporary prints were removed.

Inspected `Speech.Channel` producer-monitor handling, `ScopeControl` retirement
and tree-DOWN slot release, `Session.close/1`, and the capability's close/event
matching. The fix belongs to the capability; no generic speech lifecycle change
was needed.

## Fix and regression

- Initialize all restart bookkeeping fields in fresh output-STT state.
- On failed recognition input, keep the allocation identity through retirement,
  mark the current turn's text failed, discard its pending PCM, and start a
  replacement for subsequent turns. Never feed or finalize the failed turn's
  PCM suffix into that replacement.
- Share failed-turn handling between push failure and session-close handling.
- Strengthen the existing two-turn regression with monitors, distinct pinned
  turn references, and completion of the recovered turn. Reduced its inherited
  15-second waits to 5 seconds; no timeout increases or weakened assertions.
- Removed `dbg_sts_restart_test.exs`: it duplicated this scenario, printed state,
  slept, and did not assert recovered transcript/completion. Its useful behavior
  is covered by the strengthened owning-boundary test. It was untracked; its
  original contents remain in the session tool transcript.

## Verification

- Two consecutive sweeps of seeds 0..6: each run 9 tests, 0 failures (126 test
  executions). Second sweep overlapped the broader/root runs.
- Final pinned-reference regression file, seeds 0..6: 63 test executions,
  0 failures (189 executions across the three complete sweeps).
- Ten-call Morse STS concurrency test: 1 test, 0 failures.
- Broader speech, STS capability, room, ingress, transfer, usage, and activation
  suite, seed 264975: 314 tests, 1 failure. Failure is the separate
  `SpeechToSpeechTest` barge-in case at line 280: helper reads `sink_turn` from
  nil `active_output` at line 378. No output-STT test failed.
- Changed implementation/test formatting and `git diff --check`: pass.
- Root compile with warnings-as-errors and unused-dependency check: pass.
- Root formatting: fails on existing milestone files outside this focused fix.
- Root Credo: five module-size violations (Google STSSession, RoomAuthority STS,
  RoomAuthority, PlanStartup, capability STS).
- Root test run is being collected; known failures so far include Morse room
  round-trip and alternate-provider plan validation (`unsupported_call_plan`
  at caller speech-to-text selection).

No commits, hosted Google calls, provider-namespace changes, or milestone/index
completion checkmarks. This is a focused recovery fix, not evidence that the
whole milestone is complete. Preserve these reproduction methods in future
teammate handoffs: test full files across seeds, observe process exits rather
than only waiting longer, trace allocation identities through close/DOWN, and
assert a subsequent real-provider turn recovers with correlated output.

## Follow-up verification

The MorseCode provider namespace migration left two call-engine tests
configuring the legacy `CallEngine.Provider.MorseCode*` modules while the
registry resolves `Vxpipe.Providers.MorseCode.*Session`. Updating those test
boundaries restored the intended provider contract; the focused tests passed,
and the full `vxpipe_call_engine` suite passed 992 tests with zero failures.
Formatting and warnings-as-errors compilation pass. Credo still reports five
project-owned module-size suggestions; the milestone remains open while those
are split and restart-context replay is specified and verified.
