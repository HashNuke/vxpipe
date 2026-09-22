# Gateway handoff ordering

Scope: two tracked intermittent Gateway native handoff failures. Work is isolated
on the assigned Gateway branch; the parent owns serial umbrella gates.

Initial evidence:
- The original root failure reached the final audience assertion in `:waiting`;
  its error did not identify the peer or output generation.
- The release-loss failure published `completed` and `transfer.active` after the
  mock STT transport stopped. The fixture only monitored that transport, not
  RoomAuthority receipt of `:vxpipe_stt_unavailable`.
- A subsequent parent root run failed earlier, waiting for the returned late
  listener's 250 Hz wait tone. This means investigation must cover reconnection
  and ongoing wait output, not only final cue playback.
- The parent notified that its root run is terminal; bounded native checks are
  now permitted. Dependencies and build artifacts were copied into this worktree
  so its compilation does not mutate the main checkout's build/dependencies.

Plan: identify exact peer/generation and compare accepted PCM/RTP egress/native
receipt; control capability-loss delivery and acknowledge the room's boundary.
Do not increase timeouts or treat a passing retry as proof of repair.

Controlled evidence so far:
- Suspending STT capability delivery while disconnecting its transport yields
  transport DOWN with no RoomAuthority failure receipt. The red assertion fails
  at that exact boundary. After resuming capability delivery and awaiting its
  room receipt, the destination release-loss case passes.
- Instrumented native reproduction independently reproduces the original final
  audio failure. The failed output is still held at provisional generation 1;
  native RTP sequence is zero, no output submission was observed, and no RTP was
  emitted. This is missing handoff inclusion, not received Opus tone detection.
- Inspection found adopted-release validation captures a fresh inventory but
  does not compare its connection set with the prepared/cued connections. A new
  connection without policy membership change can therefore be included only
  in the validation snapshot while excluded from actual cue/release operations.
  The controlled attachment regression below confirmed this before repair.

Deterministic runtime reds:
- Hold the preparation worker across the late monitor's departure and rejoin.
  On the original implementation, `await_tone(returned_listener, 250, 2_000)`
  fails. The returned peer emitted/received exactly 13 RTP packets: 12 detected
  1 kHz recovery-cue packets and one edge packet, no 250 Hz waiting. Its native
  output was generation 2072 and released. This reproduces the parent's earlier
  wait-tone failure as failed handoff/recovery, not transport packet loss.
- Add a second connection for the existing caller while destination adoption is
  paused; release the pause immediately after attachment acknowledgement, before
  waiting for ICE negotiation. Participant presence and policy do not change.
  The original implementation reports success but the new caller connection
  fails the ordered 1.5 kHz conversation assertion in `:waiting`.

Repairs:
- Reconcile wait players against previous connection/output ownership. Retain a
  cursor only if an old output survives. Retire a departed episode before making
  a fresh player; preserve multi-sink cursors when another output survives.
- Compare the adopted inventory's connection IDs and owner PIDs with the actual
  prepared/cued set. A difference uses existing closed-gate preparation refresh,
  cue replay and the original deadline. No release is allowed to certify an
  output that was merely present in a new validation snapshot.
- For STT loss during paused adoption/release, deliberately hold capability delivery across transport DOWN,
  prove no owner receipt exists, resume it, then await RoomAuthority's receipt
  for that exact capability before releasing the native gate. The debug receipt
  occurs on entry to its handler; that handler processes loss before any later
  worker-result message can be handled. No runtime failure event is fabricated.

The first eight-case verification attempt passed five cases and failed three.
Both paused-gate destination/participant STT loss paths passed. Requiring the
same exact failure receipt during ordinary preparation was too strict: readiness
monitoring can cancel the capability first. That assertion is now confined to
the paused adoption/release cases. Listener retention and adopted inventory
changes alone did not yet make their controlled regressions green; internal
failure tracing and further repair remained necessary at this point.

Design review (separate from implementation progress): these changes preserve
the approved independent-cursor and cue-before-conversation contracts. Reject
PID-liveness retries, blanket player restarts, added sleeps, and longer runtime
deadlines. A failed player with a still-selected old output remains a failure;
only removed output ownership permits a fresh episode. The inventory check runs
before conversational release, so partial release failures remain fatal.

Temporary bounded PCM/RTP tracing established submission/egress/receipt evidence
and was removed. Final assertions retain bounded, failure-only connection,
participant, generation, hold-state and RTP-sequence diagnostics.

Reproduction from `apps/vxpipe_gateway`, using `ERL_FLAGS='+S 2:2'`:

```sh
mix test test/vxpipe/gateway/http/human_transfer_webrtc_test.exs \
  --name-pattern 'five-participant handoff retains' --seed 0
mix test test/vxpipe/gateway/http/human_transfer_webrtc_test.exs \
  --name-pattern 'human handoff gates destination and then relays conversation with silent_all waits' --seed 0
mix test test/vxpipe/gateway/http/human_transfer_webrtc_test.exs \
  --only gateway_release_loss:true --seed 0
```

The first two fail with their controlled regression edits on the baseline
implementation (`5e7fed4c`). The STT red places an immediate positive receipt
assertion before resuming the suspended capability; the final test instead
asserts absence there and requires actual receipt after resumption.

Verification remains in progress. No hosted speech/carrier services, credential
changes, provider advertisements, full umbrella tests or remote writes occurred.
The parent owns integration review and final serial umbrella gates.

Further isolation:
- The controlled preparation pause actually fails private policy refresh before
  wait-player reconciliation: the private snapshot is revision 8, current room
  revision 10, and `Enforcer.apply` rejects `:unexpected_policy_revision`.
  `PrivateMedia` applies speech capability first, followed by ingress and media
  actors; this is a shared policy/STT boundary, not evidence that the tentative
  wait-player retention change repairs the returned-listener failure. Parent
  coordination is required before changing those contracts.
- The adoption test now suspends the worker after the native gate is reached,
  acknowledges adoption within its unchanged deadline, connects the new caller
  completely, then resumes validation. This avoids conflating adoption-set
  validation with a still-negotiating transport. This revised regression passes
  with the inventory repair (two-case diagnostic: one pass, one policy-gap fail).
- An independent audience-stage regression suspends the phase across removal
  and rejoin before private destination media exists. With the original
  participant-ID-only retention algorithm it fails deterministically:
  `Player.reconcile` calls the departed process and exits `:noproc`, followed by
  the missing 250 Hz assertion. This isolates the old-player bug from private
  policy refresh (one test, one failure, seed 0, 157.8 s). The surviving-output
  retention repair is restored for the final bounded native verification.
- The owning Call Engine transfer-room and wait-player files pass together:
  52 tests, zero failures, seed 0. Final native and static verification remains.

Policy-gap reproduction for the coordinating parent: in the five-participant
case, immediately before the later `departing_player` removal (after observer
reconnection), retrieve `Phase.scope(phase).worker.pid` via the existing
`{:ok, %{worker: %Task{pid: worker}}}` match. Suspend that worker, execute the
existing `remove_native_listener` and `join_native_listener` calls inside
`try/after`, and resume the worker in `after` before `await_tone`. This keeps
private destination actors at their old policy while the room processes both
presence revisions. Temporary logging of `PrivateMedia.refresh`'s `apply_base`
error and old/new revisions produced `{:error, :unexpected_policy_revision}`,
8, 10. Remove that instrumentation afterward. This controlled failure remains
unrepaired; the committed audience-stage suspension exercises the independently
repairable dead-player issue instead, without concealing this separate blocker.

Final scoped native verification: nine tests, zero failures, 59 excluded, seed 0,
206.7 seconds. From the Gateway child with `ERL_FLAGS='+S 2:2'`:

```sh
mix test test/vxpipe/gateway/http/human_transfer_webrtc_test.exs \
  --name-pattern 'five-participant handoff retains|human handoff gates (destination|participant) and .*silent_all waits' \
  --seed 0 --trace
```

This includes the controlled audience departure/rejoin, fully negotiated extra
connection during adoption, destination and participant ordinary preparation
loss, and all four owner-acknowledged adoption/release loss paths. The changed
Elixir files pass targeted formatting; strict Credo reports no issues (its file
selector still loaded 1,075 source files). `git diff --check` is clean. Temporary
runtime/packet tracing is removed; `PrivateMedia` has no final changes.

Final owning-child recheck also passes: 52 tests, zero failures, seed 0, 50.0 s.
From `apps/vxpipe_call_engine` with `ERL_FLAGS='+S 2:2'`:

```sh
mix test test/vxpipe/call_engine/human_web_transfer_room_test.exs \
  test/vxpipe/call_engine/wait_sounds/player_test.exs --seed 0
```

All local test processes have exited. Parent notified that the quiet measurement
window is available; no further compile/tests will run during that window.
Full umbrella/static integration gates remain parent-owned and were not run here.
