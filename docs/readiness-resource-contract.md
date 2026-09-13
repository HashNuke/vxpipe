# Resource readiness evidence

Status: barrier, asynchronous collection, speech/model/tool adapters and core room-service adapters
implemented; the complete prospective inventory and lifecycle integration remain in progress.
This is a decision for
[transfer readiness and wait sounds](milestones/transfer-readiness-and-wait-sounds.md), not a
claim that calls or transfers now wait for the full barrier.

## Identity and evidence

A required resource is identified by capability kind, room/participant scope, and an optional
binding key. The binding distinguishes multiple connections belonging to the same participant,
or independently prepared routes for the same capability. Duplicate required identities are an
error; overwriting one would hide a missing resource.

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
actual activation graph. Recording/media adapters, complete prospective inventory, and lifecycle
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
asynchronous storage/gap contract. Recording writer adapters remain pending.

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
