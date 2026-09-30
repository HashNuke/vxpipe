# RTVI departure readiness

## Root failure and boundary inspection

The root run with the phone acknowledgement and handoff progress fixture
corrections terminates with 2,924 reported tests, one failure, 74 exclusions,
seed 149103. All 1,718 CallEngine tests pass; the 522 Gateway tests have one
failure in `signals bot departure before closing WebRTC when the room ends`.
Its connection exits with `:shutdown` before the expected `peerLeft` payload.

The test ends the room immediately after observing the client's data channel
open. The server's peer notifications pass through `SourceReceiver`, whereas
room termination reaches `Connection` through an independent monitor.
Client-side opening does not establish ordering between these senders.
`Connection.signal_peer_left/1` cannot send without its remembered chat channel;
that path shuts down immediately. The failed log closes the server's ICE agent
about one millisecond after channel negotiation, rather than after its 250 ms
departure grace. These observations support a missing test readiness barrier;
the log alone does not prove the exact callback interleaving.

## Fixture correction

- [x] Inspect root failure and production shutdown/channel handling.
- [x] Establish the RTVI session with `client-ready` and assert its matching
  `bot-ready` reply before terminating the room.
- [x] Verify the owning RTVI file and all root gates.

The original failing root is the red evidence for this unsupported test
synchronization. The corrected case retains actual peer departure delivery and
monitored connection shutdown; it now explicitly covers an established session.
No production shutdown policy, departure timeout, room lifecycle or readiness
behavior changed. No billable provider request was made. The owning RTVI file
passes all three checks in 3.6 seconds at seed 149103. Format, compilation with
warnings as errors, strict Credo and unused dependency gates pass. The full root
run with all three Gateway fixture corrections is terminal, exit zero:
2,924 reported tests, zero failures, 74 excluded, seed 149103. All 522 Gateway
tests pass. All five completion gates are green for this fixture checkpoint.
No new UI or speech/source-cutover runtime state machine changed. ElevenLabs
and final provider milestone acceptance remain pending.
