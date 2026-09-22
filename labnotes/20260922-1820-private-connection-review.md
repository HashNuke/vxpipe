# Private connection review

- Independent xhigh rereview of `39f16427` cleared the original stale receipt and
  ordinary-admission bypass repairs but found the destination-connection variant.
  Main's integrated authority/transfer-room/speech-policy run passes 117 tests;
  this is missing coverage, not evidence against the source-traced race.
- Recorded both reproduction and implementation tasks in the milestone first.
  Extend the queued-ready test with real support connection shutdown after actor
  retirement, while RoomAuthority remains suspended and its genuine completed
  worker result is already queued. Require attempt-local recovery and the exact
  source capability to survive after resumption.
- `validate_enforcers` rejects the dead connection before any candidate barrier,
  but its ordinary error is converted into a fatal generic commit failure. Scope
  the repair to this established pre-barrier private path; do not make uncertain
  application or post-promotion failure recoverable.
- Red confirmed: three selected room review cases, one expected failure, seed 0.
  The new connection-loss variant receives `:handoff_commit_failed` and source
  teardown instead of recovery. The actor-only and staged-participant cases pass.
- Reclassify only `invalid_enforcers` returned by the pre-barrier validation of
  a scoped candidate as `invalid_private_enforcers`. Legacy ordinary admission
  keeps its existing error; enforcement failures are not handled by this branch.
  Validation occurs in Authority, so connection loss after Room's earlier check
  is still rejected before candidate application.
- Integrated green: **118 tests, zero failures**, seed 0, 67.3 seconds. Command
  below, from the owning Call Engine child; full output is recorded in the local
  temporary log `vxpipe-private-connection-review.log`. Existing fatal enforcement
  tests continue to pass; only proven pre-barrier private loss becomes recoverable.
- Independent xhigh source rereview cleared the narrow repair with no additional
  actionable finding. Exact-file formatting and staged diff checks pass. The
  separate native late-attachment timeout remains open; no broad acceptance is
  claimed before the post-commit integration gates.

```sh
ERL_FLAGS='+S 2:2' mix test \
  test/vxpipe/call_engine/media_policy/authority_test.exs \
  test/vxpipe/call_engine/human_web_transfer_room_test.exs \
  test/vxpipe/call_engine/speech_to_text_media_policy_room_test.exs --seed 0
```
