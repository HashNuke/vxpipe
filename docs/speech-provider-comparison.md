# Speech provider API comparison

Researched 2026-09-19 from the linked official documentation. This is a comparison of API
contracts, not latency/quality benchmarking or evidence that these providers are integrated.
The user requested Cartesia, AssemblyAI, Rime, ElevenLabs and Gemini to test the proposed
abstraction against more than the existing Deepgram and Morse implementations.

Recommendation: a small semantic session API works for standalone streaming STT and TTS,
provided it explicitly separates transcript stability, turn completion, synthesis completion,
playback completion and cancellation isolation. Batch transcription and conversational
speech-to-speech sessions need distinct contracts. See the
[design](speech-provider-contract.md), [implementation milestone](milestones/simpler-speech-integrations.md)
and [provider authoring guide](speech-integration-guide.md).

## Comparison

| Provider/API surface | Input and output | Boundary and cancellation | Fit for Vxpipe |
| --- | --- | --- | --- |
| Cartesia TTS WebSocket | Text for a context; correlated audio chunks and optional timing. | Context cancellation; separate flush and generation-done events. | Semantic TTS; context IDs stay adapter-private. |
| Cartesia automatic STT | Continuous audio; cumulative turn transcripts and explicit turn events. | Provider determines turn start/end; eager end/resume are supported. | Semantic conversational STT. |
| Cartesia manual STT | Continuous audio with caller-issued finalize; transcript results. | Finalize and close acknowledgements are separate from transcript finality. | Needs an external turn-boundary owner; not automatically eligible for the current call path. |
| AssemblyAI streaming STT | Binary audio; session, speech-start and turn-transcript events. | `end_of_turn` is authoritative; explicit termination ends the session. | Semantic conversational STT; model-specific settings remain local to the adapter. |
| Rime TTS HTTP / JSON WebSocket | Complete text over HTTP or buffered text over WebSocket; bytes or base64 chunks. | Flush, clear and end-of-stream have different meanings; synthesis can have several batches. | Semantic TTS; completion requires a configured batch-boundary strategy. |
| ElevenLabs TTS HTTP / WebSocket | Request streaming or incremental text; audio and optional alignment. | Multi-context API supports closing an interrupted context; flush generates buffered text. | Semantic TTS; endpoint/model choice and context isolation remain private. |
| ElevenLabs realtime STT | Base64 audio messages; replaceable partials and committed segments. | Manual or VAD-driven commits; a commit finalizes a segment. | Needs explicit endpointing provenance; do not equate every commit with a conversational turn. |
| Gemini dedicated TTS | Text request; audio response, with streaming supported by documented newer TTS models. | Request-local completion; no persistent speech connection is necessary. | Semantic TTS through a bounded request worker. |
| Gemini audio understanding | Audio file/inline audio plus a prompt; generated text including transcription. | Request completion, not a live speaker-turn event. | Batch/utterance transcription; unsuitable as a drop-in continuous STT provider. |
| Gemini Live | Bidirectional audio/model session with optional input/output transcription. | Server activity detection, interruption and model-turn lifecycle. | Separate realtime agent/session design; it also owns conversation/model behavior. |

The rows are synthesized from the evidence below. “Fit” is an architectural inference, not
a claim of support, proven cancellation semantics, or permission to add these integrations.

## Provider evidence

### Cartesia

The [TTS WebSocket reference](https://docs.cartesia.ai/api-reference/tts/websocket) documents
context-tagged generation/audio, cancel-context messages, flush acknowledgements and a final
generation event. Audio is base64 in the JSON response, with an explicit requested output
format. Optional timestamps are separate events. A Vxpipe request reference can map to a
provider context without the engine knowing Cartesia's wire identifiers.

The [STT endpoint comparison](https://docs.cartesia.ai/use-the-api/stt/compare-endpoints)
distinguishes automatic turn detection, manual finalization and whole-file transcription.
Its [turn guide](https://docs.cartesia.ai/use-the-api/stt/turns) defines start/update/eager-end/
resume/end events and cumulative turn text. The
[manual reference](https://docs.cartesia.ai/api-reference/stt/websocket) instead requires
`finalize` for buffered input and has separate finalize/close acknowledgements. Thus one
provider brand does not imply one STT lifecycle. Realtime input is paced audio; a file must
not be injected at unrestricted speed through that lane.

### AssemblyAI

The [current streaming specification](https://www.assemblyai.com/docs/streaming/api-spec/streaming-websocket)
defines `Begin`, `SpeechStarted`, `Turn`, and termination, with a session ID and turn order.
It distinguishes raw PCM, raw Opus packets, Ogg Opus and ADTS AAC; packet/container semantics
matter beyond the codec name. The [message guide](https://www.assemblyai.com/docs/streaming/message-sequence)
separates the running `transcript` from an utterance fragment. The
[turn-detection guide](https://www.assemblyai.com/docs/universal-streaming/turn-detection)
identifies `end_of_turn`, rather than formatting completion, as the turn boundary.

Model families expose different controls: the
[voice-agent guidance](https://www.assemblyai.com/docs/voice-agents/best-practices) distinguishes
newer silence/punctuation behavior from older confidence controls. Do not promote a particular
threshold field into a universal STT callback or silently carry settings across models.
The [product integration reference](https://www.assemblyai.com/docs/coding-agent-prompts)
distinguishes standalone STT from its managed voice-agent product and states that standalone
TTS is not a separate API. This comparison uses standalone streaming STT only.

### Rime

Rime's [streaming guide](https://docs.rime.ai/docs/streaming) offers HTTP response-body audio
and WebSockets. The [Coda JSON reference](https://docs.rime.ai/api-reference/coda/websockets-json)
documents text/context IDs, clear, flush, EOS, audio and optional timestamps. It offers
explicit format/sample-rate options, including PCM; unknown format values may fall back to
WAV, so adapter-side validation must reject unsupported settings before sending them.

The [segmentation guide](https://docs.rime.ai/docs/websockets-segment) is the key difference:
`segment=never` leaves synthesis initiation to flush/EOS; an empty flush produces nothing,
and overlapping flushes can be coalesced. Other modes produce synthesis runs based on text
segmentation. Therefore, counting flushes against done events is unsafe. For a complete-text
Vxpipe request, a future adapter should use one validated serialization/segmentation strategy
and verify its final boundary. Clearing buffered text alone does not establish that all
previously generated audio is gone. The docs reviewed do not establish a generic cancellation
acknowledgement with that guarantee.

The [API index](https://docs.rime.ai/docs/api-reference) describes TTS surfaces; no standalone
continuous STT contract was established in this review. The older generic JSON reference
redirects to Mist v2 `/ws2`; the current Coda page describes `/ws3`. Record the exact endpoint
and model in future fixtures rather than treating those protocols as identical.

### ElevenLabs

The [HTTP streaming reference](https://elevenlabs.io/docs/api-reference/text-to-speech/stream)
returns generated audio from a complete text request. The
[TTS WebSocket guide](https://elevenlabs.io/docs/eleven-api/guides/how-to/websockets/realtime-tts)
describes buffered text and flush, and notes model-specific endpoint restrictions. Its
[multi-context guide](https://elevenlabs.io/docs/eleven-api/guides/how-to/websockets/multi-context-web-socket)
uses a context per generation and closes the previous context on interruption. That supports
request isolation without a universal cumulative playback-offset command. Keep context-close
and audio-drop ordering in the adapter and verify it on the chosen endpoint.

The [realtime STT reference](https://elevenlabs.io/docs/api-reference/speech-to-text/v-1-speech-to-text-realtime)
uses a session-start event and base64 audio messages; supported input formats include several
PCM rates and 8 kHz mu-law. The
[commit guide](https://elevenlabs.io/docs/eleven-api/guides/how-to/speech-to-text/realtime/transcripts-and-commit-strategies)
distinguishes manual and VAD commits and documents automatic long-segment commits. The
[event reference](https://elevenlabs.io/docs/eleven-api/guides/how-to/speech-to-text/realtime/event-reference)
describes replaceable partials, stable committed segments and later timestamp metadata.
Those are segment guarantees. A future adapter must establish which events/configuration
justify a speaker-turn boundary and how it obtains speech-start evidence for barge-in;
the engine must not infer either merely from an arbitrary committed segment.

### Gemini

The [dedicated TTS guide](https://ai.google.dev/gemini-api/docs/speech-generation) explicitly
distinguishes exact-text speech generation from Live conversation. It documents request-based
single/multiple-speaker generation and streaming audio via the Interactions API for TTS
models starting with version 3.1; its examples use 24 kHz 16-bit mono PCM. A future adapter
must pin a supported API/model combination. Whole-response and streamed models have different
buffering/first-audio implications, but neither needs a fake connected/speech-started event.
The reviewed page does not establish a speech-specific server cancellation guarantee; local
request abortion and output suppression must not be reported as proof billing stopped.

The [audio-understanding guide](https://ai.google.dev/gemini-api/docs/audio) supports prompted
transcription of supplied audio. It directs realtime conversational use to Live and dedicated
realtime STT use to Google Cloud Speech-to-Text, a different product. A completed transcription
request does not establish a live turn boundary.

The [Live capability guide](https://ai.google.dev/gemini-api/docs/live-api/capabilities)
documents input/output transcription alongside model audio, activity detection, server
interruption and client playback clearing. Live uses little-endian PCM, with 24 kHz output
and sample-rate-described input. Adapting that whole session as independent STT plus TTS would
obscure its model/context/tool ownership. Keep Live as a separate future realtime-agent
decision; this milestone does not replace Vxpipe's model loop.

## Abstractions supported by the comparison

These are design conclusions drawn from the sources, with deliberately bounded scope.

1. **Session does not mean socket.** A local provider, reusable WebSocket or per-request HTTP/SSE
   worker can implement the same speech operations. Readiness is explicit and describes its
   actual evidence; local initialization cannot imply remote authentication was verified.
2. **Separate stable text from turn evidence.** Normalize full current-turn snapshots while
   keeping segment commits internal. Declare endpointing provenance. Manual/batch modes need
   a separate boundary owner; reject unsupported conversational configurations explicitly.
3. **Use engine request references.** Provider context IDs, sequence numbers and sessions are
   adapter metadata. Retain optional genuine provider IDs for accounting and diagnostics.
4. **Define completed at the request boundary.** A provider's flush/batch event is translated
   only after all input for the engine request and all its audio are accounted for. Sink
   playback acknowledgement remains separate.
5. **Cancellation guarantees local isolation.** Providers use context cancellation, worker
   abortion, draining or session closure. Remote cancellation/billing certainty is separate
   evidence and cannot be invented from a successful local cancel call.
6. **Make audio representation explicit.** Codec, rate, channels, byte order and packet/container
   framing are validated. Base64 and JSON are wire encodings inside adapters. Rechunking and
   pacing respect bounded queues; new resamplers/codecs remain separate work.
7. **Keep extensions optional.** Word timing, eager endpoints and incremental text input are
   useful but not baseline requirements. Start with complete-text `speak`; a future
   begin/append/finish-text extension can preserve prosody within one engine request if needed.
   Do not expose vendor Flush simply to accommodate token streaming.

## Uncertainties and implementation evidence required

No accounts were contacted and no credentials were read. Provider versions, quotas, rollout and
sample code can change; recheck the exact endpoint/model docs before implementing an adapter.
Some older model guides conflict with newer API specifications. This plan does not pick the
latest model, set tuning defaults, or claim measured provider latency.

The milestone's synthetic contract profiles cover the structural differences above without
adding hosted support: request-based TTS, context-cancelled TTS, batch-completion TTS, and
segmented STT. They cannot prove external compatibility. Each future hosted integration still
needs its own option/auth review, recorded protocol fixtures and tagged live acceptance.
