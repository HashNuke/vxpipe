# Deepgram finite-input terminal evidence

Initial research checkpoint, 2026-09-22, against `aa67912c`, committed as
`75dba0ac` without runtime changes. Subsequent local transport work is recorded
below; it does not establish hosted acceptance. The
[finite recognition contract](output-recognition-settlement.md)
requires every final segment followed by ordered `input_finished`; a successful
callback, a conversation endpoint or elapsed time cannot substitute for that proof.

## Decision and protocol plan

Keep existing Flux finite admission disabled while resolving the exact successful
drain terminal. This is an evidence gap, not a claim that Flux cannot support finite
input. The promising profile is ordered audio, `CloseStream`, remaining updates,
then a verified peer-close signal. It cannot use our current generic
`:connection_lost` event as success. Hosted implementation still needs protocol
clarification; the separately authorized transport prerequisite is described below.

Do not send `ForceEndTurn` as an all-input flush, infer completion from a quiet
period, pad audio with silence, add a synthetic transcript, or silently switch
models/endpoints. Hosted finite-input support remains an open milestone requirement.
Ordinary human STT and existing private/PCM admission behavior are unchanged.

## Primary evidence

Official pages were read on 2026-09-22; SDK/spec sources below are immutable pins.

- [Flux CloseStream](https://developers.deepgram.com/docs/flux/close-stream)
  promises decoding received audio, emitting updates, then closing. It explicitly
  supplies neither `EndOfTurn` nor summary metadata, instructs consumers to retain
  the latest update, and says closure has no WebSocket status code. This supports
  the drain sequence, but does not specify whether the observable terminal is an
  empty peer close frame or transport EOF. Absence of a status code alone does
  **not** prove absence of a close frame. Those cases must not be conflated.
- [Flux ForceEndTurn](https://developers.deepgram.com/docs/flux/force-end-turn)
  explicitly says it uses the latest decoded transcript without another decode
  pass. A nearby broader description of received audio is insufficient to override
  that qualification. With no active turn it returns a warning, not `EndOfTurn`.
  Sending it before CloseStream therefore cannot prove the buffered tail was
  transcribed; sending it afterward is ignored.
- The [official AsyncAPI specification](https://github.com/deepgram/deepgram-api-specs/blob/6668bc2d5c3dc720697364f8c2ce3c8c0e27fbc5/asyncapi.yml#L204)
  pins Flux to `/v2/listen`: Connected, TurnInfo, ConfigureSuccess/Failure and fatal
  error responses, with no application-level finalization acknowledgement.
  `audio_window_end` describes the transcribed range, not an acknowledged submitted
  byte count. It cannot be assumed to certify every accepted PCM byte.
- The [official .NET Flux SendClose/Stop implementation](https://github.com/deepgram/deepgram-dotnet-sdk/blob/774632657c00c1253de32c3ec23dc9b76a14a173/Deepgram/Clients/Flux/WebSocket/Client.cs#L360)
  sends CloseStream and polls socket state within a grace period. Expiry or
  cancellation does not establish successful draining; Stop can fall back to
  base teardown. Its success result is not an ordered server acknowledgement.
- The [raw WebSocket example](https://github.com/deepgram/deepgram-dotnet-sdk/blob/774632657c00c1253de32c3ec23dc9b76a14a173/examples/speech-to-text/websocket/flux-raw/Program.cs#L45)
  handles peer close frames, but also stops waiting after a timeout. This makes
  frame-based completion plausible; it is not a capture proving the terminal
  emitted by CloseStream.
- The [official captured fixture](https://github.com/deepgram/deepgram-dotnet-sdk/blob/774632657c00c1253de32c3ec23dc9b76a14a173/Deepgram.Tests/Fixtures/Flux/frames.json)
  contains receive-ordered text messages and an empty `close` object. Its
  [parity test](https://github.com/deepgram/deepgram-dotnet-sdk/blob/774632657c00c1253de32c3ec23dc9b76a14a173/Deepgram.Tests/UnitTests/ClientTests/FluxParityTests.cs#L63)
  replays only text frames, so neither supplies raw close-handshake evidence.
  The [live test source](https://github.com/deepgram/deepgram-dotnet-sdk/blob/774632657c00c1253de32c3ec23dc9b76a14a173/Deepgram.Tests/UnitTests/ClientTests/FluxLiveIntegrationTests.cs#L81)
  adds trailing silence and checks a locally emitted close event after Stop. It
  does not distinguish server drain from the SDK's fallback teardown. We did not
  run it or make any hosted request.

## Approved transport seam; hosted profile remains unapproved

Parent initially approved this transport-only prerequisite on 2026-09-22,
independently of the unresolved hosted terminal profile: an optional Socket callback
`handle_peer_close(:no_status | non_neg_integer(), state) :: {:ok, state}`.
That initial status type was superseded by the reviewed correction below.
Dispatch after preceding frames/acknowledgements, once, instead of generic
disconnect for an opted-in callback. Preserve an observed code even if the close
reply fails. Raw reason text is discarded; EOF/errors and local close retain
their existing behavior. No production adapter opts in and no finite flag changes.

Pre-test design finding: the pinned `mint_web_socket` 1.0.6 decoder's
`Mint.WebSocket.Frame.into_frame/5` maps an empty close payload to code 1000 and
empty reason. Therefore Socket cannot distinguish an absent status from explicit
1000 at its current input boundary. A nil-to-`:no_status` mapping alone cannot meet
the initial empty-status distinction. The real-loopback regression reproduced
this loss. Its failing history remains recorded in the checkpoint labnote.

Approved correction after Goodall xhigh independent design review, recorded before
changing test expectations/runtime: the callback type is
`handle_peer_close(:normal_or_no_status | non_neg_integer(), state) :: {:ok, state}`.
Decoded 1000 maps to `:normal_or_no_status`; other decoded codes stay numeric.
This explicitly represents Mint's normalized evidence, never successful draining
or a distinction between those two raw wire shapes. Keep separate real-wire tests
for empty payload and explicit 1000. The milestone prerequisite is peer close
versus EOF/error/local teardown; raw empty-versus-1000 fidelity was an unsupported
assumption in our initial seam design, not a user requirement. Reject that assumed
specification rather than invent status, fork the dependency or add a second parser.

Hosted drain proof and all production opt-ins remain open. A future hosted profile
must independently prove that this normalized class suffices after finite finish;
peer-close observation alone is not that proof. If the profile requires raw
empty-versus-explicit-1000 discrimination, this seam cannot provide it.

Local implementation evidence: revised expectations failed in three of eleven
loopback tests before normalization. The corrected implementation passes all 11
transport tests and all 27 combined privacy/adapter tests. The optional callback
is implemented only by a test probe; production adapters retain generic disconnect
behavior. Exact commands, terminal handles and the original rejected-assumption
red history are in [checkpoint labnotes](../labnotes/20260922-1950-speech-peer-close.md).

`Deepgram.STTSocket.close/1` currently invokes shared `Speech.Socket.close/2`,
which sends CloseStream **and a client WebSocket close**, then immediately stops.
Finite finish must instead send only the control message and continue receiving.
That send-only operation can use existing `Socket.send_frame/2` in Deepgram code.

At the research baseline, `Speech.Socket.handle_frames/2` consumed peer close
frames itself, and `disconnect/1` reduced both peer close and transport failure to
`handle_disconnect(:connection_lost, state)`. Deepgram alone cannot recover evidence
already discarded there. The authorized local seam adds an opt-in, sanitized peer-close
notification, preserving ordered delivery after preceding frames, distinct from
EOF/error, with existing callback behavior unchanged by default. Do not pass raw
reason text, headers or connection state into public events/status. Do not duplicate
the entire shared transport to avoid this ownership boundary.

If primary evidence confirms an accepted peer-close profile, the Deepgram session
can retain the bounded latest active-turn text, finalize that tail once on proven
drain, emit existing `turn_ended` before `input_finished`, and remain available for
channel acknowledgement/owner retirement. Earlier completed segments stay in order.
Do not stop the provider immediately after emitting terminal: session monitor loss
can otherwise invalidate queued events. Missing/abnormal close remains failure under
the existing deadline; no new success timer. Repeated finish must be idempotent,
later audio rejected, and no terminal emitted before finite finish was requested.
Ordinary streaming behavior must not invoke this path.

Before hosted implementation, approve the profile and provider scope, then record
red probes for final-tail/multi-segment order, a success terminal distinguishable
from loss, no-terminal timeout, duplicate finish, post-finish input, overflow,
private inspect/status, and acknowledgement before provider retirement. Reuse
channel bounds and existing PCM/usage identity rather than adding parallel rules.

## Alternatives and limits

The existing Google STT model, `gemini-3.5-transcribe-live`, is an alternative
research target, not a silently enabled fallback. Its [official transcription
guide](https://ai.google.dev/gemini-api/docs/live-api/live-transcribe) documents
`audioStreamEnd` finalization and distinguishes provisional transcription from
final speech-segment text. The reviewed page does not identify a separate ordered
all-input acknowledgement covering multiple automatic segments. Manual VAD is
documented but would need a separately reviewed provider profile; this checkpoint
does not change Google, infer completion from its next segment, or alter human STT.

Deepgram [Nova CloseStream](https://developers.deepgram.com/docs/close-stream)
documents cached-audio results followed by summary Metadata and closure: a stronger
application-level candidate. But Vxpipe's existing Deepgram adapter supports Flux
models on `/v2/listen`, not Nova on `/v1/listen`. Adding Nova is a separately
authorized integration, not implementation of the existing Flux profile. Nova
[Finalize](https://developers.deepgram.com/docs/finalize) is also not a Flux command;
its `from_finalize` response is not guaranteed when little audio is buffered.

Local Morse already supplies ordered decoder-flush proof. It remains a local
conformance/reference implementation, not satisfaction of hosted acceptance.
No already-supported hosted provider terminal was established by this research.
