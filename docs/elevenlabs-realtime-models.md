# ElevenLabs Realtime speech-to-speech

The standalone Realtime adapter selects `eleven_realtime_v1_mini` (recommended)
or `eleven_realtime_v1_max` through the `elevenlabs` speech-to-speech provider.
It takes the existing ElevenLabs API-key credential, voice (default `brian`),
agent prompt and room-owned function tools. It does not provision hosted agents
or require an agent ID.

## Native turn detection

ElevenLabs runs semantic turn detection on the continuous 24 kHz mono PCM input.
No local VAD, Silero model, separate speech recognizer, or explicit activity
boundary is required. The adapter advertises provider-controlled turns only;
`turn_control: "external"` and local detector options are rejected.

The Realtime API emits native speech-start/stop and transcription events. The
adapter retains their private item identity and assigns an engine-owned opaque
caller turn. Final transcription and native stop evidence settle that caller
turn. Output responses have distinct references and require the engine's normal
output authorization; caller input alone never authorizes playback.

## Connection and ownership

The adapter implements `Speech.STSProvider`. Its local startup is bounded;
a supervised worker requests a short-lived credential from
`POST /v1/convai/realtime/client_secrets`, using the private API key in
`xi-api-key`. The configured model, voice, prompt, tools and audio settings are
sent in that request. The private Mint WebSocket connects to
`wss://api.elevenlabs.io/v1/convai/realtime` with the ephemeral Bearer credential.
Readiness waits for the selected model, PCM format, input transcription and
native-turn configuration to be acknowledged. Credentials, raw provider errors and protocol payloads are not
logged or exposed through public descriptors.

Each allocation retains one connection. The owning speech supervisor handles
shutdown, owner loss and abandoned preparation. Disconnection ends the allocation;
there is no undocumented replay or session-resumption claim. ElevenLabs' documented
session duration defaults to 600 seconds. Interrupted-history reconciliation is
not advertised. A connection retains one input authorization context. Native
stop events do not prove that the provider has consumed every buffered PCM byte,
so the descriptor declares `input_cutover: :close`. Hold and relevant policy or
presence changes close the allocation at the boundary, before delayed caller
events can acquire a new epoch. Changed-context input also closes before wire
admission as a defensive check. A fresh allocation is required; the adapter
does not automatically reconnect or replay history. Quiescence is never claimed
after microphone audio has been accepted.

PCM delivery uses one outstanding engine credit, bounded pending audio, immutable
final transcripts, and local playback settlement. Cancellation fences buffered and
late audio for the exact response. Tool references remain private; the room owns
allowlisting, schema checks, execution and result authorization.

## Protocol decisions and alternatives

Sources reviewed on 2026-10-26:

- [ElevenLabs model catalog](https://elevenlabs.io/docs/overview/models)
- [Realtime compatibility guide](https://elevenlabs.io/docs/eleven-agents/guides/openai-realtime-compatibility)
- [Client-secret API and configuration schema](https://elevenlabs.io/docs/api-reference/conversations/create-client-secret)

The compatibility guide documents the browser authentication flow; the same
client-secret exchange and Bearer WebSocket authentication passed a short direct
provider probe. A successful connection is not complete conversational acceptance.

The first probe showed that `response.created` omitted client-supplied response
metadata. A subsequent audio probe received a response before the adapter's
explicit request even though the session echoed `create_response: false`.
Consequently the audio path uses native automatic generation. A response is
associated with a pending provider-detected caller origin, never a freely mutable
latest-input context. Explicit text/opening/tool continuation requests are
serialized. Ambiguous or unsolicited identities fail the allocation instead of
borrowing a new authorization origin.

Queued text/opening requests exclude new microphone admission until the request
has a provider response identity. A queued tool continuation still accepts the
same caller's PCM so native endpointing can finish, and waits for caller-final and
native-response obligations before dispatch. Its origin stays pinned even when
trailing PCM remains. Observed conflicting native/explicit identities fail closed;
the API does not guarantee metadata echo. Caller-final and native-response obligations have
bounded deadlines. A local transport test also verifies acknowledgement-based
frame delivery so incoming WebSocket bursts cannot bypass the session's bounds.
The initial profile allows 20 seconds for startup and 30 seconds for caller-turn
or response obligations. A caller turn's deadline begins at speech start, so long
utterances or missing terminal evidence close the allocation. Pending PCM is
limited to 512 KiB per response (2 MiB while verifying a fixed opening).

Rejected alternatives:

- Reusing the historical ElevenAgents adapter would restore agent provisioning
  and a different protocol.
- Pointing GPT-Live at this endpoint would use incompatible session and delegation
  events. Only the shared speech channel and Mint transport are reused.
- Local VAD would duplicate ElevenLabs' work, consume local inference resources
  and violate this integration's required native-turn behavior.
- Assuming OpenAI compatibility proves metadata echo or suppresses native
  responses contradicted the initial live probes.

## Verification and live selection

Ordinary tests use synthetic credentials and a fake transport. They cover public
model selection, private configuration, native turns, response identity, output
credit and cancellation, and tool-result association. Catalog and configured
credential tests cover both models; they do not establish hosted behavior.

Run only the new ElevenLabs STS cases, with no telephony or fixture generation:

```sh
bin/livetests run --only live_elevenlabs \
  apps/vxpipe_call_engine/test/integration/elevenlabs_realtime_test.exs
```

The runner supplies credentials to its child process. Only `ELEVENLABS_API_KEY`
is needed by these tests. They reuse committed 24 kHz speech samples and bound
session time and output. Selecting the entire `live_elevenlabs` lane would also
run the existing STT/TTS cases and costs more. Use a single test location while
investigating a concrete failure.

Hosted acceptance, final independent review and completion evidence are tracked
in the [milestone](../labnotes/milestones/elevenlabs-realtime-models.md). Initial
probe failures remain recorded in the associated labnotes; passing configuration
and unit tests must not be represented as full live acceptance.
