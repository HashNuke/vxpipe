# Resource readiness evidence

Status: barrier, asynchronous collection, speech/model/tool, recording and core room-service adapters
implemented; the complete prospective inventory and lifecycle integration remain in progress.
This is a decision for
[transfer readiness and wait sounds](milestones/transfer-readiness-and-wait-sounds.md), not a
claim that calls or transfers now wait for the full barrier.

## Identity and evidence

A required resource is identified by capability kind, room/participant scope, and an optional
binding key. The binding distinguishes multiple connections belonging to the same participant,
or independently prepared routes for the same capability. Duplicate required identities are an
error; overwriting one would hide a missing resource.

When one process owns multiple resources, an adapter can implement `readiness_binding/1`. The
collector supplies the exact expected descriptor so the owner can check that binding's token and
return its current evidence. The default `readiness/1` query remains appropriate for one resource
per process. Mixer subscriptions use the binding callback: each queue has its own generation even
though several queues share a mixer PID. A query does not take or flush buffered audio.

Each descriptor pins the actual process, an explicit instance/session generation, an opaque
configuration signature, the relevant policy interval and its adapter. The configuration hash
covers effective runtime settings without putting credentials or provider connection options in
reports. A process address identifies the resource being checked; it is never evidence of readiness.

A report also carries the room incarnation, lifecycle attempt, barrier request reference and an
increasing sequence for that request. The barrier accepts only the exact required descriptor and
current request. Old requests, earlier sequence numbers, changed configuration, old generations
and foreign attempts cannot make it ready. A reported failure is terminal for that descriptor;
recovery requires replacing the failed binding/generation. A later preparing report revokes ready
status, and an older ready report cannot erase that loss.

The lifecycle owner must derive the required set from the prospective plan and effective policy.
An absent or disabled resource is omitted deliberately. A required resource with no bound process
stays preparing; one with no adapter fails. Neither counts as ready. The owner must keep this
inventory complete: an empty/incomplete input set cannot prove room readiness.

## Reconciliation and lifetime

`Readiness.Barrier.reconcile/3` returns bindings to prepare, remove and retain. Exact unchanged
bindings keep their evidence. A new attempt changes their report references while preserving
already established operational readiness. Removing and later re-adding a binding creates a new
reference even within the same attempt. This closes delayed-response races without restarting
healthy resources.

Preparing/removing a binding does not automatically mean starting/stopping its process. The
resource owner applies only the needed configuration change and acknowledges the resulting
binding. Hold/output generations are separate from resource lifetime and privacy-policy intervals.
Global policy revision numbers must not stand in for a resource's relevant interval: unrelated
membership, audio policy or hold changes must preserve that resource's descriptor and evidence.

The barrier is pure state. The supervised collector performs bounded adapter calls outside
RoomAuthority's receive loop, binds each response to its current batch/request and monitors required
processes. The barrier alone neither monitors processes nor releases media. Lifecycle use and media
release fencing are still pending.

## Prospective policy

The policy authority can now preview an exact resulting membership without applying it. It
recomposes the pinned host ceiling, normal policy and only those participants' presence restrictions,
then calculates the same scoped permission intervals used by live transitions. This lets inventory
planning exclude the departing source while it remains present and available for recovery. Remaining
participants retain unaffected intervals; an unchanged target membership retains the entire installed
snapshot. Unknown participants and malformed membership fail rather than producing a partial plan.

A candidate pins its authority instance and base snapshot. Validation checks both and recomputes the
result from pinned policies, rejecting stale or altered candidates. A live revision requires a fresh
preview even when some resource intervals remain unchanged; those resources can still retain their
readiness evidence. Preview and validation do not invoke enforcers, start/stop capabilities, alter
live permissions or grant transfer authorization. The lifecycle owner must separately fence the
attempt/deadline and validate the complete resource inventory.

Rejected alternatives are temporarily admitting the destination to discover its policy, or computing
only the destination's restrictions. The first exposes premature permissions and invokes runtime
changes; the second misses restrictions from other remaining participants and the host ceiling.
Preparing affected enforcer resources behind closed gates and installing those prepared bindings at
commit remain unfinished. A valid policy preview alone is not readiness or permission to release media.

## Prospective requirements and room bindings

`Readiness.Inventory.build/4` derives required paths from the pinned plan, the prospective policy
and authorized connections. It indexes the plan by participant ID, rather than confusing definition
keys with runtime identities. Every resulting human remains required when disconnected; every
authorized connection is selected when a participant has multiple sinks. A private destination
connection is included only for the matching attempt. Its inclusion describes future demand and
does not grant main-room access. Departing and unselected participants are excluded.

The selector distinguishes room audio input, room output and selected speech recognition. A monitor
never demands microphone processing. Policy-forbidden or unselected speech is absent. Recording
permission alone does not demand a decoder: recording must also be enabled and target that source
through a full mix or an individual track. Required remaining/incoming agents retain selected model
inference and usable TTS requirements even when their actors have not started. Model readiness
includes its existing tool/MCP dependency contract. Core mixer, transcript router and Variables
requirements are always present for a planned room; configured local recording, archive and live
inspection handoffs remain required independently of whether their processes are available.

`Readiness.RoomInventory.capture/3` obtains these requirements from RoomAuthority's pinned state
and binds the current resource owners. Its short room callback reads bindings and registry entries;
it does not query providers or dependent actors. Candidate-policy validation runs outside that
callback, within one bounded observation budget. Capture and subsequent validation reject changed
room bindings, foreign/stale policy evidence and altered or shortened inventories. The capture pins
the current transfer attempt/deadline when present, but it does not authorize a transfer or extend
its clock. Repeated captures retain exact unchanged bindings. Production room recorders now have
an incarnation-scoped registry entry; a missing enabled recorder stays explicitly required with a
nil binding. Standalone recorders remain unnamed unless their owner supplies a name.

This inventory is a requirements/binding snapshot, not a ready report. The next preparation step
must expand every selected connection through its graph adapter, prepare individual recording
writers from the resulting track identities, query all required participant/room adapters, and
revalidate the inventory before using the collector's result. Candidate enforcer preparation,
private destination prewarming and lifecycle release remain unfinished. A captured PID never
satisfies readiness by itself.

Local design review rejected deriving requirements from whichever PIDs happen to exist, accepting
a caller's shortened resource list, demanding microphone paths for monitors, and treating recording
permission as enabled recording. Checks cover five resulting listeners, multiple sinks, missing and
foreign-attempt destinations, selected/denied capabilities, recording targets, source retention
during policy preview, actual room/recorder bindings, a lost recorder, altered inventories and a busy
policy authority. These are selection and binding checks, not the milestone's five-listener playback
or transfer-release acceptance.

## Collection and deadlines

`RoomCapabilitySupervisor.start_readiness/2` owns each collector. It accepts the complete required
resource set and one absolute deadline; reconciliation never extends that deadline. Its worker
limits concurrent adapter calls, automatically revisits preparing resources and stops polling once
ready. Reconciliation retains unchanged evidence and does not invoke provider initialization.

Explicit refresh rechecks current evidence before a lifecycle transition. It closes the evidence
barrier during that check without replacing resource processes. A changed returned binding cannot
be adopted silently: the lifecycle owner must validate and reconcile it against the desired plan
and policy. Missing adapters, explicit failures and monitored process loss fail closed. A timed-out
observation remains preparing and may be retried within the same deadline; it is not proof that a
healthy provider must be restarted.

Late results from cancelled batches are ignored. Owner loss cancels the collector's outstanding
probe work, and deadline checks occur when results are accepted as well as when the timer arrives.
The owner receives only safe status/blocker summaries. Resources themselves are not stopped by
the collector. After successful lifecycle release the owner must retire the completed collector;
its deadline covers that lifecycle attempt, not the subsequent conversation.

Eleven collector tests include actual STT and mixer reports, delayed readiness, changed policy
evidence, unsupported adapters, bounded concurrency, automatic polling, loss of a ready resource,
owner cleanup, stale batches and deadline races. Inventory construction, the remaining adapters,
and startup/transfer use are still required before this becomes a complete room barrier.

## Speech-provider adapters

STT and TTS expose bounded `readiness/1` queries returning their actual descriptor and initialization
status. Speech providers declare one of two initialization contracts:

- `provider_connected`: the configured transport must deliver the provider's normalized connection
  acknowledgement. Both Deepgram speech adapters and local Morse STT use this contract.
- `initialized`: validated local/client initialization is sufficient. Local Morse TTS uses this
  contract; no fabricated handshake or synthesized probe is needed.

A missing/unsupported provider contract reports failed. STT retains its connected evidence and
session generation through unrelated policy revisions. Closing/replacing its provider session
invalidates that evidence and changes the generation; callbacks from the old transport cannot
restore it. TTS retains its initialized generation across ordinary interruption.

These queries prove the provider component's readiness. Codec/ingress binding, private output,
room routing, selected model/tools and room services are separate required resources. In
particular, a ready speech provider cannot substitute for an unprepared destination input/output
route. Startup and transfer gating will consume the combined required set.

## Model sessions, tools and MCP

Agent Runtime exposes initialization evidence independently of Call Engine: the actual session,
a generation and an opaque digest of its installed configuration/context. Ordinary conversation
updates and cancellation preserve that evidence. A busy session reports preparing because it cannot
accept its next request yet. Model providers declare a local, nonblocking `readiness/1` contract;
missing, failed or unsupported contracts fail closed. The stateless ReqLLM adapter acknowledges its
resolved configuration without generating a request. This does not promise that the next external
request will succeed.

The engine coordinator combines its admission state with the session, tool invocation registry,
request supervisor and any selected remote MCP owner. Dependency queries run outside the coordinator
receive loop. The common descriptor pins the installed dependency evidence as well as the activation;
the activation's existing one-for-all supervision invalidates that generation on dependency loss.
This composite model resource does not substitute for the separate room Variables, speech or media
bindings. Tool invocation readiness also exposes its own participant/activation resource and requires
the initialized bounded queue and owning supervisor. Saturation reports preparing without restarting
the registry; consuming completions restores readiness with the same generation.

MCP readiness follows pinned binding validation, credential lease acquisition and scoped connection
initialization. The production `Connections.open` boundary already requires the approved protocol's
ready status before returning. The owner reports only after that initialization finishes, without
invoking a dummy tool. Its resource digest covers effective private configuration and pinned tool
bindings without exposing either. Connection loss or credential revocation ends the owner and
invalidates its evidence. Call-engine callers that omit participant identity cannot obtain a scoped
resource; production activation graphs supply it explicitly.

Focused checks cover installed context privacy, busy/cancelled session reuse, unsupported providers,
delayed MCP initialization, client loss/revocation, bounded tool capacity, and collection over an
actual activation graph. Media adapters, complete prospective inventory, and lifecycle
waiting/release remain outstanding.

## Room services and local handoffs

The room mixer and transcript router report preparing until their first policy is installed.
Their ready descriptors include only the relevant audio/recording or transcript intervals.
Applying an unrelated policy revision retains the exact descriptor. Applying a relevant revision
changes its policy evidence while preserving the process generation and configured buffers.
Participant subscriptions/codecs remain additional bindings in the prospective required set.

Variables reports its initialized schema, grants and local handoff configuration after baseline
handoff. Ordinary value updates do not change its resource generation or configuration signature;
values and snapshots never appear in readiness reports.

Live inspection requires an open local observation port. Archive readiness requires an open
handoff and a bound producer. Closing either local handoff revokes readiness even while its process
still exists. A pending remote archive write does not block readiness or alter the existing bounded
asynchronous storage/gap contract.

## Recording preparation and dependency monitoring

The artifact writer acknowledges an initialized, open local handoff. Pending remote initialization,
writes or queue saturation retain the existing bounded acceptance/gap semantics; they are not new
synchronous storage dependencies. A closed or draining local handoff reports failed. Writer evidence
includes the actual process/generation, configured artifact identity and opaque configuration digest.
Malformed or unbound writer evidence fails closed instead of being omitted from monitoring.

`RoomRecording.prepare_tracks/3` takes the complete demanded individual-track set and installed
recording interval. The lifecycle owner must derive that set from the prospective media inventory;
the recorder cannot infer a negotiated track from microphone samples while input is held. The
recorder validates participant membership, configured targets and recording permission, then opens
only missing writers. Repeating preparation retains existing handles and sequences. Stale policy,
unselected tracks and disallowed recording fail preparation explicitly.

Individual-track readiness stays preparing until that set is supplied and every required writer
is initialized under the current recording interval. Relevant recording changes require a new
acknowledgement, while unrelated transcript/audio changes preserve evidence. Partial preparation
retains successfully opened writers for a bounded retry. Once preparation is used, audio cannot
create a missing writer or reintroduce a track outside the required set. Existing lazy recording
remains compatible for callers that have not entered this preparation lifecycle.

`RoomRecording.readiness_resources/1` returns the recorder plus its required writer and subscription
descriptors. The full inventory must collect all of them, because an artifact writer can fail while
the recorder process remains alive. Old track writers can continue their existing archival lifetime
without becoming requirements of the prospective room. The lifecycle owner omits recording resources
when recording is not demanded by the resulting plan/policy.

Local design review rejected consuming a frame as a queue probe, using a single mixer PID for every
subscription, preparing writers on the first released sample, and waiting for S3 as readiness.
Those alternatives respectively change playback, hide missing bindings, lose preparation guarantees,
or change the approved asynchronous storage contract. Checks cover exact subscription tokens,
unchanged intervals/generations, preparation before samples, partial failure/retry, closed local
handoffs, pending/saturated storage, and monitored writer loss with the recorder still running.
Complete startup/transfer inventory and orchestration are still pending.

## Gateway codec and room-route readiness

Room audio ingress and common phone/native audio output expose the initialization acknowledgement
of their current pipeline. The descriptor is scoped to the participant and connection, and its
generation changes when that pipeline is replaced or removed. Stale pipeline callbacks cannot
establish replacement readiness. Clearing native output preserves the codec and its descriptor;
drain/clear completion is a separate phase requirement. Room ingress also requires its installed
audio-input policy interval. Unrelated policy revisions retain its evidence.

Room audio egress requires its current pipeline acknowledgement, installed audio-output interval
and an exact ready mixer subscription under that same interval. Mixer queries run outside the
egress receive loop. Missing contracts and malformed/foreign subscription reports fail closed.
`RoomAudioEgress.readiness_resources/1` exposes the subscription separately so the collector monitors
the actual mixer even when the egress process remains available. A changed output interval can
prepare a replacement pipeline while retaining the same mixer subscription generation.

This is component evidence, not complete participant-media readiness. WebRTC connection/track
evidence, STT ingress and complete prospective inventory still need integration. No sample packet,
utterance or codec restart is used as a readiness probe.

Local design review rejected treating the pipeline acknowledgement as proof of a mixer queue or
live transport, substituting a global policy revision for relevant intervals, and making the egress
query the mixer synchronously inside its receive loop. Focused checks cover unchanged generations,
replacement callbacks, malformed subscription reports, real mixer/egress interval mismatch and
collector revocation after mixer loss. Runtime hold/release and audible acceptance remain pending.

## Shared recipient output

WebRTC native output exposes its initialized encoder, configured peer and output-track binding.
WebRTC and phone arbiters receive explicit recipient identity and native adapter configuration.
Private-output readiness queries that adapter outside the arbiter loop, validates the returned
participant/connection/process binding, and rechecks the arbiter snapshot before accepting evidence.
Unsupported adapters fail closed. Pending clear/drain reports preparing without changing resource
generation; ordinary held or private-playing output retains its initialized evidence.

The room route has a separate descriptor tied to the exact arbiter binding token. Rebinding room
output does not change the private output or native encoder descriptors. A foreign recipient
cannot acquire the route, and an old route token cannot establish readiness. The production shared
pipeline queries this revocable route; room egress includes it alongside the mixer subscription
when reporting readiness and exposing dependencies. Direct encoding pipelines retain their existing
initialization acknowledgement contract without requiring an arbiter route.

Local design review rejected reusing the first shared-pipeline acknowledgement indefinitely: its
process can remain alive after another binding replaces its route. It also rejected treating a
native PID as initialization evidence or coupling codec lifetime to hold/room-binding generations.
Focused checks cover delayed phone initialization, remote drain acknowledgements, retained codec
and RTP state, missing adapters, separate private/room bindings, native loss and stale shared routes.
Both deterministic phone adapter fixtures query their actual private/room output readiness before
exchanging audio. Negotiated live transport and required input-track evidence remain separate
requirements; these output checks do not claim complete connection or lifecycle readiness.

## Negotiated WebRTC media

Connection readiness now queries ExWebRTC's current transport state and negotiated transceivers
outside the gateway connection loop. Output evidence requires a connected peer and the configured
output track with a compatible selected Opus codec and sending direction. Input evidence separately
requires one negotiated receiving track with a supported Opus format. No RTP packet, microphone
sample or provider request establishes this evidence. Multiple active input tracks fail explicitly
because the current ingress supports one pinned track per connection.

`Connection.readiness_resources/2` includes input only when the caller requests `input?: true`.
The prospective inventory must make that choice from participant capability/policy demand, including
private destination preparation; current attachment permissions are not the prospective contract.
A receive-only connection can therefore become ready without an input track. `input_track/1`
provides the normalized track ID and format for subsequent ingress/recording preparation.

Resource signatures pin the negotiated track, codec and relevant direction. Changing only the
opposite direction preserves that resource's signature. A negotiation revision fences observations
crossing a negotiation call without becoming part of the resource's lifetime/configuration itself.
Ordinary RTP traffic and holds do not change these bindings. Collector monitoring and phase-boundary
refresh remain required for loss after an observation.

Local design review rejected deriving connectivity from the client-side connected event, accepting
an allocated transceiver without a negotiated direction, learning readiness from the first packet,
and requiring microphone negotiation for every listener. Real two-peer checks collect output/input
readiness before audio exchange, retain descriptors afterward, and cover a receive-only peer.
Codec/direction checks cover incompatible codecs, ambiguous inputs and independent directions.
Phone transport evidence, actual ingress track binding and complete lifecycle inventory remain
outstanding; negotiated input readiness does not itself prove the STT/normalizer handoffs are bound.

## Prepared input handoffs

WebRTC's decoder path now has its own `AudioPipeline.prepare_track/2` and readiness descriptor.
The previous child-playing acknowledgement describes the running graph, not initialized decoding:
the dependency's Opus parser emits its first format only after a packet, and its decoder allocates
native state after receiving a format. A preparation filter supplies the negotiated Opus format
before any packet. An ordered, correlated event then traverses the decoder, mono conversion and
frame parser; the PCM sink acknowledges only after its 48 kHz mono format is installed. This is
operational codec/path evidence without fabricated microphone samples or advancing the media clock.

Preparation retains the existing observed format for a path that already has audio, and repeated
preparation of an identical track emits no new format/event and preserves buffered partial frames.
The pipeline generation remains unchanged. Negotiated Opus channel capacity and actual packet
channels can differ; ordinary dependency handling of packet formats continues. Invalid or different
track/format requests cannot silently replace the binding. A missing or failed matching PCM
acknowledgement cannot satisfy readiness. A collector test establishes readiness before any PCM,
then combines two 10 ms packets across repeated preparation into one complete 20 ms frame.
Preparation arriving before the filter starts playing is held as one pending request; format/event
emission begins only when Membrane permits it. The element boundary regression and twenty related
WebRTC/phone/room-ingress checks pass (21 focused tests).

The common room ingress now prepares the track through the selected pipeline's registered ID and
collects its actual decoder resource outside the ingress loop. The stored lifecycle PID belongs to
the Membrane supervisor; it must not receive pipeline readiness calls. The helper rechecks the
owning ingress binding after preparation/observation and requires a matching adapter, participant
and connection descriptor. Missing adapters fail closed. Its composite descriptor includes the
actual decoder generation and its installed audio-input policy interval, and its resource list
exposes both ingress and decoder for monitoring. Graph readiness without decoder readiness remains
preparing; unrelated transcript policy changes preserve both descriptors.

Phone input uses the same PCM-sink acknowledgement. Its packet source emits the already configured
format followed by a correlated event before any media. Telnyx retains Opus/16 kHz mono input and
Twilio PCMU/8 kHz mono input; both produce the common 48 kHz mono room format. Their input track is
bound from the authenticated stream at startup. Repeated preparation validates that exact existing
binding without resetting sequence/timestamp state or re-emitting formats. Real pipeline/collector
checks cover all three transports through the common ingress and require no microphone sample.
Prospective inventory and lifecycle integration remain unfinished.

## Connection resource graphs

Call Engine now has a transport-independent preparation query for an exact attached connection.
The connection callback supplies its current binding only; a supervised bounded worker invokes the
Gateway adapter and rechecks that binding afterward. The default total query limit is five seconds;
lifecycle callers must cap it to their remaining attempt budget and run it outside RoomAuthority.
Timeout cancels the query worker. Identity mismatches, missing adapters, foreign resource scopes,
duplicate resource identities and changed connection bindings cannot produce a usable graph.

`prepare_graph` returns a `PreparedConnection` with the exact identity, connection generation,
native input-track metadata and resources from that same bounded observation. Input metadata
is nil when input was not demanded; a demanded input cannot silently omit its track. This supplies
the track identity needed for individual recording writers without a later unfenced transport lookup.
`prepare` is the resource-list projection for callers that only need collection.

WebRTC and phone sessions use the same graph adapter. Private/native output and transport evidence
are always included; room input, room output and speech input are explicit demands. A demanded input
uses the negotiated or authenticated track to prepare only its existing decoder and/or STT handoff.
The graph includes their actual dependencies, including mixer subscription and revocable output
route bindings. The adapter checks the requested scoped policy intervals before preparation and
again before returning, so an installed current-policy graph cannot stand in for an unprepared
candidate configuration. These queries do not change media gates or start new capability processes.

Receive-only attachments cannot demand microphone paths. Private transfer attachments still cannot
demand main-room input/output: attempt-bound destination preparation remains a separate unfinished
authorization step. The lifecycle owner must derive all demands from the prospective plan/policy and
collect every required connection plus participant and room resources; a graph is not that complete
inventory and cannot itself authorize release.

Deterministic WebRTC/Telnyx/Twilio checks collect complete demanded media graphs before audio and
retain them across real packet delivery. The WebRTC transfer fixture additionally verifies that its
selected STT stays preparing until the provider's explicit connection acknowledgement, then carries
audio and transcripts. That check uses the existing post-promotion attachment; it does not claim the
new coordinated transfer lifecycle is implemented. Phone graph fixtures here do not select STT, and
none of these checks substitute for rendered or live-provider acceptance.

## Phone transport

Phone sockets now expose a bounded readiness query based on their validated media-start state.
Before a valid start, their transport resource is preparing. Afterward, its descriptor pins the
socket instance, complete binding, stream and provider input format. Queries remain responsive while
the asynchronous leg dispatcher is busy: transport evidence does not wait on room setup through the
leg, which would create a dependency cycle. A process reply alias discards responses after the
bounded query ends. No playback command, media sample or provider request is sent by this query.

`MediaSession` checks that socket evidence against its exact provider, stream, socket owner and full
room/participant/connection identity outside its receive loop, then rechecks its own binding. It
exposes separate connection/input descriptors plus the actual socket dependency; input selection is
explicit, as with WebRTC. A changed or foreign stream fails readiness and cannot supply an input
track. Actual audio delivery preserves descriptors. These descriptors prove the configured transport;
the decoder, STT handoff, outputs and candidate policy remain separately required resources.
Socket callback checks cover validated starts while leg dispatch is suspended; deterministic media
session fixtures collect before audio, exchange audio, retain bindings and reject a changed stream.
Complete prospective inventory, preparation/orchestration and live phone acceptance remain unfinished.

## Speech input handoff

Engine STT ingress now supports explicit `prepare_track/2` using the normalized track ID, codec,
sample rate and channel count. It queries the actual STT owner's identity and media format outside
the ingress loop, then pins that track only if its local binding is unchanged. Invalid formats,
another connection/incarnation, and attempts to replace an already prepared track fail explicitly.
Repeated preparation of the same track does not query a busy provider, purge queues, open input or
restart anything. Existing streams can prepare their already learned track; a different track still
requires a new owning ingress.

Its composite readiness requires the provider's connection evidence, matching installed STT policy
interval, a prepared track and capacity in the bounded handoff. The inventory receives the actual
provider descriptor as a dependency as well. Queries recheck the local binding after observing the
provider. Provider configuration is represented by a digest; the input-binding query exposes only
identity and public codec/rate fields. Unrelated policy changes, opening-gate release and ordinary
delivery retain readiness generations. Prepared ingress rejects a later frame's changed format
before provider delivery, and microphone frames received while closed are discarded.

Local design review rejected first-sample readiness, assuming every STT provider accepts negotiated
Opus, and calling providers synchronously from the ingress receive loop. Ten ingress checks plus
the STT and collector checks pass (42 focused tests). This prepares the bounded STT handoff under
installed policy; it does not authorize prospective destination input or bind gateway normalizers.
Candidate-policy preparation and lifecycle integration remain separate unfinished requirements.

## Rejected alternatives and verification

Checking PIDs would release while providers are still connecting. Resetting all ready state on
every policy revision would reconnect unchanged services. Accepting reports by participant ID
alone would accept old sessions or collapse two connections. Keeping only the latest received
status without an ordered request identity would allow delayed ready reports to erase failures.

Focused tests cover a destination, a remaining caller and a room resource; exact-generation and
attempt checks; two bindings for one participant; incremental reconciliation; readiness loss;
unsupported adapters; delayed STT/TTS connection acknowledgements; stale STT callbacks; unchanged
session reuse; and initialized local TTS. Checkpoint gate results are recorded in the
[implementation labnote](../labnotes/20260914-0032-transfer-readiness-implementation.md).
