# STT-owned activity provenance for room STS

Status: reviewed design candidate, not implemented room control. Selected-STT
demand, audio-route provider reset, and ingress policy-interval plus native
allocation-generation checks are committed enabling slices. Source-time input
cutover, hold/release and room acceptance remain open. Scoped capability-emission
signal metadata and recording-only retirement checks pass, but they are not a
room controller binding.

## Decision

Use one immutable activity binding per native STT allocation that is authorized
to control the selected room STS allocation. It records the exact STT source
connection/capability, selected STS capability and activation, STS input epoch,
and the source's audio-input and audio-output policy intervals. Native STT
`Event` already carries an allocation generation, producer sequence and native
turn reference; preserve those values, with the binding, in private STT signals
at producer emission. Never fill missing provenance from current room state
when the signal is handled. The room accepts a start/end only when the exact
binding is current, both routes and participants remain authorized, and the
end matches the active native turn reference. Unrelated global revisions do
not rotate the binding. The existing STS input queue receives captured epoch
and intervals only after this room check; queue admission is not proof of
completed provider delivery.

The current-origin side of this comparison belongs to the STT capability:
extend its bounded engine input-binding query with the selected native
allocation generation and scoped source-audio intervals. The room compares
that result with the signal's frozen generation/intervals before binding the
STS input epoch. The query must not mint an origin or infer one from a late
signal, and a non-selected or unready recognizer supplies no activity origin.
The current-origin query must also return no origin for a canceled native
allocation, even before the capability consumes its closure notification.
A ready prepared-policy replacement is a candidate, not the live origin:
its resource-scoped query returns no origin until adoption, after which the
adopted session may expose the same generation as the current binding.
This is a room-validation seam, not the separate ingress PCM cutover proof.

The STT ingress needs an acknowledged cutover, not merely queue clearing. It
must close admission, purge queued PCM and qualify each asynchronous delivery
with the allocation/input generation that admitted it. STT must reject an old
envelope before sending its audio to a new provider allocation; stale replies
must not unlock a new delivery credit. The cutover also needs a trustworthy
upstream received-before-open fence for pushes handled after reopening. The
existing `AudioFrame.received_at` is a possible seam only if every source
preserves its original timestamp; a source-issued generation is stronger. Both
policy-enforcer application orders need focused proof.

The reviewed admission shape is explicit and room-owned: close ingress,
acknowledge native STT retirement, wait for a fresh ready allocation, then
install its exact origin at ingress open. Ingress freezes that admission when
each frame is enqueued; capability compares the frozen native generation and
scoped policy intervals before provider delivery. The hot path does not query
STT for each frame. A separate source-side fence rejects an old frame received
before reopen but first pushed afterward. Read-only review reproduced why a
query at push is insufficient: the same delayed old frame was rejected with
its pre-replacement origin, then accepted when a post-replacement query labeled
it with the fresh generation and intervals. This is design evidence, not
implemented cutover acceptance.

An enabling interval-proof slice captures the ingress snapshot's STT,
audio-input and audio-output intervals in each asynchronous PCM envelope and
rejects a mismatch at capability delivery. A later selected-STT slice binds
the ready native audio origin to ingress, freezes its generation at enqueue,
and rejects missing or stale generations at capability delivery. Ingress
readiness also compares the bound generation with the provider's current one;
transcription audio origin remains distinct from STS activity authority. These
checks now include an ingress-only close/reopen and receive-time cutoff: a
selected frame stamped at or before fresh origin binding or explicit reopen is
rejected before queueing. WebRTC now stamps peer notifications in a dedicated
initial receiver before forwarding them to Connection; the legacy direct
callback path retains its handler-time fallback. Telephony stamps decoded media in
the WebSock callback before Leg dispatch, but raw messages queued before
that callback remain unclassified until a source hold/fence is acknowledged;
legacy unstamped media still gets a MediaSession handler-time fallback. Astra
xhigh reproduced pre-reopen raw messages first handled afterward receiving
a fresh timestamp and bypassing the cutoff before the telephony enabler.
The cutoff conservatively rejects equal-millisecond frames. Room-owned
ordering of close, native retirement, fresh readiness and release also
remains unproven. This is not the completed cutover contract above.

The reviewed next boundary is an acknowledged **source-admission epoch**,
separate from the STT native allocation generation and transfer generation.
An upstream owner fixes that epoch before handing media to an asynchronous
consumer; a downstream handler must never read a mutable current epoch and
apply it to older queued bytes. During cutover, close ingress and revoke the
old source epoch, hold/fence the source with an acknowledgement, retire the
old recognizer, bind the fresh ready STT origin while closed, arm a fresh
source epoch with an acknowledgement, then reopen ingress. Timeout, owner
death, stale acknowledgement or another active hold leaves input closed.
Selected-STT reopening cannot clear a transfer's independent hold.

For WebRTC, the ExWebRTC peer's controlling-process notifications are the
earliest project-usable handoff. A per-epoch receiver is one possible way to
keep already-emitted notifications on their old epoch; merely relaying them
through a process that reads a mutable epoch would preserve the bug. A peer
ordering barrier or owner switch needs proof that old notifications cannot
overtake its acknowledgement and that non-media peer notifications retain
their required ordering. For telephony, the WebSock callback must assign the
epoch before asynchronous SocketDispatch, then carry it unchanged through
Leg to MediaSession. While held, stale media may be dropped with successful
dispatch acknowledgement, but marks, readiness and lifecycle messages must
continue. An acknowledgement at the socket alone does not drain already
queued Leg events. Synchronous nested calls can form a Leg/MediaSession cycle;
the implementation must prove its ordering without such a cycle.

An initial WebRTC `SourceReceiver` now owns peer notifications from startup.
It stamps RTP with its current source epoch and monotonic receiver-handling
time before forwarding. The Connection admits only RTP from its exact current
receiver/epoch and carries that evidence through STS conversion. Non-media
notifications retain their
original shape. A focused suspended-old-receiver test proves its queued RTP
cannot be relabeled by starting a successor; a connection test proves stale
envelopes are dropped. The receiver-owned same-peer barrier described below
now has focused protocol proof, but no room-coordinated hold/reopen acceptance.

A same-receiver design avoids changing ExWebRTC's controlling process and
accumulating old receivers, but a **Connection-side** peer call followed by a
receiver rotate is unsafe. The peer sends RTP to Receiver and its call reply
to Connection. OTP does not guarantee transitive delivery order across those
two destinations and the subsequent Connection-to-Receiver request. Astra
xhigh reproduced an old peer-emitted RTP notification stamped with the fresh
epoch under off-heap signal buffering and contention, even though the peer
call completed before Connection requested rotation. An ordinary notification
already in Receiver's mailbox stays ahead of the call; the bypass concerns
signals not yet delivered into that mailbox. This is still inside the local
peer/receiver boundary, not ICE/DTLS backlog.

The implemented receiver-local protocol is receiver-owned: while downstream
admission is closed, Receiver itself calls the peer's controlling-process API
with the **same** receiver. After the peer reply, Receiver queues a private
normal commit marker, returns to its mailbox loop, processes preceding RTP
with the old epoch, then commits the new epoch at that marker and acknowledges
Connection. It must not mutate the epoch immediately in the nested call's
selective receive. The old public `rotate/4` bypass was removed; cutover
requires an exact old epoch, a peer binding, an operation token and an
absolute deadline. A queued request or late peer acknowledgement cannot
mutate the receiver after the caller deadline. Focused fake-peer tests cover
old/fresh RTP, non-media, stale calls, error and expiry; independent actual-
peer off-heap challenges preserved ordering in 100/100 trials. ExWebRTC's
peer call can still hold Receiver for five seconds after a shorter caller
timeout. The caller must keep downstream admission closed on an ambiguous
reply, and room/source coordination remains unimplemented. This local
protocol alone does not authorize rotating a live source during a call.

## WebRTC caller-side cutover contract (design, not implemented)

The missing live caller is the room, through one private source-control
boundary on the exact attached Gateway Connection. Extend the internal
`ConnectionAttachment` with the owning RoomAuthority PID; this is not a public
call-spec or client handle. Connection accepts a cutover command only from that
PID for its current main attachment, with a fresh room-issued operation token.
An old or overlapping token cannot arm a later interval. The Gateway owns its
current `source_receiver` and epoch; the room must not rotate them directly.

For selected external/hybrid STT, rotate this boundary whenever the selected
native allocation changes, including transcript-only replacement or a
hold/release interval—not just on audio-route changes. The room first closes
its STT and STS ingress admissions and retires the old controller association.
Because policy enforcers can run in either order, selected STT ingress must
also close locally when its current allocation/policy origin is invalidated,
before acknowledging that transition; a later connected signal may bind the
candidate origin but cannot reopen admission on its own. Room close is the
coordinating acknowledgement, not the only safety fence.
RoomAuthority must send correlated, asynchronous GenServer requests **from its
own PID** and handle their replies in a later message. That preserves the
Connection caller check without blocking the room in a possible synchronous
Connection→RoomAuthority call cycle. The hold request carries an absolute
deadline, exact attachment and fresh room token; its receipt records the
receiver plus old and held epochs. Arm requests must match that receipt and
carry their own bounded absolute deadlines. Connection checks expiry both when
a queued request starts and before any state transition;
expired tokens are terminal. The receiver's fixed five-second peer call needs
a compatible outer budget for peer wait, mailbox marker and reply, with a
separate bounded room response budget. A missing room reply closes room ingress;
a late success cannot authorize it.

Connection uses **two** receiver-owned barriers. On hold, its source gate closes
before rotating the old epoch to a private held epoch. Old RTP queued before
that marker keeps the old stamp; RTP accumulating during the hold has the held
stamp. After native STT retirement and fresh readiness, the room chooses an
active epoch. Connection rotates held→active under a second receiver-owned peer
barrier when it handles the room's arm request. RTP queued during the hold must
leave with the held stamp, even if Receiver first handles it
after the arm request; it cannot acquire the active epoch. A single rotation
at hold followed by opening that same epoch is rejected: a focused reviewer
probe suspended Receiver, queued RTP during hold and observed it emerge with
the fresh epoch and a post-cutoff timestamp after resume.

After native STT retirement and fresh readiness, the room binds the exact new
allocation origin **and** the proposed active source epoch to the closed STT
ingress. Ingress must compare that epoch on every selected `AudioFrame`, in addition to
its current generation, policy intervals and receive-time cutoff. The room
then sends one exact arm request. Connection checks expiry, attachment,
receiver, held/active epochs and independent transfer hold; within that same
blocked Connection callback it performs the second receiver barrier, updates
its expected epoch and opens its source gate, then acknowledges. There is no
gap in which Receiver stamps active-epoch RTP while Connection remains held
awaiting a separate release. The room reopens each input lane still authorized
by current policy only after the arm receipt. If that reply is late or
ambiguous, room ingress stays closed even if Connection opened; a subsequent
cancel re-holds it. A dead RoomAuthority ends its monitored Connection, not
an unowned media stream.
If transcription demand survives an STS route denial, STT input may reopen
while STS activity/input stays closed. RTP handled by ingress while it remains
closed is dropped. RTP delivered by the peer after the arm barrier but queued
in Receiver until ingress reopens may carry the active epoch and be admitted:
arm, not room-ingress reopen, is the source-time boundary. The room must
recheck current authorization before reopening ingress; a revoked interval
stays closed. `SourceAudio` must check both this source gate and the independent
transfer hold; STT release cannot clear a transfer hold.
Any uncertainty at any step leaves effective room admission closed and the
selected STS allocation unavailable. This protocol fences project-observable
queues, not remote microphone capture or ICE/DTLS buffering.

The first implementation slice is the Gateway-side caller boundary and its
controlled delayed-peer, old/held/active RTP, timeout and transfer-overlap tests.
Room-driven close/retire/bind/arm/open and telephony callback/Leg cutover are
separate dependencies of the same existing milestone gate; the Gateway slice
alone cannot be reported as successful hold/reopen.
The integrated proof must run both policy-enforcer orders, a transcript-only
native replacement with unchanged audio intervals, same-peer queued RTP across
hold and reopen, a packet queued after arm but before ingress reopen, a
genuinely fresh packet, unrelated policy rebase, missing or late
acknowledgements, owner death, and transcription-only operation while STS
audio is denied. Use observable acknowledgements, not sleeps or an unqualified
fixed delay. Keep effective room admission closed after any uncertain result.

The first telephony enabler now stamps decoded media with a monotonic time
and private socket-lifetime epoch before SocketDispatch; Leg preserves the
packet and MediaSession carries that evidence into the input `AudioFrame`.
The Twilio test stalls Leg; both provider tests verify retained metadata,
and a MediaSession test verifies it does not restamp a delayed packet. This
does **not** rotate or revoke the socket epoch, reject stale epochs, drain a
raw WebSock mailbox, or coordinate STT hold/reopen; those remain the actual
source-cutover gate.

This is a reviewed design candidate, not implemented acceptance. It fences
project-observable queues at the stated admission boundary; it does not prove
when a remote microphone captured audio, when a packet entered ICE/DTLS, or
when TCP bytes arrived before a WebSock callback. Those upstream limits must
be stated in tests and in the final acceptance claim.

The producer-side slice preserves the native STT event's allocation
generation and turn reference plus the source's audio-input/output intervals
in each private signal at capability emission. This is immutable evidence for
later room comparison; it does not itself authorize external activity or bind
the selected STS epoch. The room must not infer a missing epoch from its state
when a delayed signal arrives.

Capability-emission stamping is not evidence of audio origin if a native event
waits across a policy change while its provider allocation remains alive. A
focused queued-native-end reproduction found exactly that on a recording-only
change: the old end acquired the new audio-input interval. Selected activity
STT now retires its provider on any scoped source audio-input/output interval
change, including recording-only changes, so a queued event from that old
allocation is rejected. This relies on successful session retirement and does
not solve hold/reopen, pre-cutoff PCM or native evidence first produced by a
provider that is allowed to survive another lifecycle boundary.

Hold, route loss, source replacement and transfer retire the room controller
association before a new interval opens. Under the current STT provider
contract, an allocation that consumed old or held audio must be retired and a
fresh allocation made ready before activity control is reopened. The provider
exposes no acknowledged discard/reset or frame-to-event origin correlation;
simply changing a room epoch or stamping a provider event at receipt cannot
classify evidence first surfaced after reopening. Transcript demand may keep
recognition available during denial, but that allocation cannot inherit fresh
activity authority; it must be replaced again before control resumes. A
failure to retire, start or reach readiness leaves control closed.

External mode sends the validated STT start and matching end through STS ingress.
Hybrid uses the STT pair for attribution but sends only its matching end;
provider-controlled mode sends neither. Loss of activity demand mid-turn
retires the pair without manufacturing a normal end. STS provider-side
external activity retirement is a separate requirement: hold must not synthesize
an end that prompts an old reply.

## Rejected alternatives

- Stamp the room's current STS epoch onto a delayed STT signal. This relabels
  already-emitted old evidence after hold/release.
- Stamp only the current STT transcript interval. Audio-only route changes can
  leave that interval unchanged.
- Query STT origin on each frame push as a substitute for source admission.
  It can stamp previously received audio with a fresh allocation generation,
  and the current five-second query would block a media caller on the hot path.
- Stamp raw media only when the Gateway callback eventually handles it, or
  pass it through a relay that consults a mutable current epoch. Both relabel
  already-queued old bytes after reopening.
- Treat a socket-only acknowledgement as a telephony drain. An older dispatch
  may still be waiting in Leg's asynchronous mailbox.
- Rotate a generation while keeping the same provider session. A provider
  event first surfaced after reopen could still describe audio from before it.
- Let Connection call the peer first and ask Receiver to rotate afterward.
  The peer reply and RTP go to different destinations, so that sequence can
  relabel old RTP despite both calls returning successfully.
- Treat a successful receiver rotation as permission to reopen STT ingress.
  The selected recognizer and source-side admission must be rebound separately;
  an ambiguous caller reply must leave effective room ingress closed, even if
  Connection has opened locally after an unobserved arm acknowledgement.
- Clear only the ingress queue. One PCM envelope may already be in the STT
  capability mailbox and can otherwise reach a replacement provider.
- Send `:ended` on hold. Morse can treat it as a normal response-triggering end.

## Implications and verification

Retiring a native STT allocation costs reconnection latency and may truncate a
transcript. That is preferable to inheriting un-attributable old recognition;
avoiding it needs a new provider discard contract with acknowledged origin
isolation. Exact audio-input/output intervals are conservative: audio-input
also reflects recording policy, so a recording change may require a harmless
cutover even when the selected route is unchanged. Do not use global policy
revision as a substitute.

Focused reds must cover emitted old signals delayed across hold/release, old
provider evidence first produced afterward, audio-only revoke/regrant while
transcripts remain demanded, already-sent PCM crossing allocation replacement,
queued and pre-cutoff frames, raw WebRTC RTP and Twilio/Telnyx callback backlog
(including Leg backlog), stale/duplicate/wrong-source acknowledgements, source
timeout/death, fresh media overtaking an arm acknowledgement, overlapping
transfer hold, both enforcer orders, unchanged-policy rebase,
failure-closed readiness, and compiled external/hybrid room response timing.
The first capability red (`selected activity STT resets its provider on
audio-route loss despite transcript demand`) failed 1/1 because no new provider
started after route denial; the scoped reset change now passes that test and
the adjacent 83-test group. This does not prove late-event or hold safety.
Scoped Astra xhigh code review found no concrete regression after 39 focused
tests and eight in-memory probes. It verified both route directions, unrelated
policy rebase, prepared adoption and ingress queue clearing; it did not close
the generation-qualified PCM, emitted-signal or hold gates.

Independent Astra xhigh source review identified the native event generation/
turn-reference seam and the already-sent PCM gap. It was read-only and did not
execute tests, so its broader design risks are not claimed as reproduced
runtime defects. The scoped capability red above is independently observed in
the local test run. See the milestone for implementation tasks and acceptance.
