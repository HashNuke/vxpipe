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

## Transfer phase ownership

The existing destination task under `RoomTransferSupervisor` now persists after configuration.
It sends `RoomAuthority` a typed prepared notification keyed by its public task reference, then
waits under the same authority, incarnation, attempt and absolute deadline. `Phase.scope/1` reports
that identity after preparation; it supplies neither capability readiness nor connection authority.
Only the owning room authority can acknowledge completion. Requests are bounded and use reply
aliases so a late response cannot remain in the caller's mailbox.

The task monitor remains installed while a human hears briefing or waits to accept. Its original
deadline also expires independently after preparation if room authority is busy. Terminal failure
stops it through its existing supervisor; human failure uses private connection, briefing and
outbound-leg cleanup. Adopted resources retain their ordinary owners, while unadopted resources
bound to this phase observe its termination through their existing leases.

Both existing commit paths now require a final phase acknowledgement before publishing history or
tool success or starting the destination greeting. If that acknowledgement fails after policy/control
mutation, room authority exits with `shutdown`; its significant-child supervision closes the room.
Reporting success or attempting ordinary restoration from that partial state was rejected. A new
owner process or registry was unnecessary because the existing task supplies the lifetime boundary.

This connects ownership to the actual transfer path, but does not implement the full coordinator.
Private connection authorization, complete resource preparation, listener holds/waits/cues and
acknowledged media release must still use this lifetime before calling the completion boundary.

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
Affected enforcers now support preparing and adopting their selected resources behind closed gates.
The lifecycle integration remains unfinished. A valid policy preview alone is not readiness or
permission to release media.

`MediaPolicy.Authority.commit_candidate/3` installs the complete validated target membership in one
policy revision. It takes the original absolute phase deadline, revalidates the candidate inside
the authority, and sends that exact snapshot through the existing enforcer acknowledgement barrier.
The barrier gets the smaller of its configured enforcement budget and the phase's remaining time;
the authority also checks the phase deadline before publishing a successful result. Expiry before
application rejects the request without changing policy. Failure or expiry after application starts
stops the authority under its existing fail-closed contract, since some enforcers may already have
installed the snapshot. Contributions and the installed snapshot change together after acknowledgement.

This avoids an intermediate destination-admitted/source-present policy invalidating resources prepared
for the final source-departed membership. It does not bypass per-resource adoption checks or confer
transfer authorization. The lifecycle must keep media held, validate readiness and the attempt,
coordinate participant/control state, and await release before reporting success. Ordinary admission
and departure keep their existing APIs. Source retirement must be coordinated with the committed
membership rather than applying an additional source-departure policy revision afterward.

Verification covers a five-participant replacement with one exact snapshot and delayed acknowledgement,
expired/forged/foreign/stale requests, and fail-closed exhaustion of a shorter phase budget. The prepared
WebRTC recording graph also adopts through this API and remains ready before output release.

### Adopting newly prepared enforcers

`commit_candidate/4` also accepts the exact new enforcer PIDs selected by the internal lifecycle
owner. It applies the candidate once to the union of existing and new actors, waits for their
acknowledgements, and retains critical monitors for the adopted actors. Duplicate PIDs do not
receive duplicate applications. Invalid actors, invalid candidates and already expired requests
are rejected before registration or application. Once application begins, failure retains the
existing fail-closed authority behavior.

An unchanged candidate with no new actors succeeds without reapplying the installed revision.
New actor adoption requires an actual membership transition: an unchanged candidate with new
actors returns `unchanged_candidate` before application. Private transfer destinations are absent
from the base membership, so their adoption supplies that transition. Ordinary initial registration
continues to install current policy through its existing API; no synthetic policy revision or
relaxation of enforcers' stale-revision checks is introduced.

A newly staged actor must not use ordinary `register_enforcer/3` during private preparation:
that would make its cancellation a critical room failure. Its owner instead installs the base
policy locally and prepares the candidate under closed delivery gates. The owner remains
responsible for authorization, actual actor identity, phase/deadline ownership, cancellation and
complete inventory selection; this optional internal list grants none of those permissions.
No second pending-enforcer registry is needed in the policy authority. Existing live enforcers
remain registered throughout preparation and retain their ordinary failure contract.

Private STT initialization accepts an internal `initial_policy` snapshot through
`RoomCapabilitySupervisor.start_speech_to_text/8`. When that policy requires no speech session,
the capability starts without a transport. Enforcement still installs the actual current policy;
later demand starts the existing connector. Preparing the candidate uses the existing scoped
session, provider acknowledgement and ingress-track readiness. Adopting the pair through the
candidate barrier keeps that exact session, and an ingress initialized closed stays closed until
explicit release. Ordinary constructor callers retain their existing behavior.

Checks cover delayed new-enforcer acknowledgement, deduplication, rejected adoption, critical loss
after commit and failed application. The supervised private speech pair also covers discarded
preparation, pair cleanup, source resource/audio retention, retry and exact provider adoption with
input still closed. This does not yet implement the authorized private connection binding or the
persistent transfer coordinator.

### Private speech allocation lifetime

A private speech pair can receive an internal `preparation` option alongside `initial_policy`.
It pins the original phase `owner`, `attempt_id` and absolute `deadline_ms` before any provider
preparation starts. The base policy must exclude the participant. Invalid/expired scope is rejected
before a provider transport starts. Subsequent preparation must use that exact scope; a different
owner, attempt or extended deadline cannot reuse the allocation.

The temporary STT actor owns this allocation lease. On owner loss or expiry, it explicitly discards
pending provider work and stops. The ingress follows its existing capability monitor and also stops;
neither actor restarts. This covers failure between allocation and the first provider request as
well as failure during preparation. It uses existing actor supervision rather than adding a pair
supervisor, persistent lease process or central allocation registry. Ordinary live speech actors
keep their existing pending-session-only cancellation behavior.

Private admission requires a prepared replacement session matching the installed candidate. A
no-demand preparation cannot be promoted as a live speech enforcer; selection must discard it.
Successful session adoption releases the allocation lease and the existing provider-preparation
lease, retains the actual session, and leaves ingress closed until explicit release. Ending the
old phase therefore does not stop adopted speech. A refreshed candidate can retain the same private
provider generation while updating its future interval through existing policy reconciliation.

This lifetime option is an internal ownership contract, not connection authorization. The lifecycle
still needs to authenticate the private connection and provide its persistent phase owner. Checks
cover owner loss before provider startup, real deadline expiry with an unacknowledged provider,
scope changes, admission without a prepared/required session, retention after phase completion,
and unchanged provider generation across unrelated membership refresh.

### Authorized private speech binding

`RoomAuthority.prepare_transfer_speech_to_text/3` is an internal allocation operation for an
already attached private destination. It requires the actual connection process, matching actor,
tenant, room, incarnation, destination, connection and attempt, a live phase and unexpired command
and attempt deadlines. Source transfer authority is revalidated. Callers cannot choose a profile,
phase owner or actor PID: allocation uses the resolved destination and the real pending task.

The operation creates a dormant capability/ingress pair under the existing capability supervisor,
with locally applied base policy, closed input and the original private allocation lease. It does
not connect a provider or register critical enforcers. A repeated valid request returns the same
pair; an unconfigured destination returns `nil` even when application STT is enabled. The actual
connection binding makes this pair visible to authoritative readiness inventory. Provider warming
and candidate preparation remain outside room authority under the persistent phase.

The ordinary activation and startup/opening input-release paths cannot open this private binding.
Allocated private speech blocks the old immediate human commit path: allocation is not readiness,
and the complete prepared media sequence must own adoption. Capability/ingress loss or a capability
unavailable event fails only the exact private attempt and cleans all its private connections and
pending resources; the source stays available. Destination actor PIDs are created inside the authorized
operation rather than accepted through a second, caller-supplied binding handshake.

Gateway can now request this allocation through its private media operation below. The complete
coordinator must invoke that operation, adopt the selected actors through the final enforcer
barrier and explicitly release input. The ordinary committer is not a
fallback for an allocated private pair; without that integration the attempt remains pending until
failure or its original deadline. This checkpoint does not establish successful private adoption
through the sample transfer flow.

### Private Gateway media preparation

WebRTC connections and phone media sessions accept the internal
`{:vxpipe_prepare_transfer_media, attempt_id}` query. The owning connection requests authority's
configuration and private speech allocation under the exact authorization above. Authority supplies
the actual transfer owner, attempt and original deadline; the requester cannot replace that scope.
Room media preparation is tracked even when the destination has no STT profile, so absence of speech
cannot allow ordinary acceptance/briefing completion to bypass prepared adoption.

Gateway creates dormant `RoomAudioIngress` and `RoomAudioEgress` under its existing connection
supervisor. Their base policy is applied locally without critical registration, pipeline startup,
or live mixer subscription. The connection retains its native output, private admission and disabled
room modes. Only its closed speech ingress is attached, when selected. The future mix-minus
subscription descriptor is available to candidate collection without granting room output.
Repeated requests reuse actors and refresh their base policy. A missing, undemanded input decoder
stays absent when an unrelated policy revision changes its default interval.

The connection monitors its private actors. Actor loss ends that private connection and the engine's
existing failure path cancels the exact attempt; phase loss discards its private connections.
Partial construction failure also stops the private connection, letting its existing supervisor
clean all children. This reuses connection supervision rather than introducing another process or
registry. Pending provider/pipeline preparations retain their independent phase leases.

A real WebRTC check prepares and collects the entire prospective caller/human room while retaining
the source for cancellation. It waits for the actual destination provider acknowledgement, preserves
caller pipelines, and discards pending media without admission. Separate Telnyx Opus and Twilio PCMU
checks prepare their real decoder/output paths with no selected STT, using socket readiness and
simulated playback acknowledgements. These phone checks do not establish PCMU compatibility with a
configured STT profile. Actor/phase-loss checks and a policy refresh keep current room permissions
unchanged. The lifecycle does not invoke this operation automatically yet: final actor selection,
prepared adoption, attachment promotion, waits/cues and acknowledged release remain required.

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

This inventory is a requirements/binding snapshot, not a ready report. Preparation for collection
is described below. Candidate enforcer preparation, private destination prewarming and lifecycle
release remain unfinished. A captured PID never satisfies readiness by itself. Participant TTS
bindings come from the owning capability supervisor's incarnation/participant registry, including
actors outside the room's active conversation handle.

Local design review rejected deriving requirements from whichever PIDs happen to exist, accepting
a caller's shortened resource list, demanding microphone paths for monitors, and treating recording
permission as enabled recording. Checks cover five resulting listeners, multiple sinks, missing and
foreign-attempt destinations, selected/denied capabilities, recording targets, source retention
during policy preview, actual room/recorder bindings, a lost recorder, altered inventories and a busy
policy authority. These are selection and binding checks, not the milestone's five-listener playback
or transfer-release acceptance.

## Preparing the resource set for collection

`Readiness.Preparation.run/3` captures authoritative requirements, expands every selected connection
through the transport-independent graph protocol, and queries selected participant and room adapters.
It runs under the existing readiness task supervisor, with at most eight concurrent observations,
one bounded preparation budget and at most 256 distinct resulting resources. Lifecycle callers must
cap that budget to their remaining attempt time. Once captured, an existing attempt deadline also
caps preparation. Cancelled or expired observations terminate their workers without killing the
connection/capability actors. The returned descriptors still require operational collection; this
operation does not install policy, open media gates, or report transfer completion.

The supervised preparation streams link their query workers to the stream monitor. This gives
the stream ownership of cancellation as well as normal completion and timeout cleanup. The earlier
unlinked streams could leave a nested connection query running when an enclosing request died.
Direct connection cancellation, room cancellation and room-budget expiry now monitor the actual
blocked worker's termination while confirming that the connection remains usable. This changes
query lifetime only; it does not link or restart the queried media actors.

Missing connections/actors, failed required resources, inconsistent bindings, conflicting resource
identities and foreign participant scopes cannot return a partial usable set. Preparation checks
the candidate's relevant policy intervals, then revalidates the complete room inventory and policy
after dependent work. A policy change can reject either an individual observation or final
validation. Diagnostics identify capability kind/scope and a bounded reason, without provider
payloads. Unchanged instances retain their actual generations and descriptors through preparation.

Recording preparation initializes selected individual human writers from exact prepared input
tracks and agent writers from the receiving native output's mixer-issued recording tap. It collects
recorder, subscription, writer and required output-tap resources. Full-mix writers use their existing
initialized local handoff and include required agent output taps in collection. A preparing local
writer or output codec keeps collection closed; remote storage retains the existing asynchronous
contract. A required agent without a permitted, bound receiving output still fails explicitly with
`output_track_unavailable`; preparation never guesses or silently omits a track.

WebRTC and common phone output expose their current recording binding through a bounded local
query. The engine observes dependencies outside the native output's callback: it validates the
actual mixer issuer, room identity, receiving connection and PCM sample rate/channels/frame size,
then rechecks the native resource and handoff. Installed preparation also checks the current recording
interval; candidate preparation requires the exact prepared mixer policy dependency described below.
The physical tap descriptor preserves the codec's generation while its configuration signature pins
the handoff. Its policy interval is nil because the mixer owns the mutable recording gate. Different bindings invalidate
readiness; queue/cursor values and unrelated transcript policy changes do not change the binding.
No audio is offered, consumed or synthesized to establish readiness.

Design review rejected forwarding recording observations through another output control queue,
accepting an output PID without its issued tap, and deriving an agent track from an agent-owned
microphone. Connection graphs already expose native output adapters, so the engine can query that
boundary directly. Preparation covers each permitted receiving connection for each recorded agent;
identical tap descriptors shared by multiple sources are deduplicated by the existing aggregate.
Writer preparation does not fan out or duplicate audio; actual accepted egress remains the producer.

The WebRTC agent-room check opens caller and agent writers before speech and includes them in its
TTS-delayed barrier. The common phone output check prepares an agent writer before audio, remains
blocked for native codec initialization, then becomes ready with the same generation. Mixer and
collector checks reject foreign/stale bindings, fence replacement during observation, preserve
bindings across normal audio/irrelevant policy changes, and verify the first recorded frame still
uses its original timestamp. Incompatible mixer/native sample rates or frame sizes fail preparation.
Private destination prewarming and lifecycle integration remain open.

Local design review rejected returning whatever subset answered, accepting current-policy evidence
for an uninstalled candidate, learning recording tracks from the first packet, and treating an
active room handle as the inventory of all supervised TTS instances. Engine checks exercise five
participants, writer preparation before audio, delayed/failed writers, resource retention, stale
policy, foreign dependencies and cancellation. Real WebRTC checks collect both human connection
graphs plus room services before audio and retain them after audio exchange. The agent fixture also
collects model/tool and TTS resources, stays closed until the TTS provider's explicit Connected
message, then proceeds with the existing transfer. This is collection evidence; coordinated
startup/transfer waiting, candidate installation, cues and release are still unimplemented.

## Preparing an affected speech policy

Room-owned STT capabilities accept `prepare_policy/3` with an authority-produced candidate plus
the attempt ID, persistent owner PID and existing absolute monotonic deadline. Candidate validation
runs outside the capability loop; the capability also checks its room's authority and installed
base policy. One pending policy lease exists per capability. Repeated identical requests return
the same binding; another owner/attempt or a changed deadline cannot replace or extend it.

Preparation compares the participant's scoped speech permissions and demand. An unchanged session
returns its existing resource. A denied future source requires no speech resource and keeps its
current session until commit. An affected, still-demanded source initializes a separate provider
connection through the existing supervised connector while the installed session remains available.
The shared provider readiness contract applies: initialized providers need their bound transport,
and providers with an explicit connection acknowledgement remain preparing until it arrives.
Preparation sends no audio to the new connection and publishes none of its transcript signals.

Prepared resources include a lease token in their binding. The collector observes the actual pending
session, and the same descriptor remains valid when policy application adopts it. Commit rejects
failed, expired or unready preparations. A matching ready replacement is installed without starting
another connection; the old session closes through its existing transport lifecycle. Normal speech
resource queries then report the adopted generation and interval. Stale cleanup cannot close it.
Pending provider sequence positions are retained so ignored preparation events cannot be replayed
into room transcripts after adoption. Provider connection/failure usage stays in the existing
observation path, while preparation cancellation preserves the installed source session.

An unrelated installed membership/policy revision retains both the live session and its pending
replacement. The old candidate binding becomes stale until the caller supplies an authoritative
candidate based on the new room snapshot. If prospective speech permissions are unchanged, that
refresh reuses the pending connection, generation, readiness and deadline while updating its policy
interval. A relevant permission change invalidates the affected preparation. Explicit token-scoped
discard, owner loss and deadline expiry remove only the pending session; failure leaves a terminal
lease that cannot be committed until explicitly discarded and prepared again.

Local design review rejected stopping the source during preparation, starting another connection at
commit, treating pending provider events as admitted speech, and discarding a healthy replacement
solely because an unrelated room revision advanced. Room-level checks cover the actual policy
authority, registered STT/ingress, provider acknowledgements, collection and participant admission.
They also exercise foreign authority with an identical snapshot, blocked construction, exact cleanup,
failure/expiry, unchanged retention, candidate refresh and stale transcript delivery after adoption.

This is the STT enforcer's preparation path. Complete prospective graph preparation still requires
candidate input/output/recording and room-enforcer support, private destination admission, and the
startup/transfer coordinator's gates, cues and release acknowledgements. Callers must supply the
existing attempt deadline; this API does not create or extend a transfer budget.

### Input bound to the prepared speech session

`Media.Ingress.prepare_track/3` and `readiness_resources/2` accept the exact STT resource returned
by policy preparation. The capability acknowledges that descriptor's identity, generation,
configuration, audio format and applicable input policy intervals. A discarded, expired, stale or
altered descriptor cannot validate a track. Queries stay outside the ingress receive loop; the
final track bind verifies that the input resource has not changed during validation.

The input descriptor binds its existing buffer generation and negotiated track to the selected STT
session. The collector queries that same provider lease, including its connection acknowledgement.
For a replacement, it reports the prospective speech interval while accepting an input buffer still
under the installed base policy. After adoption, only the committed interval is accepted. The
prepared descriptor remains observable after commit, without replacing the input buffer or starting
another speech session. An unchanged provider produces the ordinary unchanged input descriptor.

This preparation pins the negotiated track, but does not open a microphone gate, apply policy,
consume queued audio, or forward audio to the pending session. A currently denied route can become
ready for its future policy while continuing to discard microphone input. Unrelated membership
revisions preserve the provider and buffer generations; after candidate refresh, the input binding
uses the refreshed provider interval. The provider owns cancellation and expiry, so this input
binding creates no second lease or deadline. The candidate connection query below selects this
binding; coordinated startup/transfer invocation remains pending.

### Preparing the room input decoder

Gateway's `RoomAudioIngress.prepare_policy/4` accepts an authority-produced candidate, negotiated
track, and the persistent phase owner/attempt/deadline. It validates the candidate outside the input
actor, then checks that actor's incarnation authority and installed base policy. A matching repeated
request reuses its lease; another attempt, owner or extended deadline cannot replace it.

For a still-required input, unchanged policy returns the existing decoder resources. A future denial
or absence of recipients/recording demand returns no input resources and defers stopping the installed
decoder until commit. Renewed demand prepares a missing decoder even when the permission interval is
unchanged. An affected, still-required
input starts a separate pipeline through the existing per-connection supervisor. It prepares the
negotiated track and collects the decoder's operational readiness outside the input receive loop.
The original pipeline continues to serve the installed policy, and pending PCM does not enter the
room. The input actor acknowledges the observed pipeline binding so commit can adopt that exact
ready decoder without starting a third pipeline or querying it inside the policy barrier.

Adoption preserves the normalized-frame sequence, fences transport packets received before the new
interval and ignores old-pipeline PCM. Its prepared readiness descriptor remains observable after
commit. A denied route discards subsequent input without classifying the connection as failed.
Unrelated membership revisions preserve both pipelines; refreshing the authoritative candidate
rebinds the prospective interval while retaining the decoder and input generations.

Discard, phase-owner loss, deadline expiry and pending-pipeline failure clean up only the preparation.
A failed or expired lease cannot commit. The startup-ready flag may advance during a track query;
readiness validation distinguishes that expected transition from changed identity, generation,
configuration or policy. Deterministic checks cover the real WebRTC, Telnyx Opus and Twilio PCMU
normalizers under this protocol. They do not prove live-provider calls or complete transfer release.

Design review rejected replacing during commit, accepting process startup alone as decoder readiness,
and treating a policy-denied route as transport failure. Candidate connection graphs select these
resources; complete room-service/recording preparation and startup/transfer coordination remain required.

### Preparing mixer policy and subscriptions

`RoomMixer.prepare_policy/3` accepts an authoritative candidate and the existing phase owner,
attempt and absolute deadline. Its optional `subscriptions` list contains the ordinary participant
subscription options, including exact room/recipient identity, subscriber and mode. An explicit list
reconciles the complete desired set; omission during refresh retains the previously selected set.
Removing a prospective listener cancels only its new queue, retaining other prepared handles. The mixer
acknowledges the prospective audio/recording policy and initializes only missing bounded queues.
It returns a preparation token, required descriptors and subscription handles. Existing matching
subscriptions retain their queues, tokens and configuration; a conflicting subscription is rejected.
The preparation set is bounded to 255 subscriptions plus the mixer resource.

Candidate validation runs outside the mixer loop. The mixer also checks the registered authority
for its incarnation and its exact installed base. Pending queues remain outside active fanout, and
their handles cannot take audio until matching policy installation adopts them. Preparation changes
neither current privacy nor current source delivery. Adoption uses the ordinary policy enforcement
path, retaining the mixer, current queues and initialized subscription instances. New subscriptions
exclude source frames accepted before commit, even when those frames remain buffered for existing
listeners. This fence preserves existing listeners' queued audio without replaying it to a joiner.

Prepared descriptors and handles remain queryable after adoption. An unchanged subscription keeps
its adopted handle and readiness evidence through later attempts; only an affected subscription's
policy binding changes. Unrelated membership invalidates the old candidate evidence but permits
refresh with the same owner, attempt and deadline, retaining allocated queues and generations.
Preparation cannot extend its deadline or replace a subscription ID through ordinary registration.

Discard removes only pending queues. Expiry, owner loss or required subscriber loss fail the pending
policy, notify its owner and cancel only new subscribers with exact subscription tokens. The known
failed descriptors report `failed` on collection refresh, and matching policy installation rejects
the failed preparation. The terminal preparation must be discarded before starting another attempt.
Adoption releases phase ownership; later phase shutdown cannot stop adopted subscriptions.

Design review rejected installing the candidate early, copying live queues into a replacement
mixer, and resetting all listener subscriptions. It also rejected using one room-wide preparation
token as the lifetime of every adopted handle: that invalidates unchanged routes on a later transfer.
Twenty-eight focused checks cover the real mixer and policy authority, pre-commit isolation, buffered
audio, policy denial, queue/handle retention, candidate refresh, foreign candidates, cancellation and
stale cleanup. Candidate connection graphs bind room egress to these handles. Full room recording,
transcript routing, whole-room graph selection and startup/transfer orchestration remain separate work.

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
updates and cancellation preserve that evidence. A busy session retains operational readiness;
its request admission still rejects overlapping work. Model providers declare a local, nonblocking `readiness/1` contract;
missing, failed or unsupported contracts fail closed. The stateless ReqLLM adapter acknowledges its
resolved configuration without generating a request. This does not promise that the next external
request will succeed.

The engine coordinator combines initialization evidence from the session, tool invocation registry,
request supervisor and any selected remote MCP owner. Dependency queries run outside the coordinator
receive loop. The common descriptor pins the installed dependency evidence as well as the activation;
the activation's existing one-for-all supervision invalidates that generation on dependency loss.
This composite model resource does not substitute for the separate room Variables, speech or media
bindings. Tool invocation readiness also exposes its own participant/activation resource and requires
the initialized bounded queue and owning supervisor. Saturation does not invalidate initialization
or restart the registry; submission continues to enforce the existing capacity limit.

Operational readiness excludes transient request occupancy. Waiting for an idle model or an empty
tool slot during source recovery creates a cycle: the source is waiting for the transfer result,
which may only be published after recovery releases its media. Recovery therefore checks that the
retained runtime and bindings remain initialized, then delivers the failed transfer result through
the ordinary completion path. It does not admit concurrent model requests or bypass tool capacity.
The real WebRTC recovery checks exercise destination and phase loss, retained media, the model's
failure response and a subsequent caller turn. Session and invocation checks retain rejection of
overlapping requests and excess tool submissions.

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

### Preparing a shared room route

After the output hold is acknowledged, `OutputArbiter.prepare_room/3` reserves a replacement
room binding under the existing phase owner, attempt, absolute deadline and output generation.
The live binding remains available for restoration. Preparation neither replaces the native
encoder nor interrupts private wait/cue playback. Its descriptor reports the actual native
output adapter's readiness; a running pipeline alone cannot satisfy collection.

`SharedOutputPipeline` accepts this preparation when started by the per-connection supervisor.
Its owner activates it with the exact collected resource and held generation. Activation checks
native readiness outside the arbiter loop, then commits the binding only while the lease and
base route remain current and private output has drained. Release is rejected while preparation
is pending. The adopted descriptor remains queryable, and subsequent room packets use the same
encoder, RTP sequence, timestamp clock and SSRC as the preceding private cue.

Cancellation, expiry, phase-owner loss and a newer hold generation stop only the prepared route.
After adoption, phase ownership is released and the ordinary room-output owner controls lifetime.
Repeated preparation cannot extend its deadline; stale discard/expiry/activation cannot remove a
newer binding. The previous source route remains usable after discarded preparation and an
explicit release of the current generation.

Design review rejected immediate rebinding during construction because it destroys the source
route before readiness, and rejected another native encoder because it breaks ordered cue/media
delivery. Nineteen focused arbiter checks cover preparation, exact evidence, cue ordering,
adoption, cancellation and retained output identity. Mixer subscriptions and room-egress candidate
installation still need to use this protocol; these checks do not prove transfer orchestration.

### Preparing room egress for policy adoption

`RoomAudioEgress.prepare_policy/4` takes the authoritative candidate, the exact mixer-prepared
subscription and the phase's owner, attempt, absolute deadline and held output generation. It
validates the room/participant/subscription before any gate mutation and rechecks before staging.
The mixer confirms that this queue's actual subscriber is the egress process; matching room and
participant IDs alone is insufficient. Mixer preparation can hold a pending participant queue
without adding it to active delivery; the adopted queue keeps that hold until explicit release.
A pending queue cannot be released
through the live subscription API before commit.

An existing shared egress retains its pipeline, subscription token and native output. Routing
permission changes belong to the mixer; they do not require a new forwarding pipeline. A joining
connection with no room route starts its shared pipeline against a pending native binding. Its
prepared readiness includes the exact prospective subscription and native route. Resource evidence
remains queryable after adoption, and unchanged preparations preserve all existing descriptors.

The policy callback adopts only collected ready resources under the original valid lease and a
held, drained output. Retained routes revalidate their native binding, and new routes activate their
reserved binding. No codec or provider starts during commit. Mixer-dependent observation happens
outside the callback; ordinary mixer delivery is scheduled after the callback returns. Existing
readiness waiters are answered only after successful adoption, while media remains held.

An unrelated membership update keeps a dormant joining egress dormant. Its candidate can be
refreshed under the same lease without replacing the pending pipeline or subscription. Expiry,
owner loss or pending-pipeline/subscription failure invalidate prepared evidence and notify the
phase owner; cleanup affects only the pending route. Explicit discard acknowledges native
reservation cleanup. A stale discard cannot remove a later preparation or an adopted route.

Design review rejected replacing a shared forwarding pipeline merely for a different permission
interval, premature live activation of a joining route, and holding a supplied subscription before
validating its owner/identity. Nine focused real-authority/mixer/native-output checks exercise
adoption, retained identities, private isolation, cancellation, owner loss, foreign-room rejection,
revoked native bindings, actual queue ownership and membership refresh. Complete connection-graph
selection and transfer orchestration still need to use this protocol; this is not complete
lifecycle acceptance.

### Holding an existing room output

`RoomAudioEgress.hold/2` closes the exact mixer subscription and then holds/clears its shared
native output under one generation. Dependency calls run outside the egress callback so native
completion and policy acknowledgements remain serviceable. The operation rechecks its pipeline,
subscription, relevant interval and exact arbiter route before acknowledging success.

The mixer gate is participant-subscription-local. It clears that queue, skips held delivery and
captures source sequence cutoffs at release, excluding audio buffered before release. Newly mixed
frames carry the released output generation. Duplicate holds/releases preserve the gate's state;
an old generation cannot reopen it. Gates do not change privacy policy, subscription tokens,
readiness generations, recording subscriptions or another listener's queue.

Clearing a playing shared room frame emits a distinct discard acknowledgement after native clear
completes. The shared producer uses it to release its in-flight frame; this does not report played
audio or satisfy private cue completion. `RoomAudioEgress.release/2` requires native release first,
which rejects undrained private playback, then opens the mixer subscription and revalidates the
binding. Failure after native release reports an uncertain release and ends the connection's room
output boundary through its existing owner notification. The lifecycle coordinator must still own
the attempt deadline, cancellation and release across all connections, microphone and model gates.

Design review rejected restarting codecs/subscriptions for a hold, changing privacy policy just to
wait, and resetting every frame to a new generation at the output sink (which would admit stale
frames). Focused checks cover independent mixer queues, discarded buffered speech, retained
readiness, native discard completion, real mixer/egress/private-output ordering on one RTP timeline,
and terminal release failure. These checks enable room output gating; they do not establish the
complete startup/transfer sequence or browser/provider acceptance.

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

### Selecting prepared candidate connections

`Media.ConnectionReadiness.prepare_candidate/5` takes the connection, exact identity, authoritative
candidate, demanded paths and preparation options. Options retain the phase's persistent `owner`,
`attempt_id`, absolute `deadline_ms` and held output `generation`. The phase also supplies the exact
mixer-prepared `subscription` for room output and selected prepared `speech_to_text` resource for
speech input. Those dependencies retain their owning mixer's/provider's lease; the query worker
does not become their owner or extend their deadline.

The bounded external worker validates the candidate against the incarnation's real authority,
captures the connection binding, then invokes the candidate callback. Gateway confirms output is
held, prepares the demanded decoder, selects the exact speech/input binding, and prepares the
room egress against that mixer handle. It checks every resulting scoped interval. Call Engine
revalidates connection identity/generation and the authoritative candidate before returning the
graph. A legacy adapter without the candidate callback reports unsupported; installed-policy
collection cannot silently substitute for prepared resources.

If the prospective policy removes an existing input's demand, collection records its deferred
shutdown without requiring an input track or decoder readiness. The live decoder stays installed
until commit, then stops without creating a replacement. Its removal is absent from the required
resource set but remains in the graph's cancellation handles until adoption.

The returned `PreparedConnection` includes exact input/output preparation handles.
`discard_candidate/1` cancels those preparations in reverse order, retaining live resources and
ignoring already-adopted/stale handles. Failure during collection discards completed input/output
preparations. The phase still owns cancellation of its separately prepared mixer and STT leases.
Discard does not release media gates. Ordinary installed-policy graphs have no preparation handles.

Private attachment matching remains narrow: its attempt must match the phase, and its participant
must still be absent from installed membership. Human handoff establishes dormant media and demanded
STT bindings through the owning connection before collecting the prospective room resources.
Repeated private preparation retains the same owner, attempt and deadline, but reevaluates speech
demand. If demand disappears before acceptance, the engine removes the private speech capability
and ingress; Gateway removes their monitors and updates attachments on its retained media actors.
An unchanged speech binding retains its instances and monitors. The returned receipt describes
the current enforcers and must be collected again after such a change. Current privacy stays
installed throughout collection, and readiness by itself cannot authorize microphone/model
admission or release.

While human handoff readiness is pending, the worker validates its captured candidate on readiness
notifications and at bounded 100 ms intervals. A stale policy causes the worker to recheck private
media and prepare the current candidate under the same owner, attempt, generation and deadline. Existing
preparation APIs retain unchanged resources; `Collector.reconcile/3` retains their readiness and
replaces only changed descriptors. Existing wait players continue; newly included, already connected
listeners receive their own hold and wait. The handoff uses the refreshed receipts and complete
resource set for its eventual commit. Queued notifications are treated as signals to read the
collector's current state, because they may describe a resource set that reconciliation removed.

Ordinary WebRTC handoffs verify removal of undemanded private STT while collection is pending and
retention of the original STT transport across an unrelated membership revision. Both retain the
existing connections and media actors and exchange caller/support audio after release. Policy
changes during initial graph construction or adoption, changed still-required resources and
complete changing-listener lifecycle behavior remain separate acceptance work.

If the candidate becomes stale during a human connection cue, only the private cue is allowed to
finish draining. Conversation remains held. The worker then resumes waits, prepares the current
requirements under the original lease/deadline, and plays new cues before revalidating release.
Final readiness queries also check candidate validity while awaiting resource replies. Every
playback episode has a fresh correlation identifier even though the media generation stays stable;
a previous cue's acknowledgement cannot identify its replay. Actual player failure still uses the
existing bounded recovery path. Controlled engine checks cover removed STT demand with default
waits and unaffected STT across a membership revision with silent waits, requiring the second cue's
drain before success and proving the attempt deadline is unchanged.

Design review rejected rebuilding a retained native output, using current STT evidence for a
replacement session, and assigning preparation ownership to a short-lived collection worker.
Actual WebRTC checks prepare/discard/retry/adopt a changed decoder, retain native output, verify
the same collected descriptors after the policy barrier, and deliver audio to the new participant.
The speech fixture collects the replacement session while preserving the live session, stays
preparing until its explicit Connected acknowledgement, then cancels only pending work and resumes
the original conversation. Existing WebRTC and both phone graph fixtures continue to pass. These
are connection-boundary checks, not complete startup/transfer or live-provider acceptance.

## Preparing the prospective room

`Readiness.Preparation.run_candidate/3` composes the authoritative inventory with candidate
connection preparation under one persistent owner, attempt, media generation and absolute deadline.
It captures each connection's actual output consumer and requests the complete desired mixer
subscription set once. It then prepares transcript routing and selected speech sessions, supplies
their exact prepared bindings to every required connection, and observes the remaining room and
participant resources. Existing affected input with no future demand still receives deferred
shutdown preparation. Required disconnected humans or missing actors fail the operation.

The result contains the complete collected descriptors and flat preparation handles. Explicit
discard and failures after partial preparation unwind known handles in reverse order. This cancels
pending work while retaining live resources and leaving media gates held. Persistent phase ownership
and the original deadline bound preparation if an enclosing query is cancelled before it can return
handles. The lifecycle owner must end that phase on cancellation. Final inventory/policy validation
still occurs outside authority and media actor callbacks; no candidate permissions are installed by
the runner. Repeated preparation under the same lease retains resources.

Transcript routing has no provider to reconnect. Its pending policy binds the authoritative base
and desired snapshot without changing live projection decisions. Commit adopts the prepared
descriptor while preserving the router process, generation and configuration. Owner loss or expiry
invalidates pending evidence and prevents that candidate's adoption; explicit discard allows a new
lease. An unrelated revision requires a refreshed candidate under the same original deadline.

Candidate recording now stages future writer ownership and selected tracks separately from live
recording, as described below. The installed-policy query still rejects changed recording sources
instead of mutating live requirements prematurely. Native agent taps are selected with the same
prepared mixer policy evidence, including changed recording intervals. Private destination actors
and lifecycle orchestration remain unfinished. Do not treat
this runner as complete transfer readiness.

Design review rejected deriving subscriptions from a partial caller list, replacing transcript
routing on policy changes, extending a lease on refresh, or presenting current recording descriptors
as evidence for a different prospective recording configuration. Actual WebRTC checks cover a
three-to-two participant transition, cancellation/retry, closed transcript routes until commit,
unchanged native output and audio after release. The human-transfer fixture additionally collects
both connected humans, existing STT and recording writers, cancels preparation and continues the
original audio/transcript conversation. It also prepares and discards a future recording source set,
preserves current writers and retries successfully. Router checks cover discard, refresh, expiry and
owner loss.
These checks do not establish the milestone's wait/cue, recovery or browser/provider acceptance.

## Prepared recording ownership and policy

The candidate runner now prepares required recording tracks against the authoritative future
membership and recording permission. The recorder keeps its live stream selection until policy
adoption. Existing writers retain their handles; missing writers open through independently
supervised `Recording.PreparedWriter` sources. Each source monitors both the recorder and the
phase, and uses the original absolute deadline. Writer configuration is passed through separately
from these lifecycle options. No new writer callback or dependency is required.

Discard ends only new sources; existing artifact writers already drain when their source exits.
Adoption removes each new source's phase monitor and timer while retaining its recorder monitor.
The actual writer process, handoff and readiness descriptor remain unchanged. Remote storage stays
asynchronous: cancellation initiates the existing bounded drain and does not wait for remote
completion. Source ownership is the cleanup boundary, not a claim that remote storage has finished.

The mixer prepares evidence for its existing recording subscriptions under the same candidate
lease. Changed recording intervals receive exact prepared bindings which survive policy adoption;
unchanged queues retain their descriptor. The recorder joins the policy barrier on its first
candidate preparation, after identity/candidate validation and outside its callback loop. Ordinary
recorder startup continues to use its existing mixer policy path. Once registered, recorder loss is
an enforcer loss under the existing authority contract.

Readiness observes the prepared subscriptions and local writers outside the recorder callback, then
confirms the exact unchanged selection. Adoption requires that confirmation, an unexpired lease and
the matching authoritative base. The recorder monitors required writer instances after confirmation;
writer loss invalidates the pending policy even if no new readiness query has run. It performs local
source adoption and installs the prepared track
selection. Retained output sequence numbers come from the live streams at commit, so audio recorded
during preparation cannot be replayed or restart a stream's numbering. No writer opens during commit.

Unrelated policy refresh retains pending writers and the original deadline. A full-mix recorder
with unchanged dependencies retains its exact descriptor, including when its track-preparation
metadata is first initialized. An adopted descriptor can confirm readiness for a later unchanged
preparation. Failure, discard and owner loss close pending sources; mixer loss still terminates
the recorder during preparation. Known final-validation failures unwind recording handles along
with the rest of the room's preparations.

Design review rejected mutating live required tracks to discover readiness, copying stale sequence
counters from the start of preparation, replacing existing writers, and adding provider-specific
cancellation callbacks where source ownership already supplies cleanup. Engine checks cover private
future writer creation, recording during preparation, adoption, delayed local readiness,
discard/retry, phase loss, mixer/writer loss, full-mix retention and policy refresh. The WebRTC room check
prepares changed human recording membership while preserving current writer resources, discards it
and continues the original conversation.

### Native recording taps under a candidate policy

An existing native tap can be physically initialized while its mixer recording gate is closed.
`Recording.EgressReadiness.prepare_candidate/5` validates the authoritative candidate and pairs that
exact tap with the prepared mixer resource already owned by the room phase. It verifies the actual
mixer instance, identity, connection, format and bounded capacity, rechecks the native binding,
and observes the exact mixer descriptor before and after the tap query. The candidate must permit
recording and its scoped intervals must match the mixer's acknowledged preparation. Relabeled
installed evidence, stale candidates, discarded preparations and foreign mixers cannot establish
this dependency.

The physical tap descriptor has no policy interval: changing permission updates the mixer's existing
gate without allocating a tap or restarting its codec. Candidate recording selection returns both
the tap and mixer resources for collection; a ready tap alone cannot open recording. The whole-room
aggregate deduplicates the shared mixer dependency. Installed-policy preparation retains its current
permission/interval checks. Prepared recording writers, subscriptions and policy adoption retain
their separate ownership contracts above.

Design review rejected a second registry of tap preparation leases because the mixer already owns
the gate and original phase lease. Copying a future interval onto a current tap descriptor would
claim permission readiness without observing its owner. A physical descriptor plus the exact prepared
mixer dependency preserves allocation and enforces the actual permission boundary.

Engine checks cover preparation while recording is denied, unchanged tap/codec identity after
adoption, ignored audio before commit, accepted audio after commit, selected agent writer cleanup,
discarded policy evidence and rejection of installed/relabeled/stale evidence. A real WebRTC room
prepares both caller and agent recording paths under a changed recording interval, discards and
retries, collects the complete resource set, adopts those exact resources and releases output.
The existing human transfer still exercises bidirectional audio and destination transcripts. These
checks establish candidate recording preparation, not the unfinished transfer/wait lifecycle.

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
