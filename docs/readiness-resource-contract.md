# Resource readiness evidence

Status: barrier, speech-provider adapters and core room-service adapters implemented; lifecycle
collection and the complete prospective resource inventory remain in progress. This is a decision for
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

The barrier is pure state. Bounded adapter calls, process monitors and preparation belong in a
collector outside RoomAuthority's receive loop. The collector must bind each actual response to
its request, preserve report ordering and revoke evidence on resource loss; it cannot fabricate
readiness from a successful child start. The barrier alone neither monitors processes nor releases
media. Collection and release fencing are still pending.

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
room routing, selected model/tools and room services remain separate required resources. In
particular, a ready speech provider cannot substitute for an unprepared destination input/output
route. Startup and transfer gating will consume the combined required set.

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
