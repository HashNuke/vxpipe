# STS native source cutover design

Objective: resolve the existing B native WebRTC source-time hold/reopen gate,
not add a new media mode. This is an architecture checkpoint; no runtime code
or tests have been changed.

The current `SourceReceiver` already owns a same-peer barrier: it calls
`PeerConnection.controlling_process(peer, self())`, queues an internal commit
marker, forwards earlier RTP under the old reference, and switches epoch only
when that marker is handled before its deadline. Focused fake-peer and actual-
peer probes were recorded in the milestone. `Connection` currently binds that
receiver once at startup, but never calls its `cutover/4` method. It accepts
source RTP only from its exact receiver/current epoch; `SourceAudio.held?/1`
currently consults only the transfer handoff gate. `AudioFrame` already carries
`source_epoch`, but selected STT `Ingress` checks only receive-time cutoff,
origin generation and policy intervals, not that epoch. `STTAudioAdmission`
can bind a fresh recognizer origin independently of any upstream source hold.

The reviewed design added to `docs/sts-activity-provenance.md` uses an
internal room-authorized Connection hold/cutover/arm protocol. Room closes STT
and STS admission first. Connection holds local RTP before its receiver call
and keeps holding after old→held rotation. After the room binds the fresh STT
origin and proposed active source epoch to closed ingress, one matching arm
request rotates held→active and opens Connection admission in the same blocked
callback, then acknowledges. An ambiguous arm reply cannot reopen room ingress.
The caller budget must account for ExWebRTC's fixed five-second peer call.
Source hold is independent from
transfer hold, so STT release cannot bypass a transfer. This is local queue
fencing, not a guarantee about remote capture or ICE/DTLS backlog.

Rejected: a Connection-side peer call followed by Receiver rotation (already
reproduced as unsafe in prior Astra off-heap probes); a receiver `:ok` treated
as room ingress permission; per-frame STT origin queries; changing only the
receive-time cutoff while old raw messages can be stamped after reopen.

Next verification: a focused Gateway red for an ambiguous delayed-peer cutover
and queued old/fresh RTP. Do not mark the
room/native or telephony acceptance items complete from that Gateway slice.

Independent Astra xhigh review requested revisions. A focused Receiver probe
rotated once, suspended Receiver, queued RTP during the hold, advanced a
simulated reopen cutoff, then resumed: that packet emerged with the supposedly
fresh epoch and a post-cutoff handling timestamp. The proposal now requires a
second receiver-owned held→active barrier at arm, so held-period packets keep
the held epoch. This is a demonstrated primitive limitation and a flaw in the
first proposed protocol, not a reproduced room-cutover bug.

The reviewer also identified a synchronous RoomAuthority→Connection call-cycle
risk because Connection can call RoomAuthority. The revised protocol uses
`GenServer.send_request`-style correlated asynchronous requests from the
actual RoomAuthority PID, preserving Connection's caller check. Each phase has
an absolute deadline and terminal token/receipt checks, with budget for the
peer API's fixed five-second call. A late or ambiguous reply cannot authorize
room ingress. An ambiguous arm reply may leave Connection locally open, but
the room remains closed and must issue a fresh cancel/hold before retrying;
this uncertainty is not represented as a successful room cutover.

The latest refinement removes a release gap: a separate held→active rotation
followed by a delayed release could accumulate active-stamped RTP in
Connection's mailbox and admit it after release. Therefore the receiver barrier,
expected-epoch update and Connection source-gate opening are one arm callback;
room ingress opens only after its exact acknowledgement.

Finally, a focused in-memory Gateway probe reproduced a separate current
integration obstacle: after STS ingress retirement, a WebRTC callback with
otherwise successful STT delivery stops the Connection because the missing STS
handle is classified as fatal. This is not a full policy-driven room-call
reproduction. The existing B task now tracks the required STT-only behavior
separately; do not weaken truly required STS failure handling without a red.
No runtime code was changed in this design checkpoint.

Independent re-review cleared the first Gateway slice after the single-arm
refinement. It found one room-acceptance overclaim: after arm, Receiver can be
suspended while the peer queues RTP; if ingress reopens before Receiver handles
it, the packet receives the active epoch and a later handling timestamp. No
runtime bug was claimed from this design counterexample. The contract now
defines arm as the source-time boundary, promises dropping only for packets
actually handled while ingress is closed, and keeps delayed post-arm RTP plus
policy recheck in the integrated room test. This does not weaken the required
pre-arm old/held packet fence.
