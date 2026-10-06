# Incoming carrier hangup lifecycle

An authenticated incoming carrier hangup must end the call that owns that incoming entry.
The live two-carrier harness exposed a missing path: incoming media worked, but the backend
rejected terminal events and the receiving room survived remote hangup. Speech authentication
and audio success therefore did not imply call/archive closure.

## Decision

Add the trusted host operation `CallEngine.end_call(tenant_id, room_id, incarnation_id)`.
RoomSupervisor resolves the tenant/room authority and makes one bounded call. RoomAuthority
delegates to its cohesive EndCall policy, which compares the supplied incarnation with its
current snapshot inside that same call and stops
normally with `{:shutdown, :remote_hangup}` only on an exact match. A missing, unavailable or
stale room returns `{:error, :room_unavailable}`. This operation is for trusted hosts; the
Gateway's carrier verifier and pinned incoming-leg identity provide external authorization.

Gateway's incoming leg accepts a matching terminal event in both answering and running
states. Its production admission backend forwards the activation's tenant/room/incarnation
to the Engine operation. An already unavailable incarnation is an idempotent terminal
acknowledgement, never permission to end another incarnation. Room supervision and the
existing archive handoff own normal shutdown and durable closure.

## Rejected alternatives and implications

- Stopping an arbitrary Registry PID from Gateway crosses ownership and risks an identity
  race. The Engine checks the incarnation atomically in its authority process.
- Faking an agent hangup tool effect crosses agent authorization. Carrier termination has
  its own trusted boundary and retains the existing supervision path.
- Waiting for the room's maximum duration leaves a remotely ended call running and fails
  the required bounded closure proof.
- Widening the live timeout hides the missing handler. Local tests cover the protocol before
  another paid dial; the receiving-room live bound remains ten seconds.

The change uses the existing carrier APIs, credential records and supervision. Remaining
leg cleanup follows the existing owner monitors; an already-ended incoming leg retires
without a redundant carrier hangup. No new account permissions or packages are needed.
Terminal events must still match the initialized incoming leg; malformed or unrelated
callbacks cannot acquire this authority.

Twilio's owned `<Connect><Stream>` is bidirectional. Its authenticated matching `stop` frame
is a terminal call event rather than an ignored control frame: Twilio documents that stopping
a bidirectional Stream requires ending the call. The adapter checks account, call and stream
identity before emitting the ordinary `ended` event. It does not treat an arbitrary socket
disconnect as hangup or change Telnyx stream-stop behavior. See
[Twilio WebSocket stop semantics](https://www.twilio.com/docs/voice/media-streams/websocket-messages#stop-message)
and [bidirectional Stream lifetime](https://www.twilio.com/docs/voice/twiml/stream#stop-a-stream).
This uses the existing signed media upgrade and does not add an inbound REST mutation or
require another provisioned status-callback URL.

## Verification

The new Engine lifecycle boundary and the complete lifecycle file pass 19 tests. The Gateway
carrier/decoder/ingress group passes 43 tests, including signed Telnyx terminal events before
and after media start, unrelated-leg rejection, and authenticated Twilio stop with strict
identity checks and no redundant hangup. Lifecycle/platform-tool recheck passes 20 tests
after moving the scope policy into EndCall. Formatting, warnings-as-errors compilation,
strict Credo, unused dependencies and Lean build/oracle/replay pass. The full umbrella run
passes 3,156 tests, zero failures, 103 excluded (seed 930118), including all 1,882 Engine and
549 Gateway tests. The three runner shell suites also pass.

Both paid directions pass reciprocal human markers, exact room shutdown and durable archive
closure (Twilio seed 106192, Telnyx seed 662627). The separate unanswered case passes with
no_answer within its five-second ring bound plus margin (seed 247633). The test node is
stopped. See the
[checkpoint labnotes](../labnotes/20261005-0927-carrier-hangup-lifecycle.md) and
[live milestone](milestones/outgoing-calls-and-live-telephony.md).
