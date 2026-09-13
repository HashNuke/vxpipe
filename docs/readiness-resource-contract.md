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
