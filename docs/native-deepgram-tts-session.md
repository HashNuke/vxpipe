# Native Deepgram TTS session

Status: checkpoint F accepted, 2026-09-20. The controlled local-wire, cancellation, failure,
isolation, bounded-load and hosted semantic-session lanes pass.

## Decision

`Provider.Deepgram.FluxTextToSpeech.Session` implements the semantic `Speech.TTSProvider`
contract and owns one existing private Mint WebSocket process. The provider session and wire
live inside one scoped speech allocation. There is no shared provider supervisor, compatibility
bridge, reconnect loop, replay path, fallback provider or additional audio queue.

The semantic Channel and the socket already expose matching one-chunk flow control. Channel
permits one PCM envelope to await sink credit. The socket permits one binary frame to await an
owner result and leaves later provider frames at its active-once boundary. The session directly
connects those credits:

```text
Deepgram binary frame
  -> provider session
  -> Channel.submit(request, pcm)
  -> authorized consumer validates and accepts the exact envelope
  -> Channel credit
  -> socket frame acknowledgement
  -> next provider frame
```

This keeps memory bounded without a provider-specific queue or per-frame task. Provider control
messages remain responsive in the session while PCM acceptance is asynchronous. A
`SpeechMetadata` frame cannot overtake an uncredited binary frame in the real socket; the
controlled local-wire test also proves completion is not emitted until earlier PCM receives its
exact credit.

Once Channel fences a request, a later valid PCM submission receives the existing stale media
result. The session interprets that exact result as the cancellation race, acknowledges and
discards the wire frame, and retains the request identity until terminal settlement. It creates
no semantic audio envelope, grants no sink authority, retains no payload and does not enlarge the
playback allowance.

## Request and terminal mapping

Engine admission and provider submission remain distinct. A successful `Speak` wire write emits
`input_submitted` with provider-reported provenance. The session then sends `Flush`. If `Flush`
fails, the allocation retires while preserving the accepted `Speak` evidence for accounting. A
failed `Speak` emits no submission evidence.

The engine request reference is authoritative. Deepgram's `speech_id` is optional provider
metadata and may arrive in `SpeechStarted`, `Flushed` or the terminal message. Audio can arrive
before `SpeechStarted`; it is assigned to the sole active request. Conflicting provider speech
identities fail the allocation instead of reassigning output. `SpeechMetadata` maps to semantic
`completed` after all earlier PCM has crossed the sink-acceptance boundary. Semantic completion
still does not claim audible playback; Channel settles the request only after the authorized
consumer reports locally confirmed playback.

Deepgram documents Flux TTS as a turn-based `/v2/speak` WebSocket where `Speak` supplies text,
`Flush` ends the active turn, binary frames carry raw audio and `SpeechMetadata` terminates normal
synthesis. The implementation keeps these provider details behind the semantic session. See the
[Flux TTS quickstart](https://developers.deepgram.com/docs/flux-tts/quickstart) and
[client-message reference](https://developers.deepgram.com/docs/flux-tts/client-messages).

## Cancellation

Channel fences the exact request before the consumer clears its sink and reports actual played
milliseconds. Fencing revokes the old PCM envelope immediately. If a wire frame was awaiting that
envelope's credit, the session acknowledges and discards it so the active-once socket can reach
the provider's terminal frame.

For positive playback, the session sends `Interrupt` with Channel's cumulative
session-relative playback value. It discards subsequent in-flight PCM until either
`SpeechInterrupted` or `SpeechMetadata`, then emits one semantic `cancelled` terminal. Deepgram
specifies that the offset is measured from the start of session audio and must advance across
interrupts; see [Interruption handling](https://developers.deepgram.com/docs/flux-tts/interrupt-handling).

For zero locally confirmed playback, the session does not send `Interrupt`. A zero offset does
not advance the session playback position, and Deepgram specifically documents an interrupt
before generated audio as ignored with `NO_AUDIO_GENERATED` and no `SpeechInterrupted`. The
session instead discards any old request audio until its ordinary `SpeechMetadata` boundary and
maps that boundary to `cancelled`. This preserves terminal isolation without waiting for a
provider acknowledgement that might not arrive.

Provider `Warning` messages are nonfatal and leave the current request active. This includes
documented recoverable conditions such as markup stripping and rejected interruption attempts.
Malformed known messages, provider `Error`, socket loss, invalid audio and contradictory request
identity retire only the affected allocation. Supervision and links tear down its private wire;
the session does not reconnect or replay accepted text.

Two fence races are explicit. The cancellation ticket retains the exact engine request
identifier through both races and after replacement admission. If provider completion arrives
after the fence but before the cancel callback, the session converts Channel's cancelled
completion response into one retained
`cancelled` terminal and settles when the callback arrives. If PCM arrives in that interval, the
session validates and discards it as described above. Both paths retain the engine request
reference and provider speech identity. Channel caches the exact cancellation ticket and playback
result, so a retry remains idempotent even after replacement admission.

The locally measured `generated_bytes` boundary is semantic audio admission. PCM already placed
in an Audio envelope remains historical usage if a later fence revokes playback. Provider-private
PCM that first arrives after the fence is discarded and excluded; the submitted-text snapshot
still proves provider work. An experiment counted those private bytes inside Channel, then proved
that provider loss could publish them but an untrappable whole-scope kill could not. Guaranteeing
survival would require a separately acknowledged receipt or mutable store outside the owned tree
before every wire acknowledgement. That would create the duplicate state and flow this migration
is removing, so the contract now states the narrower metric explicitly.

## Configuration and privacy

Public configuration accepts only model, encoding and sample rate and returns a validated
descriptor. The current streaming profile is raw mono little-endian signed linear16. Credentials,
endpoint and socket controls enter through the trusted private initializer and are never accepted
as public provider options. The provider state retains request references and bounded provider
identity, but not submitted text, API keys, authorization headers, PCM or raw provider messages.
State/status inspection and failures use redacted representations.

Keeping the socket module private allows the provider to reuse the established Mint connection,
active-once input, keepalive and fixed output deadline without making framing a second integration
contract. The allocation owner, consumer authority, event ordering, usage snapshots, audio credit,
playback and settlement remain owned by the shared semantic Channel.

## Rejected alternatives

- A compatibility wrapper around the previous capability would retain duplicate request,
  cancellation, queue and playback state.
- A second provider audio queue would weaken the existing one-frame backpressure and add another
  failure/cleanup boundary.
- A task per PCM frame would duplicate OTP process lifetime and acknowledgement work while making
  cancellation ordering harder to prove.
- Reconnecting or replaying after socket loss could synthesize accepted text twice and cross a
  retired allocation boundary.
- Sending a zero-offset interrupt would rely on an acknowledgement the provider explicitly does
  not send before audio generation.
- Treating warnings as fatal would terminate healthy synthesis for documented recoverable
  conditions.
- Counting provider-private post-fence PCM in a failure-surviving local metric would require a
  second acknowledged fact path or external mutable receipt before each wire ACK.

## Verification and limits

The first controlled local-wire test failed because the session module did not yet exist. After
implementation it exposed one ownership bug: state retained the Channel's registered address,
while returned credits identify its PID. Resolving and retaining the PID repaired exact credit
matching.

Focused tests cover accepted `Speak` followed by failed `Flush`, audio before
`SpeechStarted`, terminal ordering after exact credit, independent provider IDs, nonfatal warning,
zero-played and positive-playback cancellation, cumulative offsets, late old audio, outstanding
credit release, audio and terminal arrival between fence and cancel, cancellation-identity retries,
40 sequential chunks, provider error/disconnect, owner loss, sibling Morse progress,
private/public configuration and inspection redaction. The tagged local server exercises the real
Mint WebSocket, authorization header, active-once frame ordering and semantic mapping.

The opt-in load diagnostic runs 32 independent capability trees on four schedulers, with no
common provider execution supervisor. Each performs 20 complete request, audio-credit, terminal
and playback-settlement cycles through a controlled private wire. Its report records successful
requests plus completion and settlement percentiles; it is a bounded local scheduling and
semantic-flow measurement, not hosted capacity or end-to-end call latency.

The final post-review run used Elixir 1.19.5/OTP 28 with four schedulers. All 640 requests
completed. Completion was p50 1.404 ms, p95 3.822 ms, p99 4.622 ms and max 4.743 ms; settlement
was p50 1.992 ms, p95 4.623 ms, p99 5.582 ms and max 5.685 ms. These measurements stayed below
one 20 ms test frame interval, but they do not include hosted synthesis or network time.

The tagged hosted test now drives the semantic session itself. It passed against
`wss://api.deepgram.com/v2/speak` with `flux-haley-en`, 48 kHz mono linear16, returning nonempty
audio and a provider speech identifier before semantic completion. The full root gates also pass
on the accepted implementation: 1,950 tests, zero failures and 42 excluded with seed 530504.
