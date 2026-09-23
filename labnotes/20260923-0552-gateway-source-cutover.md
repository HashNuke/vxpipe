# Gateway source cutover

Status: design investigation for the existing unchecked STS source-time fence;
no Gateway implementation or room hold acceptance is claimed.

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
