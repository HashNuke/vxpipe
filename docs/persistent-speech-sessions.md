# Persistent speech sessions for calls

## Decision

Remote TTS, STT and STS capabilities used in calls use realtime models and
stream over a connection owned by that capability's allocation wherever the
provider supports a persistent session. Successive
utterances or recognized turns reuse the connection. A long-lived Elixir process
around a new HTTP request or WebSocket for every utterance does not satisfy this
contract. Local Morse synthesis/recognition has no network connection to retain.

The user explicitly retains Google AI Studio streaming HTTP TTS as an exception:
it streams audio during synthesis but takes one complete text request per
utterance. Its HTTP client may reuse TCP/TLS connections through pooling; that
is different from a persistent synthesis session. Keep the capability-owned
request supervisor, credit, cancellation and exact completion checks. Do not
disable Google TTS or substitute a different model/provider for this reason.

The scope is the participant's capability, including its permission interval and
configuration. Persistent realtime sessions are not shared between participants
or calls; the Google HTTP exception may use its client connection pool. Removal,
replacement, failed startup and owner loss must close the owned transport. A
provider may require bounded session rotation or resumption; that remains an
explicit provider lifecycle, not routine per-turn reconnection. A disconnected
session must never silently replay accepted audio/text or restore a revoked
capability. Existing documented failure/resumption policies still apply.

## Utterances and cancellation

The TTS API continues to accept bounded complete utterances. Incremental audio
delivery and persistent transport are required; this change does not introduce
a new token-by-token engine input API. Each utterance has an identity and a
provider-backed completion boundary. Flush/finish an utterance without closing
the healthy socket. Cancellation must fence delayed audio and terminal messages
from the cancelled utterance before another one can publish output.

Provider control remains responsive while output waits for Channel credit. Bound
pending messages, PCM, active/retired context state, setup, generation and
cancellation. Keepalive must use the provider's documented protocol and must not
generate audible text. Readiness must reflect the transport's actual setup
contract; process initialization alone is not evidence of an open remote socket.

## Audit at the start of implementation

| Provider | TTS | STT / STS |
| --- | --- | --- |
| MorseCodeApi | New WebSocket per utterance; requires repair | STT already uses one socket across committed segments |
| ElevenLabs | HTTP audio stream per utterance; requires repair | VAD STT and agent STS retain sockets; historical manual STT reconnects per acoustic turn and requires repair |
| Cartesia | HTTP audio stream per utterance; requires repair | STT retains a socket across turns |
| Google AI Studio | Interactions audio stream per utterance; explicitly retained exception | Live STT retains/rotates sockets; Live STS uses resumption |
| Deepgram | Persistent TTS socket | Persistent STT socket |
| Rime | Persistent TTS socket | No advertised STT/STS capability |
| OpenAI | No advertised dedicated TTS capability | GPT-Live STS retains a socket, with its explicit reseed lifecycle |
| Local Morse | Local synthesis | Local recognition/conversation |

This is a code-path audit, not a new live-provider certification. Existing
provider idle/lifetime limits and evidence gaps remain material. Persistence
does not promise that a network connection can live indefinitely.

## Protocol choices and rejected alternatives

- ElevenLabs: use the
  [multi-context TTS WebSocket](https://elevenlabs.io/docs/api-reference/text-to-speech/v-1-text-to-speech-voice-id-multi-stream-input)
  to separate utterance completion from socket closure and correlate output.
  For a complete utterance, flush then close its context; drain accepted audio
  before its final event while keeping the socket open. Verify more than five
  successive utterances to catch upstream context leaks. Choose supported
  realtime models explicitly. Eleven v3 uses a different dialogue protocol;
  existing pinned v3 TTS selections must fail configuration clearly. Catalog,
  configuration and activation must agree, without HTTP or model substitution.
- Cartesia: use its
  [TTS WebSocket](https://docs.cartesia.ai/api-reference/tts/websocket), with
  context identity, completion and cancellation. Preserve the selected API
  version's exact request/response schema.
- MorseCodeApi: the single-context endpoint ends with socket EOS, so add the
  compatible multi-context endpoint to the Go service before switching the
  adapter. Preserve existing HTTP and single-context clients. No persistence,
  additional authentication or whole-utterance caching is required.
- Google: the currently selected AI Studio TTS endpoint is documented as
  [request-based streaming](https://ai.google.dev/gemini-api/docs/speech-generation).
  Google distinguishes exact TTS recitation from conversational Live output.
  Prompting a conversational model to repeat text is not an equivalent TTS
  adapter. Google Cloud's streaming speech API is a separate integration and
  credential decision; it must not be silently substituted for AI Studio. The
  user chose to retain the existing streaming HTTP TTS capability.

HTTP connection pooling does not create a persistent synthesis session. A global
socket pool would cross ownership boundaries. Estimated audio length or a local
silence timer is not provider evidence that a TTS utterance completed.

Historical manual Scribe selections retain their local acoustic boundaries and
serialized commits, but keep the socket after each acknowledged final segment.
Preserve accepted PCM order and actual inter-turn silence exactly once; do not
invent padding or lengthen the acoustic endpoint to compensate for stream gaps.
Google/ElevenLabs/OpenAI STS resumption policies are not replaced by blind retry.
Deepgram's existing persistent TTS transport also needs bounded generation and
cancellation waits if a healthy socket stops providing terminal evidence.

## Acceptance

The implementation ledger is the
[persistent speech milestone](../labnotes/milestones/persistent-speech-sessions.md).
Require observable reuse across two utterances on one transport, cancellation
followed by another utterance, stale-frame isolation, idle keepalive, output
credit, owner-loss cleanup and explicit connection failure. STT/STS repeated-turn
checks must retain their existing connection and lifecycle behavior.

Run protocol fixtures and actual local Morse interoperability, followed by the
umbrella and Lean verification lanes. Deploy and verify the Go multi-context
endpoint before publishing the Vxpipe adapter that requires it; use the local
origin override while developing against an undeployed endpoint. Fake transports establish local lifecycle
contracts; they do not establish third-party hosted compatibility. Record any
unavailable live-provider checks rather than calling them verified.

### Focused live-provider verification

Run changed behavior directly through the speech session API using
`bin/livetests run`, explicit owning-app integration paths, and the provider tag.
These checks use no telephony or configured room. Thin test transports delegate
to the real sockets and report their creation, so two utterances must reuse the
actual transport, not merely the same session handle.

| Check | Isolated integration file | Selection |
| --- | --- | --- |
| ElevenLabs TTS cancellation, subsequent phrases, PCM and usage | `elevenlabs_text_to_speech_test.exs` | `--only live_elevenlabs` |
| Cartesia TTS cancellation and subsequent phrases | `cartesia_text_to_speech_test.exs` | `--only live_cartesia` |
| Morse TTS cancellation, repeated utterances and independent PCM decoding | `morse_code_api_tts_test.exs` | `--only live_morse_code_api` |
| Deepgram TTS cancellation followed by successful generation | `deepgram_flux_text_to_speech_test.exs` | `--only live_deepgram` |
| Manual Scribe repeated recording on one socket | `elevenlabs_speech_to_text_test.exs` | `--only live_scribe_repeat` |
| Manual Scribe forty seconds of silent PCM followed by speech | `elevenlabs_speech_to_text_test.exs` | `--only live_scribe_silence` |
| Manual Scribe distinct recordings on one socket | `elevenlabs_speech_to_text_test.exs` | `--only live_scribe_distinct` |

Files are under `apps/vxpipe_call_engine/test/integration/`. For example:

```shell
bin/livetests run --only live_cartesia apps/vxpipe_call_engine/test/integration/cartesia_text_to_speech_test.exs
```

The manual Scribe checks reuse committed public audio fixtures. Do not generate
new samples or invoke a phone call for this acceptance. Local fake-peer tests
cover missing terminal responses, stale messages and bounded failure deadlines;
live checks verify normal provider responses and cancellation interoperability.
The milestone and checkpoint labnotes record which checks actually passed.
