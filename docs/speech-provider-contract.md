# Semantic speech provider contract

Status: proposed design, researched and locally reviewed on 2026-09-19 against `51a9a17`.
The user requested research and an implementation plan. No runtime changes or provider
interoperability checks were performed. Implementation is tracked in
[Simpler speech integrations](milestones/simpler-speech-integrations.md).

## Problem and decision

An integration author should implement speech operations and publish speech results. Today,
Call Engine calls vendor-shaped encoders, starts a separately configured transport, decodes
its messages, and coordinates provider speech IDs and cumulative playback offsets. The local
Morse providers manufacture JSON control messages to use that same path.

Introduce one documented session behaviour for each capability, STT and TTS. Configuration
returns a typed descriptor; a supervised provider session accepts semantic operations and
emits typed events through a shared delivery helper. Network framing, provider control
commands, response parsing and upstream request correlation remain inside the provider.
Transport helpers remain available as implementation details. An integration may use several
modules where appropriate; it does not have to implement or register a second public transport
behaviour.

Keep this boundary in `vxpipe_call_engine` for this milestone. Keep the existing capability
processes as the owners of call attribution, policy, bounded turn queues and playback. Avoid
creating another call state machine or a new umbrella application just to rename callbacks.

## Research and evidence

### Repository findings

Paths below are relative to `apps/vxpipe_call_engine/lib/vxpipe/call_engine/` unless linked.

| Evidence | Consequence for the design |
| --- | --- |
| `provider/speech_to_text.ex` and `provider/text_to_speech.ex` require connection maps, codecs and decoders; TTS additionally requires separate speak/flush/interrupt encoders. | The provider boundary currently includes a particular wire interaction pattern. Replace those public callbacks with operations. |
| Both `provider/*/transport.ex` behaviours require a separate process interface. `provider/morse_code_stt/transport.ex` and `provider/morse_code_tts/transport.ex` encode/decode JSON despite running locally. | A native Morse session is a concrete proof that the new boundary removes work. |
| `capability/text_to_speech.ex` owns `:awaiting_start`, `:streaming`, `:discarding`, `:interrupting`, sink draining, provider speech IDs and cumulative session offsets. | Preserve sink draining and turn policy; move vendor boundary/cancellation bookkeeping into the provider. |
| `capability/speech_to_text/state.ex`, `transport_connector.ex` and `policy_preparation.ex` connect sessions asynchronously and bind them to privacy intervals. | Replacing a transport with a session must retain preparation/adoption order, fresh readiness and cancellation of superseded startup. |
| `plan_startup.ex` resolves credentials, reads separate provider/transport settings, composes usage and credential-scoped cache identity, and creates both runtime structs. | Simplification includes startup/configuration, with the existing credential source and scope retained. |
| `readiness/provider.ex` declares an absent `readiness_mode/0` a failure although the old behaviours label the callback optional. | Replace this mismatch with one explicit ready event and documented evidence. |
| `usage/text_to_speech_attempt.ex` and capability tests distinguish rejected Speak from accepted Speak followed by failed Flush. | Operation admission and actual provider submission must remain separate accounting facts. |
| [Speech transport privacy](speech-transport-privacy.md) documents credential exposure from an earlier socket dependency and the current bounded Mint transport. | Reuse that transport where it fits. Preserve redaction, active-once reads, cancellation and deadlines. |
| [TTS egress buffer](issues/tts-egress-buffer.md) records long-response truncation without backpressure. | A stream abstraction must preserve bounded delivery and responsive cancellation. |

These are source/test inspections, not fresh test results. Existing test names and target
files are mapped in the milestone so implementation can reproduce the relevant evidence.

### External primary sources

Reviewed 2026-09-19; these support the shape of the boundary, not claims of newly supported
providers or working live credentials. The subsequent user-requested comparison of Cartesia,
AssemblyAI, Rime, ElevenLabs and Gemini TTS/STT is recorded in
[Speech provider API comparison](speech-provider-comparison.md), including exact source links,
API/model differences and limits on what fits this milestone.

| Source | Observed contract | Design implication |
| --- | --- | --- |
| [Deepgram Flux quickstart](https://developers.deepgram.com/docs/flux/quickstart) | Flux provides turn detection, including optional eager-end and resumed-turn events. | Preserve turn evidence separately from transcript updates; optional events stay optional. |
| [Deepgram TTS Flush](https://developers.deepgram.com/docs/tts-ws-flush) | Flush asks the service to generate its buffered text. | Flush belongs inside a provider's speak implementation. It is not local playback completion. |
| [Cartesia TTS WebSocket](https://docs.cartesia.ai/api-reference/tts/websocket) | Generation, audio and cancellation are correlated by context; a distinct done event ends generation. | Engine request identity must be independent of provider speech/context IDs and cancellation encoding. |
| [Pipecat service events](https://docs.pipecat.ai/server/utilities/service-events) | Connection events apply to WebSocket services; HTTP services do not necessarily emit them. | Readiness means the selected session can accept work under its declared mode, not that every provider opened a WebSocket. |

The Deepgram Flush page describes its documented buffered TTS interface. It does not verify
the repository's `/v2/speak` Flux endpoint or `SpeechMetadata`/`SpeechInterrupted` mapping.
Preserve the current endpoint and model selection during migration; replay current fixtures
and run the existing tagged live checks before claiming hosted parity. A protocol discrepancy
is a recorded blocker for that adapter, not permission to silently switch API/model families.

## Proposed author-facing interface

Names below are proposed, not available APIs. Use `Speech.STTProvider`, `Speech.TTSProvider`,
`Speech.Descriptor`, `Speech.Session`, `Speech.Event` and `Speech.Output` under
`Vxpipe.CallEngine`. Keep each module in its own file.

| Required callback | Meaning |
| --- | --- |
| `configure(public_options)` | Pure validation; returns `{:ok, descriptor}` or a bounded configuration error. No connection or credential lookup. |
| `start_link(private_init)` | Starts the provider process when called by its owning supervisor; returns normal OTP startup results. Readiness arrives separately. |
| STT: `push_audio(pid, audio)` | Admits one bounded audio chunk matching the descriptor; returns `:ok` or a bounded error. |
| TTS: `speak(pid, request_ref, text)` | Admits one bounded complete-text request; returns `:ok` or a bounded error. Synthesis is asynchronous. |
| TTS: `cancel(pid, request_ref, playback)` | Requests cancellation with a typed, locally confirmed playback report; returns promptly. Terminal cancellation arrives separately for active generation. |
| `close(pid)` | Idempotent, bounded explicit shutdown; supervisor/monitor ownership guarantees cleanup if the call fails. |

This is four required functions for STT and five for TTS, including configuration and startup.
Standard GenServer callbacks are an implementation choice; a macro DSL or callback inheritance
tree is not required. Reusable process/network helpers should arise from the two existing
providers' demonstrated needs.

The descriptor contains validated provider-specific public settings, media format, safe usage
identity, explicit readiness evidence (`:initialized` or `:provider_acknowledged`), and TTS cache
identity. STT declares endpointing provenance (provider semantic detection, provider silence/gap
detection, external boundary required, or none), speech-start evidence and supported optional
eager/resume events. This is a small validated capability description, not arbitrary feature
flags. Identity values exclude credentials, URLs, headers and raw provider responses.
The initial contract preserves supported formats: STT linear16/Opus as advertised by the
selected provider; TTS mono little-endian linear16 at a supported sample rate. No implicit
resampling, new codecs or silent format conversion is introduced. Format validation also
distinguishes raw Opus packets from containerized Opus and raw PCM from WAV. Adapters perform
bounded rechunking/pacing where their wire protocol needs it. Do not universally require 48 kHz.

`private_init` contains the validated descriptor, private resolved credentials, trusted host
settings, and an opaque session event channel. Credentials are resolved at existing activation
boundaries; public options cannot choose a module, callback, endpoint or auth header. Each
session keeps its resolved credential snapshot. The current tenant override/platform inheritance
and pinned binding rules remain owned by the credential source.

The engine calls a shared `Speech.Session` facade. Providers implement the behaviour above;
the facade starts them through a named owning DynamicSupervisor, binds/monitors their lifetime
to the capability/preparation owner, enforces admission/deadlines, and projects typed events.
Do not synchronously run remote connection work in Room Authority or add a second turn queue.

### Example flow

```text
Caller audio -> existing ingress/policy -> STT session.push_audio(audio)
                                            |
                                    transcript / turn events
                                            v
                                   existing capability -> room

Existing TTS capability -> TTS session.speak(request_ref, text)
                                            |
                                  audio chunks / generation end
                                            v
                                 existing output sink -> playback
```

Morse STT calls its incremental decoder and publishes typed turn events directly. Morse TTS
advances its encoder and delivers bounded PCM chunks directly. Neither requires JSON, a fake
connection, a `Flush` command or a fake hosted provider ID. Deepgram sessions translate the
same operations to their actual protocol internally.

## Event and lifecycle contract

### Identity and order

The shared event channel binds the producer PID, fresh session generation and monotonic local
event sequence. TTS events also carry the engine-issued request reference; STT turn events
carry a stable session-local turn reference. The helper, rather than integration-authored
tuple construction, owns that envelope and its delivery acknowledgements. Multiple internal
workers serialize through the provider's event channel. Bind the session before releasing
early ready/audio events, including frames coalesced with a network upgrade.

Real provider request/operation IDs are optional bounded metadata and keep their existing usage
meaning. Local references never masquerade as provider IDs. Adapters reject duplicate/stale
upstream messages using upstream sequence/context information where available; the delivery
helper rejects repeated envelope deliveries. Generating new local sequence numbers cannot
deduplicate repeated upstream events by itself.

The capability ignores messages from retired sessions/requests and remains the authority for
participant, connection, activation and privacy-interval attribution. A provider never chooses
those identities or policy revisions. Existing downstream domain signals may remain internal
projections during migration; renaming every room event is unnecessary.

### STT

Events are `ready`, `turn_started`, `transcript_updated`, `turn_ended`, optional
`eager_turn_ended`/`turn_resumed`, and a safe session failure. Transcript text is the cumulative
snapshot for the identified turn. `turn_ended` carries its final snapshot and ends that turn;
a provider's finalized transcript segment alone does not prove the person finished speaking.
Adapters assemble segmented results when necessary and supply genuine endpointing evidence.

The conversational path requires provider-owned endpointing and the speech-start evidence
needed by its current barge-in behavior. A transcript-only or manually finalized provider is
rejected for this path until a separate endpointing/input-boundary design exists. Provider VAD
can be legitimate endpointing evidence, but a timed buffer commit is not automatically a user
turn. The comparison's Cartesia manual STT and ElevenLabs segment commits make this distinction
concrete. This milestone adds no VAD, timer-based invented turn ending, optional manual-finalize
callback without a consumer, or automatic eager-response policy. Preserve existing speech-start
barge-in and any existing eager/resume handling.

No permitted consumer means no STT session or submitted audio. A changed speech permission
interval requires the existing session replacement/preparation rules and fresh readiness;
unrelated policy changes retain the current session. Prepared sessions cannot publish into
the active interval before adoption. Closing/replacing a session discards its buffered results;
it does not flush forbidden audio into a final transcript. Preserve current counting/privacy
rules for usage without retaining denied text.

### TTS

Each request has one ordered lifecycle: admission, optional submission evidence, audio,
then exactly one terminal result (`completed`, `cancelled`, or safe failure). A rejected
request starts no usage attempt. A request admitted to the provider process is not yet proof
that text reached the upstream transport. Publish `input_submitted` exactly once when the
protocol write is accepted; a later Flush/send failure retains that evidence. For Morse,
successful encoder acceptance is local submission, explicitly locally measured.

No provider `speech_started` wire event is required: the first correctly attributed audio
chunk can establish generation. Request/operation metadata can arrive separately, including
for a zero-audio completion. `completed` means no more audio will be generated and all earlier
chunks have reached the sink acceptance boundary. A provider batch `done` or flush acknowledgement
is insufficient when more synthesis for the request can follow; provider-specific segmentation
and input-finalization logic establishes this terminal boundary. The capability calls the
existing sink's finish operation, then waits for its actual playback acknowledgement before finishing the
room turn or starting the next queued request. A provider event never asserts audibility.

Cancellation immediately invalidates old output at the engine boundary, clears the existing
pending turn queue as today, and interrupts the sink first. The shared output/session boundary
maintains a playback ledger from actual sink acknowledgements. `cancel/3` receives a typed
report with request-relative and session-total played milliseconds; only the adapter selects
and encodes the coordinate system its API needs. Never derive those counters from generated
byte counts. This also handles interrupting sink drain after generation has completed: clear
playback and update the ledger without emitting a second generation terminal event. The next
request retains the correct cumulative evidence. Cancellation is idempotent. Audio and terminal
races cannot resurrect a cancelled request.
Generated bytes already observed still count toward incurred usage even when playback drops
them; duplicate terminal events cannot settle usage twice.

The provider reports cancellation terminal only when it can safely isolate subsequent work.
It may cancel a context, stop a supervised request worker, or consume the old stream boundary
while suppressing stale output. An uncorrelated persistent stream cannot be relabeled as the
next request. No replacement request starts before safe terminal isolation. If isolation fails
by the bounded cancellation deadline, fail/close the session through the existing unavailable
path. Successful local cancellation proves stale-output isolation, not that an upstream job
stopped incurring charges. There is no automatic reconnect, replay, fallback or retry in this
milestone. A future request-based adapter can abort its owned HTTP/SSE worker and quarantine
late results without manufacturing provider cancellation acknowledgements.

### Flow control and ownership

Keep the current ingress frame/byte/age limits, TTS pending-request limit, one in-flight output
write and the bounded sink reservoir. `Speech.Output` owns the audio acknowledgement plumbing;
provider code delivers a chunk and awaits credit before producing/reading another. Waiting
occurs in an owned producer worker or asynchronous continuation, never in the control process
that must handle cancel/close. Keep the existing 15-second output acknowledgement deadline and
5-second public call bound; explicitly bound connect/cancel/close using current host deadlines.

Control events use bounded admission through the same session delivery boundary, with a small
explicit queue limit and safe overflow failure. Audio credit does not block cancellation or
terminal failure delivery. Do not hide an unbounded mailbox behind a stream or return success
from `push_audio` before a bounded input slot is actually acquired. Readiness/command waits
have no synchronous cycle through the capability, producer and sink.

Session processes and their request/network workers have explicit supervision ownership and
monitor the capability/preparation owner. Owner loss, cancelled startup and rejected policy
adoption close the entire allocated subtree. Sessions are temporary; supervision does not
silently restart into the old permission interval. `terminate/2` remains best-effort cleanup.

Preserve [transport privacy](speech-transport-privacy.md): no secrets, text, audio, raw provider
errors or headers in Inspect/status/crash reports or routine telemetry. Typed errors use fixed
categories; bounded provider identifiers/codes use the existing controlled metadata paths.

## Configuration, migration and alternatives

Keep inline Call Specs, schema version, stored plans and the public provider names unchanged.
`CapabilityCatalog` remains a closed mapping and validates selections without credentials or
network access. It delegates speech configuration validation to the new descriptor constructor;
new entries still require explicit option/credential review. Host configuration selects a
provider session and limits without requiring a separate transport module. Optional private
test/network settings cannot enter public plans.

Compose usage and TTS cache identity in `PlanStartup` from the descriptor plus the existing
tenant/selection/credential binding and version. Voice/model/audio settings still affect cache
identity. Cache hits never bypass current credential checks. Independent opening TTS, private
briefing, transfer preparation and source restoration use the same semantic session path.

Migrate one direction/provider at a time. Temporary engine-private bridges adapt the remaining
old providers; they are not selectable public providers and own no new room queue. Remove each
bridge as soon as its final provider migrates. Update trusted host configuration/tests in the
same checkpoint. No legacy persisted Call Spec format is added. Old internal transport modules
may remain as private implementations where useful, with no public selection or requirement.

| Alternative | Decision and implication |
| --- | --- |
| Only write a guide or add a macro over the old behaviours | Rejected: reduces typing but leaves wire messages and transport selection in the engine. |
| Return a complete audio binary or lazy Enumerable | Rejected as the sole contract: hides streaming ownership, cancellation and backpressure; a request worker may adapt such a source internally with explicit bounds. |
| One generic speech behaviour with optional callbacks for everything | Rejected: STT ingress and TTS output have different operations and lifecycle contracts. |
| Replace all providers/capabilities at once | Rejected: makes attribution, privacy and output regressions hard to isolate and leaves no usable intermediate checkpoint. |
| Introduce a speech umbrella package immediately | Deferred: current consumers and policy adapters are in Call Engine; package extraction is a separate dependency decision after the API is proven. |
| Add the compared hosted providers to prove generality | Deferred: requires new auth/model/product support. Use request-style, context-cancellation, batch-completion and segmented-transcript test profiles as bounded structural counterexamples. |
| Treat Gemini Live as standalone STT plus TTS | Rejected for this scope: Live also owns model generation, context and tools; it requires a separate realtime-agent boundary decision. Dedicated Gemini TTS remains a plausible request-based adapter. |
| Add incremental text/manual STT finalization to the baseline | Deferred until there is an authorized consumer. Complete-text synthesis covers current callers; manual STT needs an explicit boundary owner, rather than treating any segment commit as a turn. |

## Verification and review

The milestone maps executable acceptance to each migration checkpoint. Shared contract tests
must exercise an independently supplied provider, not merely repeat helper internals. Morse
retains independent signal fixtures; Deepgram retains recorded/local wire and separate live
lanes. A request-style test provider demonstrates that neither persistent WebSockets nor
provider speech-start/cumulative-offset messages are mandatory.

Local design review on 2026-09-19 covered callback count, config/auth separation, supervision,
early-event ordering, usage after partial submission, cancellation isolation, backpressure,
STT privacy intervals, cache identity and prerequisite order. It corrected a too-small
`start/speak/cancel` sketch by specifying accounting and terminal-isolation evidence. This is
planning evidence only; no independent-agent review, live-provider success or implemented
contract is claimed. The wider provider review additionally caught segment-final/turn-end,
batch-done/request-end, packet/container and Gemini Live ownership distinctions; these are now
explicit in the descriptor, lifecycle rules and milestone conformance tasks.
