# Native Deepgram TTS

## Goal

Implement Deepgram Flux TTS as a standalone scoped semantic session using the existing private
Mint wire helper. Keep room consumers on their current path until Checkpoint E; add no bridge,
fallback or shared execution process.

## Initial red test

The first tagged local-wire test starts a real scoped semantic allocation, requires provider
acknowledged readiness, sends one complete-text request, receives audio before any
`SpeechStarted` message and withholds its exact channel credit. It requires completion only
after that audio is accepted and maps a later provider speech ID independently. Before the
provider session existed, the test failed with allocation initialization failure (1 test, 1
failure; seed 530504).

## Ownership decision

The provider session owns one private wire process and one request mapping. It connects the
wire's existing one-frame acknowledgement to the semantic channel's existing one-frame credit;
there is no extra worker or queue. Cancellation releases a fenced wire frame so the socket can
continue to the provider terminal marker. Locally confirmed session-relative playback is the
only value sent as Deepgram's cumulative interrupt offset.

The first implementation resolved the channel's registered address lazily but stored that
address in provider state. The semantic credit message identifies the channel by its PID, so the
provider did not match the credit and the local-wire test timed out before completion. Resolving
the channel PID during provider initialization made the same test green.

## Focused evidence

- tagged local wire and privacy file: 13 tests, zero failures;
- Deepgram TTS session plus generic semantic TTS admission, cancellation, deadline, usage and
  streaming lanes: 50 tests, zero failures;
- provider-specific cases cover failed Flush after accepted Speak, audio before
  `SpeechStarted`, exact credit-before-completion ordering, provider IDs arriving at the
  terminal marker, outstanding-credit cancellation, late old audio discard, zero-played
  cancellation, cumulative offsets across replacements, provider failure/disconnect without
  reconnect, owner loss, sibling Morse progress, long output and public/private configuration;
- `mix compile --warnings-as-errors` passes in the owning child application.

## Reliability review corrections

The first provider candidate treated an active-request `Warning` as fatal. Existing protocol
research and the established provider path identify warnings as nonfatal; current provider
documentation also describes warnings for recoverable markup and interruption conditions. A new
test reproduced allocation retirement before subsequent PCM (9 tests, one failure; seed 530504).
Ignoring the typed warning while retaining all malformed-message and `Error` failures made the
same file pass 9 tests.

The candidate also emitted `input_submitted` only after both `Speak` and `Flush` writes. That lost
positive submission/accounting evidence when `Speak` reached the wire and `Flush` then failed,
contradicting the semantic provider contract and the previous capability's accepted-input test.
Changing the existing failure assertion reproduced the missing event (9 tests, one failure; seed
530504). Emitting submission immediately after accepted `Speak`, before attempting `Flush`, made
the provider file pass. A failed `Speak` still emits no submission evidence, and a failed `Flush`
retires the allocation without replay.

The provider state/status privacy test confirms submitted text and the API key are absent from
routine inspection.

Independent Astra review then reproduced a P1 fence/audio race. A valid PCM frame arriving after
`Session.fence_output/2` but before the provider cancel callback received
`{:error, :stale_request}` from Channel, which the adapter misclassified as an audio failure. The
reviewer's isolated case and the permanent provider test both failed with an error wire credit
and `:session_failed`. The repaired session treats that exact active-request result as the
expected fence boundary: it acknowledges and discards the frame, retains the request and provider
speech identity, and waits for the normal cancel/terminal barriers. The exact reviewer
reproduction and permanent test are green.

The same review verified that Channel's cancellation ticket and cached settlement retain the
exact request reference for idempotent retries, including after replacement admission. A
provider-terminal-before-cancel test retains both request and `speech_id`, emits one cancelled
terminal, and settles without an unnecessary interrupt.

The reviewer next tested whether provider-private PCM first arriving after a fence should extend
the locally measured generated-byte total. Recording it inside Channel made the happy terminal
case green. A provider-DOWN hook could publish the count on provider loss, but a second bounded
probe killed the whole capability tree and proved the scope-local count still disappeared. The
paired probe passed provider loss and failed whole-scope loss (2 tests, one failure). No cleanup
callback can make data survive an untrappable tree kill.

Guaranteeing that additional count would require committing a separately acknowledged receipt or
mutable counter outside the owned tree before every discarded wire frame is acknowledged. That
contradicts the accepted single Event/Audio evidence path and reintroduces duplicate state. The
attempted Channel accounting and cleanup hook were removed. The durable contract now defines
`generated_bytes` as PCM admitted into semantic Audio envelopes. Such snapshots still survive a
later fence and whole-scope loss; provider-private PCM first arriving after the fence is validated
and discarded outside that local metric. The submitted-text snapshot remains evidence of provider
work. E4 now tests fenced already-enveloped audio rather than requiring a second receipt protocol.

## Bounded load

`bench/deepgram_tts_session_latency.exs` runs 32 independent capability trees and private
controlled wires for 20 sequential turns each under `ERL_FLAGS='+S 4:4'`. Every turn includes
Speak/Flush, submission acknowledgement, one 20 ms 16 kHz mono PCM frame, exact sink credit,
provider terminal, semantic completion acknowledgement and playback settlement. No shared
provider supervisor or execution queue participates.

The final post-review run completed all 640 requests with zero failures. Completion latency was
p50 1.404 ms, p95 3.822 ms, p99 4.622 ms and max 4.743 ms. Full settlement latency was p50
1.992 ms, p95 4.623 ms, p99 5.582 ms and max 5.685 ms. All measured p99 values stayed within one
20 ms frame interval. This is isolated semantic-flow and local scheduler evidence, not a
hosted-provider capacity or end-to-end call claim.

The durable decision and its limits are recorded in
[`docs/native-deepgram-tts-session.md`](../docs/native-deepgram-tts-session.md).

## Final gates and hosted evidence

The five root gates pass on the reviewed implementation. The umbrella test run used seed 530504
and passed 1,950 tests with zero failures and 42 exclusions. The tagged hosted semantic-session
test passed against `wss://api.deepgram.com/v2/speak` with `flux-haley-en`, 48 kHz mono linear16,
nonempty audio and a provider speech identifier.

The available credential also closed the earlier native STT hosted lane. A temporary fixture was
generated outside the worktree, encoded as 48 kHz mono Ogg Opus and sent through the full
WebRTC/RTVI room path. A fixture without trailing silence did not reach endpointing. A padded
two-sentence fixture completed correctly as two turns, exposing the lane's single-turn assertion.
The final one-utterance fixture with leading/trailing silence passed through
`flux-general-multi`, the model response and output audio. These failed fixture shapes do not
show instability caused by the session migration.
