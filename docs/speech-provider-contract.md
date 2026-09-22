# Semantic speech provider contract

Status: normative provider contract, synchronized on 2026-09-22. The baseline
[Simpler speech integrations](milestones/simpler-speech-integrations.md) migration
has all nine checkpoints accepted. The separate
[Agent speech-to-speech milestone](milestones/agent-speech-to-speech.md) remains
incomplete. Local adapter and embedded-call evidence does not establish hosted
Google interoperability or complete STS room lifecycle acceptance.

The original research below dates to 2026-09-19 against `51a9a17`. The historical
[startup-isolation defect](speech-startup-isolation.md),
[adoption repair and load evidence](speech-adoption-fix.md),
[deadline/fault evidence](speech-deadlines-and-failure-containment.md), and
[native STT verification](native-stt-contract.md) record the migration's evolution.
The [scoped ownership contract](speech-session-ownership.md) supersedes the rejected
global execution prototype and applies to all three speech capabilities.

The [STS lifecycle below](#sts) is part of this contract. Its companion
[output admission decision](sts-output-admission.md) and
[provider author guide](speech-integration-guide.md#speech-to-speech-providers)
give implementation examples. STS shares scoped lifetime and PCM credit without
a complete-text TTS request.

## Problem and decision

An integration author should implement speech operations and publish speech results. Before
the baseline migration, Call Engine called vendor-shaped encoders, started a separately
configured transport, decoded its messages, and coordinated provider speech IDs and cumulative
playback offsets. The local Morse providers manufactured JSON control messages for that path.

Use a distinct documented session behaviour for each capability: STT, TTS and STS. Configuration
returns a typed descriptor; a supervised provider session accepts semantic operations and
emits typed events through reusable delivery helpers with private per-allocation state.
Network framing, provider control
commands, response parsing and upstream request correlation remain inside the provider.
Transport helpers remain available as implementation details. An integration may use several
modules where appropriate; it does not have to implement or register a second public transport
behaviour.

Keep this boundary in `vxpipe_call_engine`. Keep the existing capability
processes as the owners of call attribution, policy, bounded turn queues and playback. Avoid
creating another call state machine or a new umbrella application just to rename callbacks.

## Research and evidence

### Historical repository findings (2026-09-19)

Paths below are relative to `apps/vxpipe_call_engine/lib/vxpipe/call_engine/` unless linked.
They describe the pre-migration source, including paths since removed; they are not a map of
the current implementation. Present-tense observations in this table refer to that research.

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

## Author-facing interface

The STT/TTS APIs and their room consumers implement scoped ownership. STS extends the same
boundary with its own conversational lifecycle; its remaining acceptance work is tracked
separately. Use `Speech.STTProvider`, `Speech.TTSProvider`, `Speech.STSProvider`,
`Speech.Descriptor`, `Speech.Session`, `Speech.Event` and `Speech.Output` under
`Vxpipe.CallEngine`. Keep each module in its own file.

| Required callback | Meaning |
| --- | --- |
| `configure(public_options)` | Pure validation; returns `{:ok, descriptor}` or a bounded configuration error. No connection or credential lookup. |
| `start_link(private_init)` | Performs bounded local startup beneath its owning speech scope and returns promptly; remote preparation is asynchronous. Readiness arrives separately. |
| STT/STS: `push_audio(pid, audio)` | `:ok` proves actual acceptance into a bounded provider/transport slot. `{:error, :busy}` proves no acceptance and preserves the session. Other failures retire the allocation safely. |
| TTS: `speak(pid, request_ref, text)` | Admits one bounded complete-text request; returns `:ok` or a bounded error. Synthesis is asynchronous. |
| TTS: `cancel(pid, request_ref, playback)` | Requests cancellation with a typed, locally confirmed playback report; returns promptly. Terminal cancellation arrives separately for active generation. |
| STS: `push_text(pid, text_ref, text)` | Admits explicit text through the ordered input slot; publish matching `input_submitted` evidence on protocol acceptance. This is not transcript mirroring. |
| STS: `input_activity(pid, :started \| :ended)` | Ordered external turn-control evidence, only in a declared external/hybrid mode. It does not select the transcript source. |
| STS: `interrupt(pid, turn_ref)` | Promptly fences the identified output; retain its private identity until terminal isolation. |
| STS: `send_tool_result(pid, call_ref, result)` | Delivers a bounded, room-authorized result to the matching private tool-call association. |
| `close(pid)` | Idempotent, bounded explicit shutdown; supervisor/monitor ownership guarantees cleanup if the call fails. |

This is four required callbacks for STT, five for TTS, and eight for STS, including
configuration and startup. The provider callback is `start_link/1`; the shared provider
helpers expose `start_link/2` to validate and invoke it with a module and private init.
Standard GenServer callbacks are an implementation choice; a macro DSL or callback inheritance
tree is not required. Reusable process/network helpers should arise from demonstrated
provider needs.

An STS descriptor may opt into `response_start?: true`. That mode adds the optional
`submit_input(pid, response_context, operation)` callback and makes it mandatory
for that allocation's input; there is no fallback to the legacy callbacks. The
operation is exactly `{:audio, pcm}`, `{:text, text_ref, text}` or
`{:activity, :started | :ended}`. The engine supplies an opaque reference with
each ordered `Session.push_audio/3`, `push_text/3` or `input_activity/3` using the
closed `response_context: ref` option. Missing/malformed contexts are rejected
before delivery. The channel stages first use before calling the provider,
accepts it only after the exact callback succeeds within its deadline, and rolls
back rejected first use. A provider can emit an early event without blocking its
callback, but the channel withholds consumer delivery until input acceptance;
if that input is rejected after emitting its own or unattributable semantics,
the allocation fails closed without publishing them. A response start explicitly
bound to a different, previously accepted context survives that rejection and
is delivered in order. Input acceptance and event validity are not output
authorization. Accepted origins currently have an interim 16-context allocation
bound; exact response/tool holds and authorized origin retirement remain open.
The STS capability proposes one opaque context before opted-in audio, typed
text or activity input. It commits the context only after that input accepts
and reuses it only while allocation, source, input epoch and both directional
audio-policy intervals remain unchanged: input is the sending human's outgoing
interval, output is the receiving human's incoming interval. Direct policy
revocations also advance a separate origin policy revision, so a later regrant
cannot inherit an older snapshot's context. Framed microphone input carries
its release epoch through the same path. Both audio directions must be
permitted at input acceptance.
This is pre-input origin binding, not a grant-time policy queue or Google
interaction association; those remain open.
The unadvertised Google fixture profile can opt into this callback for local
association tests. It binds the first accepted context before wire input and
continues it across `IN_PROGRESS`; a different context is rejected before
wire send while cutover is unproven. This is not Google response-start emission,
policy-qualified output, or hosted interoperability approval.
Direct legacy input callbacks are rejected for that opted-in allocation; only
the context-bearing ordered callback can send input to its wire.

The descriptor contains validated provider-specific public settings, media format, safe usage
identity, explicit readiness evidence (`:initialized` or `:provider_acknowledged`), and TTS cache
identity. STT declares endpointing provenance (provider semantic detection, provider silence/gap
detection, external boundary required, or none), speech-start evidence and supported optional
eager/resume events. STT providers that support finite fed input for the agent-output STS mode
declare `finite_input?: true` (default false, legal only for STT) and export the
optional `finish_input/1` operation. Human conversational onset and turn-end
requirements are unchanged by it. This is a small validated capability description, not arbitrary feature
flags. Identity values exclude credentials, URLs, headers and raw provider responses.
STS additionally requires separate validated `input_format` and output `format`
PCM declarations; deriving microphone format from generated output is not safe.
The STT/TTS descriptor's `input_format` stays `nil`. See the
[STS authoring contract](speech-integration-guide.md#speech-to-speech-providers).
`Descriptor.new/1` validates this closed metadata shape, and the engine repeats
validation before starting a provider. Provider-specific settings remain the provider's
pure-validation responsibility. Readiness, endpointing and optional events must agree with
the descriptor at delivery. Request IDs are optional, valid UTF-8 with 1..256 bytes,
and excluded from inspection.
The initial contract preserves supported formats: STT linear16/Opus as advertised by the
selected provider; TTS mono little-endian linear16 at a supported sample rate. No implicit
resampling, new codecs or silent format conversion is introduced. Format validation also
distinguishes raw Opus packets from containerized Opus and raw PCM from WAV. Adapters perform
bounded rechunking/pacing where their wire protocol needs it. Do not universally require 48 kHz.
WebRTC classifies channel mode from each Opus packet rather than SDP FMTP. Its bounded
per-connection decoder accepts mono/stereo packets and normalizes provider input to the
selected strict mono format. The [stereo input issue](issues/webrtc-opus-stereo-input.md)
records the accepted conversion and its verification; this does not make provider PCM stereo.

`private_init` contains the validated descriptor, private resolved credentials, trusted host
settings, and an opaque session event channel. Credentials are resolved at existing activation
boundaries; public options cannot choose a module, callback, endpoint or auth header. Each
session keeps its resolved credential snapshot. The current tenant override/platform inheritance
and pinned binding rules remain owned by the credential source.

The engine calls reusable `Speech.Session` functions with an explicit owned scope. In rooms,
each scope is a temporary speech capability subtree beneath the existing room capability
supervisor; standalone callers provide their own local scope. Its session supervisor,
provider, event/control state and I/O workers remain local. No application-wide speech
supervisor, execution queue or implicit fallback participates in this boundary.

Admission reserves bounded local capacity and returns an allocation handle in `:starting`
state; observing authenticated readiness is separate. The startup/adoption deadline starts at
API entry, includes queue wait and settles at activation/adoption; it is not a session TTL.
Later commands have independent API-entry deadlines. Every shared ancestor starts only
lightweight local children; blocking provider/credential/network work runs asynchronously
beneath the allocated subtree, preserving existing authorization boundaries. Lifetime
owner, event consumer and preparation lease/adoption authority are explicit. Cancellation
invalidates queued attempts before provider creation; adoption rechecks lease/generation and
does not reparent the tree. See the ownership proposal for exact-purpose stop handles,
participant/connection teardown and preservation of the existing room control APIs.
Opaque private-init data remains owned until asynchronous handoff, cancellation or expiry;
returning `:starting` does not end its lifetime. Supervisor/status/crash output must stay safe.

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
same operations to their actual protocol internally. Morse speech sessions are published
under the credential-free `Vxpipe.Providers.MorseCode` namespace (`STTSession`, `TTSSession`,
`STSSession`); the manifest declares all three without credential entries.

## Event and lifecycle contract

### Identity and order

Each allocation's private event channel binds the producer PID, fresh session generation and monotonic local
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

Native events are `ready`, `speech_started`, `transcript`, `turn_ended`, optional
`eager_turn_ended`/`turn_resumed`, and a safe session failure. Transcript text is the cumulative
snapshot for the identified turn. `turn_ended` carries its final snapshot and ends that turn;
a provider's finalized transcript segment alone does not prove the person finished speaking.
Adapters assemble segmented results when necessary and supply genuine endpointing evidence.
The existing room signal names `turn_started`/`transcript_updated` remain internal
projections during migration; the native helper does not expose both spellings.

Finite-input STT additionally emits fieldless `input_finished`, admitted only by
the declaring descriptor. `finish_input/1` returning `:ok` accepts finalization;
it is not completion evidence. The provider drains all accepted input and emits
every final segment before this ordered terminal marker, without later audio or
recognition events in the allocation. Repeated finalization must not duplicate
the marker. A segment endpoint, quiet period or successful callback is not this
proof. Consumers acknowledge the marker through the same channel/session boundary.

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

STT acceptance is independent of recognition completion. A consumer starts existing usage
accounting on `push_audio` returning `:ok`; later processing failure retains that accepted
work and settles the attempt once. Rejection creates no acceptance evidence. This does not
invent recognized duration or final-text measurements before real recognition evidence.
Checkpoint A proves these boundaries with a controlled deferred provider and the existing
usage accumulator; B owns the production room projection.

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
pending turn queue as today, and interrupts the sink first. The allocation's output/session boundary
maintains a playback ledger from actual sink acknowledgements. `cancel/3` receives a typed
report with request-relative and session-total played milliseconds; only the adapter selects
and encodes the coordinate system its API needs. Never derive those counters from generated
byte counts. This also handles interrupting sink drain after generation has completed: clear
playback and update the ledger without emitting a second generation terminal event. The next
request retains the correct cumulative evidence. Cancellation is idempotent. Audio and terminal
races cannot resurrect a cancelled request.
Generated bytes admitted into semantic audio envelopes still count toward incurred usage even
when a later fence drops playback; duplicate terminal events cannot settle usage twice.
Provider-private PCM that first arrives after the semantic fence is validated and discarded but
is outside the locally measured `generated_bytes` metric. Counting it while also guaranteeing
whole-scope failure survival would require committing a separate receipt outside the owned tree
before each wire acknowledgement. This contract keeps the single bounded Event/Audio evidence
path; submitted input remains the durable evidence of provider work in that interval.

The provider reports cancellation terminal only when it can safely isolate subsequent work.
It may cancel a context, stop a supervised request worker, or consume the old stream boundary
while suppressing stale output. An uncorrelated persistent stream cannot be relabeled as the
next request. No replacement request starts before safe terminal isolation. If isolation fails
by the bounded cancellation deadline, fail/close the session through the existing unavailable
path. Successful local cancellation proves stale-output isolation, not that an upstream job
stopped incurring charges. The shared boundary adds no implicit reconnect, replay, fallback or
retry. Provider-specific STS resumption has the explicit contract below. A request-based
adapter can abort its owned HTTP/SSE worker and quarantine
late results without manufacturing provider cancellation acknowledgements.

### STS

STS owns the conversational model session, not a composition of independent STT and TTS
providers. Its agent-owned capability subtree uses the same scoped allocation lifetime beneath
the room capability supervisor. The provider owns its wire protocol, private turn/tool IDs and
model context. The room owns source activation, policy, tool authorization, public identity,
transcript projection and transport-qualified playback evidence. Providers emit through the
scoped channel; they never publish room events directly.

#### Input, transcript selection and turn control

Declare distinct `input_format` and output `format`: raw, mono, signed little-endian linear16
PCM with independently validated sample rates. The descriptor also declares input/output
transcript coverage, selected and supported turn-control modes, output text settlement
(`:transcript_end` or `:generation_boundary`), readiness and `history_reconciliation?`.
Provider/hybrid control requires provider endpointing and speech-start evidence; external
control requires explicit consumer activity boundaries. Configuration fails if these facts
disagree. One exact permitted caller connection feeds each STS allocation, never mixed room
audio. Human STT and STS have independent bounded input delivery. Policy, source replacement,
hold and handoff must fence the old allocation's authority before new input is accepted.

Pin one transcript source for the caller and one for the agent before admission. Selected
human STT supplies caller text; otherwise require STS input transcription. The agent uses STS
output transcription, or explicit `output_speech_to_text` when that coverage is absent. That
agent-owned recognizer receives generated agent audio, not microphone audio, and resolves
through the existing STT provider registry and host enablement. No mid-turn fallback, duplicate
transcript source or transcription-driven second model response is permitted. Missing required
text must settle as a bounded, explicit failure/absence, not invented text or a provider switch.
Transcript selection is independent of the controller that triggers model responses; a text
delta is not speech onset or turn completion.

Output recognition also reuses ordinary STT public-option validation and tenant
credential resolution. Retain its private config/transport options separately
from the generator in `SpeechToSpeechRuntime.output_speech_to_text_private`,
then pass them through the existing recognizer PrivateInit handoff. Public
provider tuples and inspection must not expose that field. Earlier local Google
fake-wire room-allocation evidence established private startup wiring, not
finite-input completion. Current admission rejects Google/Deepgram sidecars
without implemented terminal proof; ordinary human STT private configuration and
fake-wire setup remain tested. Hosted finite-input support remains an open gate.

Before room allocation or credential resolution, PlanStartup compares complete,
validated public descriptors for STS generated output `format` and recognizer
STT input `format`. They must match exactly; a mismatch fails admission at the
agent's `output_speech_to_text` path. The microphone's separate `input_format`
and any independently selected human STT do not participate in that comparison.
Admission also requires `finite_input?: true` and an implemented `finish_input/1`;
the sidecar allocation boundary repeats that capability check. No output-side
conversion or silent option rewriting is implemented. Compatible
selections retain their private configuration unchanged. Direct low-level
allocations bypassing PlanStartup are outside this startup validation boundary.

An agent-output recognizer timeout, rejected finite-input finalization or provider
loss retires that recognition generation before the next reply is admitted.
Rejection does not imply the provider process will exit by itself. Replacement
readiness gates further output, and retired-session events cannot supply next-turn
text. At most ten consecutive restart attempts are allowed; only acknowledged
readiness resets that budget. Exhaustion ends the owning STS allocation explicitly
instead of silently switching to provider transcripts. Focused tests cover these
failure boundaries. Successful finite recognition also retires/replaces its
allocation before the next reply. Accumulate `turn_ended` finals in acknowledged
event order, deduplicating identical final references, with one space between
nonempty segments. Conflicting finals or more than 64 references/65,536 UTF-8
bytes (including separators) fail recognition without publishing partial text.
Only acknowledged `input_finished` after generation ends freezes this aggregate;
playback and policy still gate publication. Missing terminal evidence fails at
the existing deadline even when segments arrived. The recognition budget begins
after generation and playback complete; acceptance checks its fixed monotonic
expiry, so queued terminal proof cannot win merely by preceding the timer message.
This does not bound the separate wait for playback. Local Morse and controlled
fixtures prove this boundary; hosted finite-input support and full hosted
output-route acceptance remain explicit milestone requirements. See the
[settlement decision](output-recognition-settlement.md).

Locally measured agent-output recognition is a separate usage observation. Its
provider/model and PCM rate come from that reply's ready recognizer descriptor,
retained across recognizer replacement; it does not inherit the generator's
integration identity or successful playback outcome. Count only PCM accepted by
the recognizer, excluding rejected or dropped chunks. Linear16 duration uses the
selected rate and channel count, not a universal 24 kHz divisor; unsupported
encodings provide no invented duration. Timeout, rejected finalization, provider
failure or incomplete input yield failed recognition usage. Interruption cancels
unfinished recognition, while completed recognition keeps its own outcome.
Once generation and acknowledged finite-input completion are complete, later idle recognizer
loss cannot revoke that reply's text or successful usage while playback drains.
The failed recognizer still retires and replacement readiness gates the next reply.
These are local processing facts, not provider token counts or billing estimates.

Both `speech_to_speech` and `output_speech_to_text` persist through the ordinary
archive and usage store. Deploy migration `20260922171000_add_sts_usage_capabilities`
before writing them. It extends observation/amount constraints without deleting
existing usage; downgrade refuses incompatible STS rows rather than removing them.
STS observations use the archive's microsecond timestamp precision for exact
idempotent retries. Persisted timeout regressions verify identity, duration,
outcome and effective amount; full hosted/lifecycle usage acceptance remains open.

Events include `ready`, `speech_started`, `input_transcript`, `turn_ended`,
`output_transcript`, `output_completed`, `interrupted`, `input_submitted`, `tool_call` and
`tool_cancelled`, plus credited audio and safe failure. Acknowledge semantic events with
`Session.ack/2` before room handling. Input/output transcripts are distinct; generic STT
`transcript` events are invalid for STS. Tool-event admission is not tool execution authority:
the room still checks allowlisting, argument schema, active turn and current permissions.

The optional `response_started` STS event has a private model-response reference,
a positive signed-64 allocation ordinal and an opaque input authorization-origin
reference. A descriptor must opt into this event; caller `turn_ended` then only
settles caller evidence. The channel binds each start to an accepted or exactly
staged context before enqueue. Its allocation-local ordinal high-water mark
accepts gaps but rejects old, duplicate and conflicting starts; at most 16
starts may await disposition. The exact queued event must be acknowledged, and
its context accepted, before `Session.admit_output/2` grants the earliest pending
response. A busy output slot does not consume the start. The consumer may call
`Session.reject_response/2` on an acknowledged pending start to release only
that response and notify the provider with
`{:vxpipe_speech_response_discard, channel, turn_ref}`; this is not a whole-wire
interrupt. Non-opted STS providers retain caller-end admission. The STS
capability now acknowledges the exact opted-in start before admission, then
keeps its response reference, context and accepted source/epoch/policy
fingerprint in one bounded queue. It rechecks both audio directions and the
original fingerprint when granting, gates while accepted external activity or
provider-detected caller speech is unresolved, and rejects a denied queued
response by its own reference. Hold and policy/epoch changes retire stale
queued starts; a capability-local lifecycle revision prevents reuse of the
same supplied epoch after hold from reviving an old origin. Later regrant
cannot relabel it. The unresolved provider-speech gate is separately bounded
at 16 starts even when caller-event forwarding is suppressed; overflow closes
the capability before publishing caller-start evidence for the rejected turn.
This does not yet establish Google response emission or provider handling of
the discard message, complete cross-origin
cutover, or bounded origin retirement; those remain milestone requirements.
The provider must not announce a public speech turn for thought-only,
tool-only or text-only work.

Public caller, agent and tool IDs must be room-owned, with bounded associations to private
provider references qualified by allocation generation and exact source identity. Private
references, including their stringified forms, must not become public correlation IDs. Old,
duplicate or retired-generation evidence cannot create a new public turn. The milestone still
tracks complete execution/continuation adoption, upstream late-tool isolation,
agent-output retirement and complete lifecycle handling; the implemented publication paths do not prove this
entire requirement.

The provider-controlled embedded caller path now publishes one room-owned
`ParticipantTurnStarted`/`ParticipantTurnCompleted` pair, with partial/final caller text using
the same public IDs. Selected human STT retains its existing pair without a duplicate STS
publication. Caller evidence carries the exact source, ordered channel sequence, input epoch
and source audio/transcript intervals captured at onset. The room rechecks these against
current authority; text alone cannot open a public audio turn. A final transcript may arrive
after semantic end and retains the same IDs. Denied text cannot leak through the end-event
fallback; permitted turn completion still releases that association without text.

The capability and room each bound unsettled caller associations to 16. Both final text and
semantic end retire an association; a scalar sequence watermark rejects delayed/repeated
owner envelopes after retirement. Overflow fails the allocation. Hold invalidates the
room-owned input epoch; release after hold creates a new one, while repeated open calls are
idempotent. These checks fence forwarded owner evidence, not all late upstream provider
events first observed after release. Complete external/hybrid room control and provider-level
hold/transfer isolation remain milestone work. See the
[caller-publication decision](sts-caller-publication.md) for evidence and limits.

Tool publication now creates a room-owned invocation ID and command/turn IDs,
including tool-only turns. Concurrent pending tools in the same private turn
share its public turn IDs; an existing exact-source audio turn supplies those
IDs when available. Raw private key types remain distinct: a binary spelling
of a reference cannot acquire that reference's association. Execution context,
completion, failure and cancellation use the started public IDs. Active duplicate
calls and unknown/wrong-agent cancellations do not create additional work/events.

Both capability and room bound pending tool associations to 16. Capability
overflow ends the allocation explicitly; room saturation rejects excess calls
without evicting admitted work. The capability forwards acknowledged typed tool
events with channel sequence, exact input identity, input epoch and source audio
interval. Legacy unqualified tool-owner tuples cannot admit or cancel work.
Admission requires the current agent, exact source, open input epoch and current
audio permission; both boundaries recheck association evidence before delivering
a result. Source loss, replacement, hold, epoch retirement or a revoked/regranted
audio interval suppresses late provider delivery and public settlement.

Cancellation retains its original admission scope: it may retire that matching
association after epoch change, but cannot publish under the new source/epoch.
Hold retires provider associations even when the provider emits no cancellation.
A room-owned scalar sequence watermark rejects repeated or delayed forwarded
envelopes after settlement; capability replacement resets the watermark and
associations. This avoids an unbounded set of completed call IDs. It does not
deduplicate upstream events that adapters relabel with fresh semantic sequences,
or establish safety for old evidence first observed after a new input epoch.
Those upstream cases remain explicit acceptance gates.

The current host execution path uses the existing supervised Invocation registry
and workers beneath the exact STS capability tree. Its 16-record budget includes
running work and retained terminal outcomes after provider associations retire.
Ordinary interruption leaves accepted work running; capability/tree/room-owner
loss ends local workers. The five-second execution deadline reports unknown,
not proof of remote rollback. An engine-private bridge retains completion leases;
public delivery or an ordinary provider result does not consume them.

The original absolute submission deadline applies before and after preparation
and again when the worker handles begin. A timed-out submission cannot become a
new execution when stalled preparation resumes; expired prepared workers are
removed without an accepted invocation record. Formatted invocation crash/status
reports redact arguments and diagnostic messages; privileged raw VM inspection
is not protected by this formatter.

This remains incomplete adoption: correlated running acknowledgement, private
continuation commit receipts, blocking/nonblocking model admission, full schema
checks and supported tool-binding coverage are milestone tasks. Until commit
receipts exist, retained completions occupy capacity for the allocation lifetime.
The existing active-call final-result path is an incremental implementation, not
acceptance of the final conversation protocol. See [STS tool lifecycle](sts-tool-lifecycle.md).

Provider cancellation retires the provider call/speech association; ordinary
speech interruption does not authorize cancellation of an already-submitted
engine invocation. The approved [tool execution model](tool-execution-model.md)
requires bounded supervised execution and retained private completion, with
local workers ended on activation/room loss and uncertain submitted timeouts
reported as unknown. STS adoption of that complete execution/continuation
protocol remains open; a provider cancellation is not proof of remote rollback.

#### Output permission, credit and settlement

Output transcript events are bounded cumulative snapshots, not deltas for the
engine to concatenate. For `output_settlement: :transcript_end`, the provider
must emit `output_transcript` with `final: true`; omitted/false finality does not
settle text. The first acknowledged final freezes the matching output's text.
For `:generation_boundary`, acknowledged generation completion freezes the last
prior snapshot; missing text at that boundary fails explicitly. Later snapshots
cannot replace either settled form, and a different turn reference cannot settle
the current output. Upstream reference retirement remains a separate requirement.
Morse now emits the explicit final its descriptor declares.

Google assembles `outputTranscription` fragments into these snapshots, retaining
early text until output permission arrives. Its aggregate limit is 65,536 bytes;
overflow fails the allocation, and settlement/interruption clears retained text.
Ordinary `modelTurn` text, including thoughts, is not an audio-transcript source
and cannot substitute for missing output transcription. Raw caller activity end
permits a response independently of model `turnComplete`; it does not finalize
independently delivered caller text. The [controller decision](google-sts-controller.md)
records sequential fake-wire proof and the remaining correlation limits.
Google's local descriptor accepts provider and external control, not hybrid;
client activity controls require disabled automatic detection. External idle ends
and repeated boundaries do not send duplicate wire controls or reopen output.
These routine boundary checks do not establish interruption/history support.

For the pinned Gemini 3.x profile, `interimInputTranscription` is provisional and
`inputTranscription` is one final caller snapshot. Retain caller identity until
both final text and explicit caller activity end, independently of output playback,
typed submissions and model interruption. Neither final text nor model completion
can manufacture caller activity. The current local profile keeps one unfinished
caller and fails explicitly if another audio onset would make attribution
ambiguous; it does not assume FIFO final ordering or silently evict old evidence.
Sequential late-final room publication is covered, but successful overlapping-
caller correlation remains an open prerequisite, not an advertised capability.

In provider-transcript mode, public completion requires settled selected text,
acknowledged generation completion and matching sink playback. A late explicit final can finish an
already-drained output, but partial text alone cannot. Missing explicit finals
use one deadline starting at generation acknowledgement: five seconds by default,
with internal `output_transcript_timeout_ms` restricted to integer 1–30,000 ms.
Sink finalization consumes that same budget; absolute expiry is checked before
accepting a queued final. Partial updates never renew it. Final receipt, normal
settlement or interruption cancels it; the fresh engine output reference rejects a stale timeout. Expiry
closes the allocation with `output_transcript_timeout`, without partial speech
publication or transcript-source fallback. This bounds final-text acceptance,
not the instant of shutdown: an in-flight sink call may delay failure handling
within its existing 15-second call bound. Output-STT has its separate existing
recognition settlement/deadline, including explicit recognition failure followed
by completion without text. These local rules do not establish interrupted
provider-history reconciliation or remote hearing.

For an already-admitted output, revoking either audio direction fences the sink
and provider output. Revoking only agent-to-human audio does not revoke still-
permitted human input. A credited chunk denied at the output boundary is
acknowledged and discarded with terminal cleanup, not left holding provider
credit. Delayed generation completion releases the old slot with zero additional
egress, and delayed playback completion cannot publish another terminal outcome.
The direct-policy and authority-snapshot paths have generation/drain regression
coverage. Authorization and bounded retirement of not-yet-admitted/queued replies
across revoke/regrant remain separate milestone gates.

After policy checks, the consumer calls `Session.admit_output/2` with the private provider turn
reference. For an opted-in response-start descriptor, the exact start must first be
acknowledged and its context accepted; grants proceed oldest-pending first. A fresh
engine output reference authorizes `Channel.submit/3`; accepted input alone
does not authorize output. Readiness must be acknowledged and only one output turn may be
outstanding. A queued admission that expires cannot later grant permission.

Submit one PCM chunk of at most 131,072 even bytes and wait for channel credit before submitting
another. The consumer validates its envelope before sink use and returns credit only after
bounded sink acceptance. Credit is not playback. Emit `output_completed` with the turn and
output references only after the final credit. The consumer acknowledges completion, waits
for actual sink settlement and calls `Session.settle_output/3` with confirmed played
milliseconds within the credited duration. The output slot stays busy until settlement;
late audio/completion for a retired output reference is stale even if a provider reuses a turn
reference. Successful settlement notifies the provider with
`{:vxpipe_speech_output_settled, channel, turn_ref, output_ref, played_ms}`.
This proves local transport-qualified settlement, not remote hearing, and creates no TTS
input-character or usage facts. STS usage projection remains a separate milestone requirement.

Final agent text and public turn completion wait for both the selected transcript source and
the room's egress fence. Generation completion alone proves neither. Prompt interruption
fences local playback and provider output without waiting for late caller transcription.
A fence-terminal marker can release the output slot after acknowledgement/settlement but
cannot claim successful speech. Zero-egress output publishes no spoken prefix; uncertain
partial text is omitted or explicitly qualified, never treated as a fully heard reply.
Provider history reconciliation must use supported playback evidence, not generated byte count.

#### Bounded provider buffering and lossless PCM

Providers must bound private PCM buffering both before output admission and while waiting
for active-output credit. A per-chunk size bound alone is insufficient. Keep cancellation and
failure responsive while credit is withheld. Rechunking valid PCM preserves every sample,
including a final nonempty partial chunk, in order. Capacity exhaustion fails the owned
allocation safely; it must not silently truncate speech or reconnect to replay it.

The Google adapter's concrete limit is 16 pending chunks, each at most 131,072 bytes, whether
awaiting admission or buffering active output, plus the channel's single outstanding audio
credit. Opening output does not reset that allowance. Local queue, withheld-credit/cleanup and
PCM-tail regressions prove these limits and FIFO preservation, not hosted capacity. Other
providers must declare and test their own bounded strategy; 16 is not a universal queue count.

#### Private STS activation configuration

Resolve the pinned agent instruction and authorized tool descriptors before
provider startup. Retain only model-visible tool names, descriptions and input
schemas; invocation bindings, executable handlers and Call Variables values must
not enter provider configuration. Unavailable variable bindings or an absent
owning MCP runtime fail explicitly. Advertising a declaration does not authorize
execution or complete the shared tool-lifetime contract above.

Keep this configuration in the existing private-init path, not in public provider
options, descriptors or inspection. The local Google adapter accepts at most
65,536 UTF-8 instruction bytes, 64 declarations and 131,072 combined bytes as both
an external term and JSON. Existing descriptor/schema limits also apply. Reject
duplicate options/names, unsupported fields, invalid schemas and malformed names
without sanitizing authorized identities. Revalidate private config before socket
startup; config/status inspection and error logs must redact its contents.

Google setup sends the instruction in `systemInstruction.parts[].text` and exact
authorized JSON schemas in `tools[].functionDeclarations[].parametersJsonSchema`.
Activity detection belongs under `realtimeInputConfig`. Initial setup and
handle-resumed setup retain the same validated private configuration; only the
resumption handle changes. Fake-wire and startup tests cover this boundary.
This does not enable Google production selection, add an MCP owner, or establish
hosted compatibility. See [the configuration decision](google-speech-integration.md#private-sts-activation-configuration).

#### Private Google resumption

Google same-allocation renewal and idle connection-loss recovery use only the latest valid,
safe provider-issued handle, retained privately. New accepted input or revocation invalidates
the old checkpoint. Handoff waits for an idle input boundary, no pending tools and local
playback settlement, the model's `turnComplete`, and explicit interaction `IDLE`
after conversational work. Generation completion, local playback or a model end
with missing/unspecified/`IN_PROGRESS` status alone is insufficient. The local
profile also conservatively declines deprecated `REQUIRES_ACTION` as idle proof.
Accepted PCM before onset, new caller/typed input, observed model work (including
unpublished thought-only parts), and accepted tool results invalidate prior idle evidence;
a newer handle alone cannot restore it. Pristine setup with no conversational
work may still use its first safe handle. Pending caller final or activity-end
evidence also prevents renewal. Model completion invalidates any earlier handle,
so renewal also needs a subsequently valid checkpoint. The current local adapter
latches overlapping model-turn ownership as non-resumable until independent
correlation is implemented; a later unqualified end/handle cannot clear that
uncertainty. This also covers an unfinished caller preserved through model
interruption whose caller end precedes the interrupted model's completion.
It fails on connection loss or the existing expiry, with no replay
or fresh fallback. This guard does not satisfy full overlap support. Retire the old socket
through its owner and reject new input as `:busy` until replacement setup is acknowledged.

The default connection/setup attempt budget is five seconds, capped by the original local
expiry or `goAway` deadline and never restarted at an internal stage. The replacement receives
setup with the handle and then genuinely new input: no historical microphone audio,
conversation-history replay, tool replay or regeneration of earlier replies. Missing, revoked
or rejected safe handles, uncertain in-flight work, failed setup or expiry fail explicitly;
there is no fresh-session fallback. This is provider-private socket handoff, not restoration
after loss of the capability or provider process. `STSProvider` has no engine context-restore
callback. See [STS context restoration](sts-context-restoration.md) for exact deadline,
invalidation and local test evidence.

Genuinely new Gemini 3.x typed input uses `realtimeInput.text`, not history
append. This does not introduce replay or a placeholder trigger. The
[controller profile](google-sts-controller.md#interaction-and-new-text-profile)
records primary-source evidence and the separate, still-open requirement for
independently credited subsequent model responses after an in-progress turn.

#### Implementation and acceptance limits

All four caller/agent transcript-source combinations have embedded PCM room-call evidence.
Caller turns and agent output have room-owned public IDs and exact bound-source attribution
in the embedded provider-controlled path. Native input conversion/delivery and readiness
have focused evidence. Public tool identity has room-boundary and live Morse
tool-only-call evidence; qualified ordered-owner retirement and policy checks
also have focused coverage. Supervised host execution, private lease retention,
owner-loss cleanup, unknown timeouts and admission-deadline fencing now have
compiled-room and owning-worker evidence. Full private continuation and upstream
late-evidence isolation remain open.
Complete turn-controller/lifecycle coverage, full
native conversations, usage/load and final UI acceptance remain open
in the [STS milestone](milestones/agent-speech-to-speech.md); normative requirements above
do not check those tasks off. Google declares `history_reconciliation?: false`. Its manifest
entry and service badge remain disabled pending explicitly authorized hosted verification;
local fake-socket tests do not establish hosted continuity or interrupted-history semantics.
Independent review also identified directional output-revocation,
recognizer generation isolation, hosted sidecar configuration/format,
recognizer usage attribution and integrated Google response-ordering defects.
The local recognition-usage defect now has real-capability and database regression
coverage, including rejected input and failed finalization; the remaining defects
and broader acceptance retain their checklist gates. The milestone records
reproduction methods and repair tasks; successful
Morse or manually admitted provider-session fixtures do not close those gaps.

### Flow control and ownership

Keep the current ingress frame/byte/age limits, TTS pending-request limit, one in-flight output
write and the bounded sink reservoir. `Speech.Output` owns the audio acknowledgement plumbing;
provider code delivers a chunk and awaits credit before producing/reading another. Waiting
occurs in an owned producer worker or asynchronous continuation, never in the control process
that must handle cancel/close. Keep the existing 15-second output acknowledgement deadline and
5-second public call bound; explicitly bound connect/cancel/close using current host deadlines.
That public call bound limits admission/control waits, not an accepted generation's playback
duration. Successful activation settles the startup deadline; later operations and output
credit retain their separate bounds without resetting an in-flight budget at internal stages.
Use persistent local workers for repeated input/output, with separate responsive control;
avoid per-audio Tasks by default. Preserve accepted-input versus submitted-input accounting
if command completion and provider processing occur at different times.
The STT facade admits one command and 1..131,072 bytes at a time. Its age bound starts at
API entry and includes all queue waits. Binary input contains no capture timestamp: room
ingress must continue enforcing its existing frame-capture age limits. A busy provider
rejects the current chunk without replacing accepted work or automatically replaying it.
Startup deadlines must include queue wait, and one call's provider initialization must not
block admission for unrelated calls. The earlier application-global prototype failed this
requirement in an [isolated process-tree test](speech-startup-isolation.md). Checkpoint R's
scoped ownership and [deadline/fault evidence](speech-deadlines-and-failure-containment.md)
replace that rejected startup design. The completed baseline milestone records both native
directions and their room migration; STS room acceptance remains a separate checklist.

Control events use bounded admission through the same session delivery boundary, with a small
explicit queue limit and safe overflow failure. Audio credit does not block cancellation or
terminal failure delivery. Do not hide an unbounded mailbox behind a stream or return success
from `push_audio` before a bounded input slot is actually acquired. Readiness/command waits
have no synchronous cycle through the capability, producer and sink.

Session processes and their request/network workers have explicit supervision ownership and
monitor the capability/preparation owner. Owner loss, cancelled startup and rejected policy
adoption close the entire allocated subtree. Sessions are temporary; supervision does not
silently restart into the old permission interval. `terminate/2` remains best-effort cleanup.
An allocation-local failure closes that allocation; failed STT preparation preserves the
active allocation. Shared capability-control/session-supervisor failure closes the whole
capability tree, while unrelated capability trees remain usable. Allocation close and engine
capability stop are distinct operations.

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

Migrate one direction at a time. First make both built-in providers implement the semantic
contract, then switch that direction's consumers once and delete the old public behaviour and
transport configuration. Provider-specific socket/parser modules may remain private wire
helpers, with no public selection or fallback role. Update trusted host configuration and tests
in the same cutover. Stored Call Specs keep their current schema.

| Alternative | Decision and implication |
| --- | --- |
| Only write a guide or add a macro over the old behaviours | Rejected: reduces typing but leaves wire messages and transport selection in the engine. |
| Return a complete audio binary or lazy Enumerable | Rejected as the sole contract: hides streaming ownership, cancellation and backpressure; a request worker may adapt such a source internally with explicit bounds. |
| One generic speech behaviour with optional callbacks for everything | Rejected: STT ingress and TTS output have different operations and lifecycle contracts. |
| Replace STT and TTS together | Rejected: makes attribution, privacy and output regressions hard to isolate. Cut over one direction after both built-in providers implement it. |
| Introduce a speech umbrella package immediately | Deferred: current consumers and policy adapters are in Call Engine; package extraction is a separate dependency decision after the API is proven. |
| Add the compared hosted providers to prove generality | Deferred: requires new auth/model/product support. Use request-style, context-cancellation, batch-completion and segmented-transcript test profiles as bounded structural counterexamples. |
| Treat general Gemini Live as standalone STT plus TTS | Rejected: it also owns model generation, context and tools. The later [Google speech integration](google-speech-integration.md) instead uses the dedicated TTS endpoint and transcription-specific Live model as separate capabilities. |
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
planning evidence only; that initial local review was not independent-agent approval or
evidence of live-provider success or implementation. The wider provider review additionally caught segment-final/turn-end,
batch-done/request-end, packet/container and Gemini Live ownership distinctions; these are now
explicit in the descriptor, lifecycle rules and milestone conformance tasks.

Subsequent GPT-6 Astra xhigh review of the ownership replan checked fault boundaries,
admission/cancellation, deadline lifetime, private-init retention and migration order. See the
[ownership proposal](speech-session-ownership.md) and its labnote for that separate design
review. The two-of-nine R/A status recorded during that review is historical. The completed
baseline now includes both native directions and room migration, with all nine checkpoints
accepted; historical failing runs remain recorded rather than overwritten.

STS verification is tracked separately. The
[room transcript evidence](../labnotes/20260922-1420-sts-room-transcripts.md),
[agent identity evidence](../labnotes/20260922-1436-sts-public-identities.md), and
[Google output-bound evidence](../labnotes/20260922-1453-google-sts-output-bounds.md)
record focused checks and their limits. The
[contract synchronization review](../labnotes/20260922-1500-provider-contract-sync.md)
checks this document against those contracts and implementation sources. Documentation
synchronization is not acceptance of the remaining STS milestone tasks or hosted Google support.
The [tool-boundary checkpoint](../labnotes/20260922-1545-sts-tool-boundary.md)
records private/public identity, exact-source settlement and pending-map limits,
separately from the remaining execution and retirement requirements.
The [ordered tool-evidence checkpoint](../labnotes/20260922-1602-sts-tool-retirement.md)
records replay retirement, current-policy settlement, hold and capability bounds.
The [recognizer isolation checkpoint](../labnotes/20260922-1627-sts-recognizer-isolation.md)
records timeout/finalization generation retirement and bounded recovery exhaustion.
The [egress revocation checkpoint](../labnotes/20260922-1638-sts-egress-revocation.md)
records directional admitted-output fencing, denied credit and slot-reuse evidence.
