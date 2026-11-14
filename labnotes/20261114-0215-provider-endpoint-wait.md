# Provider endpoint wait

## Scope

Remove extra local settling after provider turn completion. Keep local detector
fallback and existing barge-in behavior. The broader multilingual milestone is
deferred. The change is confined to the continuous Scribe endpoint path, its
protocol settings, owning tests and documentation.

## Endpoint investigation

- The observed 1.5-second wait belongs to ElevenLabs `ContinuousSTT`, not a
  generic room delay after every provider's explicit endpoint.
- Existing long-VAD live evidence records a forced committed segment at 36 seconds
  while caller audio continues. The public Scribe protocol still exposes segment
  text without a commit-reason discriminator. Unconditionally mapping every
  segment to `turn_ended` would break the existing long-utterance contract.
- Current provider documentation describes optional keepalive partial transcripts
  emitted while processing silence, with empty text when no draft remains. A
  bounded protocol experiment checked whether that existing provider signal
  can replace the local transcript-settling timer without treating forced segments
  as endpoints.
- Asked the user which fallback they prefer if the available signal is inadequate:
  an explicit turn-completion provider/model, or immediate segment responses with
  the documented possibility of splitting long speech. The probe established a
  provider-silence path, so neither fallback nor a model switch is needed here.

Sources checked on 2026-11-14:

- [Realtime event reference](https://elevenlabs.io/docs/eleven-api/guides/how-to/speech-to-text/realtime/event-reference)
- [Realtime API](https://elevenlabs.io/docs/api-reference/speech-to-text/v-1-speech-to-text-realtime)
- [Earlier long-input evidence](20261011-0510-implement-transcript-start.md#scribe-endpoint-evidence)

## Verification

- The runner initially held a reservation for a completed branch with no checked
  out worktree or active Mix test process. Released it through that branch's
  normal runner command in a temporary checkout, then removed the checkout.
- One 54.2-second Scribe protocol probe passed with keepalive interval 500 ms.
  A forced commit arrived during continued input at 36,000 ms, without an empty
  partial. The first silence-phase commit arrived at 42,840 ms and an empty
  keepalive at 43,440 ms. A second short input committed at 50,000 ms and supplied
  an empty keepalive at 50,200 ms. These are input receipt positions, not measured
  acoustic endpoints; the 600/200 ms differences are not a general latency promise.
- A focused regression failed before implementation: no turn-end event within
  200 ms of the provider's empty silence notification. After removing the local
  endpoint timer, the 22-test continuous-session/protocol group passes.
- Continuous Scribe requests provider silence keepalives and publishes
  `provider_gap` when committed text has no outstanding draft and the empty
  notification arrives. Forced segments still accumulate. Repeated empty events
  cannot create extra turns. Missing evidence fails within the existing bounded
  deadline rather than inventing an endpoint. Draft flushing remains bounded.
- No changes to Silero/local manual endpointing, room interruption decisions,
  native speech-to-speech controllers, call specs or configured credentials.
- All six live conversational checks pass (171.6 seconds, seed 290078): distinct
  and repeated answers, 45.04-second input spanning forced commits, and bounded
  background noise, each with local VAD off/on. This verifies zero added local
  endpoint waiting without promoting forced segments to turns in that corpus.
- Formatting, warnings-as-errors compilation, strict Credo and the unused-dependency
  check pass. Lean builds all nine jobs and passes its replay check.
- The full default suite passes: 5,314 tests, zero failures, 385 excluded. This
  includes the configured encrypted-service room path and existing manual/local
  detector, interruption and lifecycle regressions.
- Changed documentation links and diff whitespace checks pass. The live-test
  reservation was released after live acceptance completed. Changes remain
  uncommitted in `qa`; no deployment or one-second end-to-end latency result is
  claimed.
