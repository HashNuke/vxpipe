# STS recognizer usage

## Scope and planned evidence

Follow up the independent audit's 16 kHz stalling recognizer reproduction:
recognition inherits the STS generator's provider/outcome and divides accepted
bytes by 48,000 instead of its actual bytes per second. Added the checkpoint
breakdown and design review to the milestone before test or implementation edits.
Use capability-boundary red tests, retain the ready recognizer's descriptor for
the current reply across recovery, and verify generated observations through the
existing archive and persisted usage boundary. No hosted call, model token
estimate, new fallback or changes to the parallel Google/Gateway scopes.

## Red evidence

Capability suite: 22 tests, seven expected failures (seed 0). The controlled
timeout independently reproduces wrong provider, 4,200 instead of 6,300 ms, and
successful recognition after timeout. Additional failures cover 8 kHz duration,
rejected finalization, cancellation identity and rejected input duration. The
24 kHz control passes because it happens to match the previous hardcoded divisor.

Actual persistence exposed another defect before reaching the identity assertion:
`EctoStorage.write/2` rejects STS observations with
`:usage_observation_insert_failed`. The observation/amount schema enums, codec
and SQL check constraints omit both STS capability names. Recorded a subordinate
milestone task before repairing these boundaries; preserve existing rows and
add a migration instead of changing migration history.

After migrating the test database, first writes passed but retrying the same
fact failed `:call_fact_conflict`. A readback probe confirmed equal instants but
different precision metadata (`{767000, 6}` stored versus `{767000, 3}` emitted).
Recorded the correction before implementation: emit these new STS observations
at microsecond precision, matching the existing immutable archive representation.
Do not broaden this checkpoint into a generic archive deduplication rewrite.

## Green checkpoint

Capture the validated recognizer descriptor at acknowledged readiness and retain
it on the admitted output. Its usage identity cannot inherit STS integration or
model metadata after replacement. Count accepted bytes only, calculate linear16
duration using that descriptor's rate/channels, and retain a distinct recognition
outcome. Rejection/drop, timeout and failed finalization are failed recognition;
interruption cancels unfinished recognition. The generator retains its independent
playback outcome. Unsupported encodings do not produce invented duration.

`ERL_FLAGS='+S 2:2' mix test` from the Call Engine child with these six paths and
`--seed 0` passes 118 tests, zero failures:

- `test/vxpipe/call_engine/capability/speech_to_speech_output_stt_test.exs`
- `test/vxpipe/call_engine/capability/speech_to_speech_test.exs`
- `test/vxpipe/call_engine/room_authority/speech_to_speech_test.exs`
- `test/vxpipe/call_engine/room_authority/sts_tool_identity_test.exs`
- `test/vxpipe/call_engine/room_authority/sts_output_identity_test.exs`
- `test/vxpipe/call_engine/room_authority/sts_transcript_modes_test.exs`

Applied the additive migration to the test database with `MIX_ENV=test` and the
existing local PostgreSQL socket. The Persistence child's
`mix test test/vxpipe/persistence/usage_store_test.exs --seed 0` passes four tests.
The new test starts a real capability/recognizer, writes its emitted observations
through `EctoStorage`, repeats each exact write, reads back typed observations and
effective amounts, and verifies two rows rather than duplicate usage. Historical
migrations and existing rows are unchanged. Downgrade deliberately rejects STS
rows instead of deleting them.

Changed-file formatting and `git diff --check` pass. Independent Astra review
is running; commit this focused checkpoint before root gates. Remaining
multi-segment recognition, hosted configuration/PCM conversion and broader
lifecycle/usage acceptance stay open in the milestone.
