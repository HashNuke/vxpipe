# Scribe VAD flush probe

## Question

Can an explicit commit flush a stranded Scribe draft while the connection retains
commit_strategy=vad, without loading Silero or reopening phantom idle turns?
This is a protocol research probe, not an adopted endpoint change.

## Sources and hypothesis

The official Python SDK exposes commit() for a connection in either strategy;
it sends an empty input_audio_chunk with commit=true. Its documentation says the
operation is normally needed only for manual mode. This client API alone does not
prove server support in VAD mode. Pipecat sends commits only in manual mode.
The provider docs identify commits as segment boundaries and document forced
commits at approximately36seconds, not full conversational endpoints.

## Bounded probe

An opt-in tagged temporary integration probe streams the existing public phrase
for41seconds followed by4seconds silence. It checks the inner adapter still has
VAD strategy, sends one explicit commit, awaits canonical settlement, continues
3seconds silence to detect ghost reopens, then sends the separate brief answer.
Only byte counts, event counts and safe mode summaries are printed. Credentials
are loaded by bin/livetests in its child; the credential file is never inspected.
No production behavior or user-approved contracts changed.

## Hosted probe result

The probe passes (seed661120,58seconds). Before the explicit request the adapter
had9 draft bytes,83 committed bytes and no canonical end. The connection retained
VAD strategy. One commit request settled the cumulative long turn; continued
3second silence emitted no semantic event, and a separate brief answer produced
a distinct turn. This proves server support for the operation in this selected
case, not a full inferred-endpoint policy or model accuracy.

## Next checkpoint

Add a bounded transcript-inactivity flush only for a draft after an existing
committed segment. Unchanged keepalives do not extend its candidate. One request
can be outstanding; changed text while waiting remains on the same turn and cannot
send a second request. The provider's committed response is still required before
canonical settlement, with a separate5second response deadline. The endpoint
continues to be labeled inferred_gap, not an acoustic/provider-semantic claim.
Focused tests are written before implementation. No Silero or strategy switch is
introduced, and the normal automatic path remains primary.

## Red/green implementation

The two focused flush tests fail as expected before implementation: no commit
request is emitted (11tests2failures, seed873765). After adding one two-phase
flush timer (inactivity candidate, then response deadline), the full continuous
suite passes11tests (seed319968). Changed drafts cannot send another request
while a response is pending. A provider segment clears both timers and provides
stable text before inferred settlement. Missing responses fail safely after5s;
startup-only drafts still await the provider's normal automatic commit.

The temporary direct protocol probe is removed after recording its result.
Acceptance now runs through the ordinary adapter, in both local onset modes,
and through the configured published-room path. These runs remain pending.

## Ordinary adapter and review evidence

The ordinary hosted adapter passed four cases: distinct short turns and 45-second
input, each with local VAD false and true (seed 513957, 123.1 seconds). The parallel
configured-room command failed during protocol consolidation before its test ran;
rerun sequentially to avoid shared build-directory mutation.

Independent review found an empty committed response could promote an outstanding
draft and cancel its deadline. The focused regression failed as expected with a
phantom turn end (12 tests, one failure), then passed after ignoring blank segments
without changing draft or timer state (12 tests, zero failures, seed 575753).
This requires actual nonempty committed recognition before settlement.

## Final verification after review

The sequential root command exits successfully: format, compilation with warnings
as errors, strict Credo, unused-dependency checks, Lean build/oracle/replay (seed
554342), and every default umbrella suite (seed 303467). No first-party failures
remain in these lanes. Lean still models the existing source gate rather than the
new coordinator or inferred Scribe endpoint. Frontend/browser evidence remains
valid because the flush change is backend-only. Documentation links pass.
Configured-room recognition and manual listening acceptance remain open. No commit
or push was made.
