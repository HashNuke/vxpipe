# Gateway source cutover

Status: Gateway provenance enablers and a receiver-owned WebRTC peer barrier
are implemented in focused checkpoints; room hold/reopen acceptance remains
unchecked.

## Reproduced problem

Astra xhigh suspended a callback-delegating test process, queued raw WebRTC
RTP or telephony media before STT ingress reopened, then resumed the callback.
Both paths built `AudioFrame.received_at` after the cutoff and dispatched old
payload. Supplying the original pre-cutoff timestamp instead made the committed
STT ingress return `{:error, :stale_frame}`. This is a source timestamp gap,
not a regression in commit `05b02718`'s ingress check. The milestone records
it under the existing cutover task.

## Current process path

- ExWebRTC `PeerConnection` emits `{:ex_webrtc, peer, {:rtp, ...}}` to the
  configured controlling process. `Vxpipe.Gateway.WebRTC.Connection` drops RTP
  when its handoff gate is held; otherwise `IncomingAudio.forward_connection`
  builds an `AudioFrame` with `System.monotonic_time(:millisecond)` when its
  handler runs. The WebRTC speech normalizer preserves `received_at`.
- Twilio/Telnyx WebSock owners decode raw frames and dispatch `Telephony.Event`
  asynchronously through `Gateway.Telephony.Leg` to `MediaSession`. The latter
  drops media while its handoff gate is held; otherwise it builds `AudioFrame`
  with handler-time `System.monotonic_time(:millisecond)`. Telephony speech
  normalization preserves that field.
- `Media.HandoffGate` currently holds output and sets a held flag on the
  Gateway callback. Its release handler opens STT ingress before clearing the
  flag. It does not by itself close/retire selected native STT or provide a
  source-issued generation across the upstream processes.

## Design constraints and next proof

An ingress-only timestamp or a clock read inside the eventual Gateway handler
cannot classify raw media already queued upstream. An acknowledged source
barrier must precede release, or the source must issue a generation before
asynchronous forwarding. WebRTC's callback mailbox and telephony's WebSock →
Leg → MediaSession chain need separate focused reds; process ordering must be
proved across every hop, not inferred from one GenServer call. A synchronous
MediaSession wait on a socket barrier may deadlock if prior socket events need
MediaSession to finish first; prefer an asynchronous continuation or a worker-
owned sequence if that concern is confirmed by a focused test. Keep room STT
close/retire/ready/rebind/open and external/hybrid controller wiring unchecked
until the source fence is proven.

## Reviewed candidate and correction

The handoff worker already calls each connection adapter's `hold/2` and
`release/3`; `Gateway.Media.ConnectionReadiness.binding/4` carries a transport
binding. WebRTC's binding includes the ExWebRTC peer PID, and telephony's
includes the WebSock owner PID. A source barrier may help establish order, but
the first hypothesis below was too weak by itself:

1. Keep the Gateway callback held and selected STT ingress closed.
2. Acknowledge the upstream source process after its already-enqueued raw
   media has been emitted or dropped. For WebRTC, the peer is a GenServer that
   emits RTP directly to its controlling connection process; a peer call may
   establish a sender-order barrier, subject to focused proof against its
   actual worker topology.
3. For telephony, the WebSock owner submits events asynchronously to `Leg`,
   which synchronously calls the MediaSession backend. A socket acknowledgement
   alone is too early; a subsequent Leg acknowledgement must wait until the
   older media dispatches have completed while MediaSession is held.
4. Only then bind/open the fresh STT origin and clear the Gateway held gate.

Scoped Astra xhigh design review reproduced raw-message bypasses in both
Gateway paths using in-memory tests delegated to real callbacks. For WebRTC,
queued raw RTP had a pre-cutover monotonic time while its eventual `AudioFrame`
was stamped afterward; telephony behaved the same. The reviewer proposed an
acknowledged source-admission epoch fixed before asynchronous forwarding. The
epoch must stay immutable in an old receiver or a WebSock event; a mutable
relay merely moves the race. WebRTC's `PeerConnection.controlling_process/2`
can change the notification destination without replacing the peer, but the
default synchronous timeout and non-media ordering need proof. Telephony must
carry the epoch through SocketDispatch and Leg; a socket ack alone cannot
drain Leg, and stale media should ack `:ok` rather than kill the socket. A
MediaSession-to-socket-to-Leg synchronous cycle must be avoided.

This is not yet an implemented or fully approved contract. The reviewer did
not test a live peer or phone socket, and no local barrier proves remote
capture, ICE/DTLS buffering or TCP receipt-time semantics. The milestone now
breaks the work into WebRTC, telephony and coordinated ordering/failure tests
under its existing source-time task. The next step is focused red tests at
each owning callback boundary; no hosted provider is involved.

## Telephony provenance enabler

Focused Twilio and Telnyx socket tests sent decoded media through the actual
asynchronous Leg dispatch, with Twilio's Leg suspended until both start and
media requests were queued. Both initially failed on missing `received_at` in
the media packet. A Gateway MediaSession/STS-input test then failed because
the delivered frame's `received_at` was assigned during MediaSession handling,
not retained from its packet (observed values differed by 12 ms in the first
red run). These are local callback/queue reproductions, not live WebSocket
arrival proofs.

`MediaPacket` now carries optional paired, validated monotonic `received_at`
and private `source_epoch` evidence. Both WebSock callbacks stamp the pair
before SocketDispatch; MediaSession preserves it in `AudioFrame`, including
through telephony STS conversion. Direct project-owned events without the
socket provenance retain the previous handler-time compatibility path.
The focused Twilio/Telnyx/STS-input group passes 28/0 (seed 0). No source
hold/arm API, raw-mailbox fence, stale-epoch rejection or room coordination
exists yet; the milestone parent task stays unchecked.

Astra xhigh read-only review reran the 28-test focused group and 13 in-memory
probes (all green). The probes covered wire-field spoofing, paired packet/event
validation, negative/zero monotonic times, default timebase, distinct socket
epochs, stalled Leg delivery for both providers, wrong-owner rejection,
PCMU/Opus conversion and legacy unstamped events. No actionable runtime
defect was reproduced. Review found two inaccurate documentation phrases
about the current telephony stamp point and which committed provider test
suspends Leg; those were corrected. This review does not satisfy the open
hold/reopen or native-socket acceptance tasks.

Post-commit gates for `efb63f66`: root `mix format --check-formatted`,
`mix compile --warnings-as-errors`, `mix credo --strict` (1,097 source files,
no issues) and `mix deps.unlock --check-unused` all exit successfully.
Root `mix test` stops before tests while creating the Persistence test database:
PostgreSQL SCRAM requires a password absent from local test configuration.
No credential was added, printed or inferred. This is an environment blocker
for that gate, not a passing umbrella test result.

## WebRTC notification provenance enabler

ExWebRTC `PeerConnection` sends all notifications to one controlling process
and exposes `controlling_process/2` as a synchronous owner change. A new
per-connection `SourceReceiver` is installed before the peer starts. It owns
one immutable private epoch, stamps RTP with monotonic time, and forwards
non-media notifications unchanged. The Connection accepts only an exact
receiver/epoch envelope when that receiver is installed; the legacy direct
RTP handler remains for isolated callback fixtures but is closed in production.
The stamped evidence reaches the STS input frame.

Red evidence: two focused tests failed because `SourceReceiver` was absent;
after adding it they pass. Reworking the existing STS-only Connection test
to use receiver envelopes then failed at the missing Connection callback
clause; it now passes with stale-old-epoch rejection and fresh sequence
continuation. The SourceReceiver test suspends the old owner, queues RTP,
starts a successor, observes the successor event, then resumes the old owner
and verifies its event still carries the old epoch. The source/connection/STS
group passes 16/0 (seed 0). The two existing HTTP WebRTC files exit 0 on
seeds 0 and 1 with actual local peers. These tests do not execute a peer
owner switch across STT hold/reopen, prove a drain/barrier, or classify media
buffered below ExWebRTC; the parent task remains unchecked.

After the first green run, Connection reached 815 lines, beyond the strict
module-size boundary. RTP source validation, track lookup and forwarding were
extracted into the cohesive `Connection.SourceAudio` module; Connection is
745 lines and the same 16 focused checks remain green. The separate receiver
process remains an owner-lifetime component, not a transfer cutover protocol.

Astra xhigh read-only review cleared the latest extracted diff after 16/0
focused tests and eight additional in-memory probes: actual peer startup
notifications, mixed notification ordering, owner/receiver/peer teardown,
raw-RTP rejection, wrong receiver/epoch/peer rejection, held-input rejection,
and STS evidence preservation. No actionable defect was reproduced. The
monotonic timestamp is SourceReceiver **handling** time, not peer emission or
network arrival time. The immutable epoch is what preserves old-receiver
identity when that handling is delayed; no switch/drain guarantee is claimed.

Post-commit gates for `5c956f59`: root format, warnings-as-errors compile,
strict Credo (1,099 source files, no issues) and unused-dependency checks
exit 0. Root `mix test` exits 1 before tests during Persistence test-database
creation because local PostgreSQL SCRAM authentication lacks a configured
password. No credential was changed or logged. This remains an environment
blocker for the umbrella test gate, not a runtime regression attribution.

## Rejected Connection-side barrier and candidate receiver-owned cutover

`PeerConnection.controlling_process(peer, same_receiver)` is a documented
synchronous call that processes in the peer GenServer without replacing its
notification owner. The first candidate called it from Connection and then
asked Receiver to rotate. That is **rejected**: Astra xhigh reproduced an RTP
notification emitted by the peer before the barrier but processed after the
Connection-to-Receiver rotate under OTP off-heap signal contention. The peer
sends RTP to Receiver and its reply to Connection, so this is not a same-
sender/destination ordering guarantee. The old receiver-local test sends RTP
and rotate from one test process and cannot disprove this cross-sender race.

Reproduction method to retain for future teammate work: run an actual local
ExWebRTC peer with the current receiver configured `message_queue_data:
:off_heap`; warm its signal queue with 64 concurrent senders of 4,000 benign
messages. From inside the peer process, emit one raw RTP notification to its
owner using `:sys.replace_state` without changing peer state. From Connection,
call `PeerConnection.controlling_process(peer, same_receiver)` and then the
old `SourceReceiver.rotate` API while coordinating receiver suspension with
send tracing. Compare the old packet's forwarded epoch to the old and fresh
references. Astra observed `actual == fresh`; the parent reran the bounded
probe on OTP 28.5 and reproduced `fresh?: true` on trial 1 (exit 0). This is a
diagnostic probe, not a default test: it uses VM signal-buffer contention and
dependency state instrumentation. See the
[OTP signal ordering contract](https://www.erlang.org/docs/28/system/ref_man_processes.html)
and the
[OTP parallel-signal explanation](https://www.erlang.org/blog/parallel-signal-sending-optimization/).
The fix's focused tests must encode the project protocol deterministically, and
the off-heap challenge should be rerun as a separate adversarial check.

The revised candidate has Receiver call the peer itself, queue a private
post-ack commit marker, return to its loop to process older notifications,
then commit the new epoch at that marker. Mutating on the nested call return
would still be unsafe because selective receive can leave RTP unhandled.
Astra's in-memory challenge held the old epoch through 100 off-heap trials;
that is design evidence, not a committed regression or live room proof.
Peer/receiver timeout, operation token, absolute deadline and downstream
fail-closed state still need implementation. Avoid synchronous
RoomAuthority→Connection calls that could cycle with Connection→room input
preparation. ICE/DTLS packets not yet delivered to the peer are outside this
local mailbox guarantee.

Receiver-local red/green: the focused rotation test failed 1/1 because
`SourceReceiver.rotate/4` did not exist. It now passes 3/0 in the receiver
test file. The call requires the exact old epoch and a positive bounded
timeout; a stale second call leaves the fresh epoch intact. The test queues
old RTP before the rotation call and verifies old/fresh envelopes. This
does not include a peer barrier or any room/Gateway release path.

Timeout hazard reproduced before committing: `GenServer.call` timeout does not
remove a queued `{:rotate, old, new}` from the receiver mailbox. If the
receiver is suspended longer than the caller timeout, it may later apply the
rotation despite the caller reporting failure. The existing milestone timeout
task now explicitly requires a late-queued-call reproduction and execution-
deadline check. The focused suspended-receiver red failed 1/1: after the
10-ms call timed out and the receiver resumed, its next RTP carried the
new epoch. An absolute execution deadline now rejects that late queued
request, and the receiver test file passes 4/0. Caller-side closed state
still has to handle an ambiguous reply-timeout race before this is usable
as a live cutover.

## Receiver-owned peer barrier implementation in progress

The first receiver-local `rotate/4` API is removed from the current worktree:
it permitted a caller to bypass the peer ordering barrier. A focused new
red test called `bind_peer/3` before that API existed and failed with the
expected undefined function (one test, one failure). The replacement receiver
owns a fixed peer binding and calls `PeerConnection.controlling_process(peer,
self())` itself. After the peer acknowledgement, it queues a private
`{:commit_source_epoch, token}` marker, returns to its mailbox, forwards
earlier peer RTP under the old epoch, and commits only at the marker. A
monotonic absolute deadline is checked both when handling a queued request
and before committing, so a timed-out suspended request cannot mutate later.
The Connection binds its newly started peer before continuing startup.

A fake peer GenServer reproduces the same sender/destination ordering: it
sends non-media and RTP to Receiver before replying to Receiver's barrier
call. The focused receiver test verifies old RTP, non-media passthrough,
fresh RTP after the marker, stale-old-epoch rejection, peer-barrier error,
unbound/different/dead peer rejection and the suspended/expired cutover case.
The receiver file passes 6/0; receiver, STS-input and local HTTP WebRTC files
pass 20/0 on seeds 0 and 1. These are protocol tests, not proof of a live
room hold/reopen. The peer's public call has its
dependency-owned five-second default timeout; a caller using a shorter
deadline must fail closed, and the remaining room integration must not reopen
on an ambiguous timeout. A first independent read-only review and an actual-
peer off-heap challenge are recorded below; room integration remains pending.

First independent read-only review reran the actual `ExWebRTC.PeerConnection`
with Receiver's mailbox configured `message_queue_data: :off_heap`: 100/100
old/fresh epoch trials held after 64 senders × 4,000 warmup messages and
16 senders × 100 contention messages per trial. The probe emits RTP from
inside the actual peer via `:sys.replace_state`, preserving the peer's sender
identity while avoiding a remote ICE/media fixture; it compares forwarded
epoch references before and after the receiver-owned cutover. This is the
same adversarial signal-buffer method that broke the rejected Connection-side
barrier, and is a diagnostic challenge rather than a default test. Six
additional local probes found no defect in wrong rebinding, dead peer,
peer death during barrier, receiver death, late peer reply after timeout or
owner death. A production startup probe confirmed the Connection binds its
exact peer and rejects wrong-peer RTP downstream. The reviewer observed that
a caller deadline shorter than ExWebRTC's five-second peer-call timeout leaves
Receiver processing blocked until that peer call returns, even though the
absolute deadline prevents a late epoch commit. This is a remaining caller-
side timing/availability contract, not evidence of a completed room release.

Post-commit root gates for `eae445ae`: `mix format --check-formatted`,
`mix compile --warnings-as-errors`, `mix credo --strict` (1,099 source files,
no issues) and `mix deps.unlock --check-unused` exit 0. Root `mix test`
exits 1 before tests while creating the Persistence database because local
PostgreSQL SCRAM authentication has no configured password. No credential
was added, logged or inferred. This is an environment acceptance blocker,
not a passing umbrella result.

An explicit Codex Astra xhigh read-only review independently reran the
20-test Gateway receiver/STS-input/HTTP group, 100/100 actual-peer off-heap
trials and six lifecycle/timeout diagnostics; it reproduced no defect in the
receiver-owned cutover. Its startup probes passed 5/5, including exact
Connection/Receiver/peer binding and sibling shutdown on peer/Receiver death.
It separately reran the already-known external/hybrid room-control reds:
`timeout 45s mix test test/vxpipe/call_engine/room_authority/sts_transcript_modes_test.exs:93
test/vxpipe/call_engine/room_authority/sts_transcript_modes_test.exs:105 --seed 0`
from the Call Engine child. Both fail because no STS reply reaches the room
sink; they are not Gateway regressions and remain outside this commit.

Reproducible off-heap challenge recipe for future teammate development:
run a bounded inline ExUnit diagnostic under `MIX_ENV=test mix run --no-start
--no-compile` in `apps/vxpipe_gateway`, with real `ExWebRTC.PeerConnection`
controlling a `SourceReceiver`. Inside Receiver's `:sys.replace_state`, set
`Process.flag(:message_queue_data, :off_heap)`. Warm its queue with 64 tasks
each sending 4,000 benign messages and await them all. Suspend the peer;
start a cutover in another task and trace Receiver's `{:controlling_process,
receiver}` GenServer call into the peer before continuing. Add 16 tasks of
100 benign sends. Inside the actual peer's `:sys.replace_state`, send to its
current owner valid RTP sequence 1, one non-media notification, then RTP
sequence 2. Resume the peer. Require cutover `:ok` and observe, in order,
old-epoch RTP/1, unchanged non-media and old-epoch RTP/2; then emit RTP/3
inside the same peer and require the fresh epoch. Reject an old-epoch second
cutover as stale. Tear down both children and repeat 100 times. A separate
late-ack variant uses a 30-ms caller deadline, waits for timeout, then
resumes the peer and checks that old RTP keeps the old epoch. This exact
method formerly exposed the rejected cross-sender race; it does not assert
real ICE/DTLS capture timing.

The review measured one important bound: when a peer is suspended, a 30-ms
cutover caller times out while Receiver remains inside ExWebRTC's fixed
five-second peer call; non-media waits about 5,001 ms. The old epoch stays
intact, but a future live caller must choose a compatible deadline, keep
downstream admission closed on uncertainty and treat Receiver availability
as part of its recovery contract. The same limitation is left visible in
the milestone task.
