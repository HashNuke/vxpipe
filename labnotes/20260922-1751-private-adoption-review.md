# Private adoption review

Independent xhigh reviewer used source tracing, not Mix. Parent supplied two P2
findings against e543d969; these take priority over late attachment investigation.
Tasks and qualification of prior contract claims recorded before tests/code.

Exact reviewer reproduction 1: start authority with joining participant; start
owner and monotonic actor; register actor with self connection and owner scope;
preview joining; monitor actor; kill owner and await actor killed; confirm snapshot
remains base; commit same candidate/deadline/actor tuple/scope. Expected
invalid_private_enforcers; missing registration currently falls through as ordinary,
so dead actor enters barrier and closes room. Explicit retirement of a still-live
actor similarly allows unauthorized readmission. Test both and room queued result.

Exact reviewer reproduction 2: register private joining actor; ordinary admit
joining succeeds without promotion; killing owner retires actor while joining is
present. Reachable room path: pause after private allocation, kill staged participant
supervisor and await DOWN, then ordinary join of same planned ID with fresh deadline
after registry reservation disappears. Room does not monitor staged participant yet.

Also cover unrelated barrier crossing original private expiry. No independent
expiry bypass was proven by reviewer. Engine-only bounded tests permitted while
parent Gateway gate is live; no native or umbrella runs.

Red evidence (seed 0, ERL_FLAGS='+S 2:2', owning Call Engine child):

- `mix test test/vxpipe/call_engine/media_policy/authority_test.exs --only
  private_review --seed 0`: three tests, three failures. Owner loss returns
  enforcement_failed; explicit live retirement and ordinary admit both succeed.
- Add queued-ready/private-actor-loss and staged-supervisor-loss/rejoin room
  tests, plus unrelated-barrier expiry coverage. Two-file private_review run:
  six tests, five failures (18.9 s). Expiry coverage passes unchanged. Queued-ready
  loss closes policy authority and room; staged-loss ordinary rejoin succeeds.
- First authority guard implementation makes authority reds green, but both room
  tests still fail: rejected private receipt closes room, and staged participant
  identity is checked after policy commit. Recorded the extra pre-barrier room
  validation/recovery work in milestone before implementing it.
- Added distinction test: a live ordinary registration is not a private receipt,
  while legacy commit_candidate/4 remains valid. One test, one expected failure
  before tightening scoped selection to require a private registration.

Implementation rejects missing or ordinary registrations on the scoped path,
blocks ordinary admission with staged actors, and checks exact staged participant
supervisor identity before policy application. Only the two explicit pre-barrier
errors route through existing attempt-local recovery; barrier uncertainty and
post-promotion failure remain fatal. No history, new registry, revised deadline,
weakened snapshot or permission change.

First room/authority green: six selected tests, zero failures (23.2 s). Strengthened
room tests now require recovery completion, ToolCallFailed, cleared pending attempt,
absent destination, unchanged base policy and retained source, not merely absence
of transfer.active. Full two-file run: 89 tests, zero failures (50.3 s), before the
final ordinary-vs-private receipt guard. Final three-file verification is pending.
Parent Gateway lane is terminal and native reproduction is released, but these
review repairs remain priority. No native test was run for this checkpoint.

Final three-file verification: 117 tests, zero failures (67.0 s), seed 0. Room
regressions additionally distinguish rejection from a stale registry reservation
(`room_start_failed`, not `participant_already_exists`), retain the exact source
TTS identity and remove the private support connection on completed recovery.

Reproduction commands, from apps/vxpipe_call_engine with ERL_FLAGS='+S 2:2':

```sh
mix test test/vxpipe/call_engine/media_policy/authority_test.exs \
  test/vxpipe/call_engine/human_web_transfer_room_test.exs \
  --only private_review --seed 0
mix test test/vxpipe/call_engine/media_policy/authority_test.exs \
  test/vxpipe/call_engine/human_web_transfer_room_test.exs \
  test/vxpipe/call_engine/speech_to_text_media_policy_room_test.exs --seed 0
```

To reproduce original findings, apply only the new private_review-tagged tests
onto e9a32226 (no runtime changes). Five original behavior assertions fail; the
unrelated-barrier expiry test passes. The additional ordinary-registration receipt
test also fails until scoped receipts are restricted to private registrations.
The queued-room test puts the real completed worker result ahead of actor-loss
notifications in a suspended RoomAuthority mailbox, waits for policy-owner cleanup,
then resumes. The staged-loss test pauses the worker, kills the exact staged
supervisor and waits for DOWN before same-ID join. No fabricated ready result,
arbitrary sleep, timeout extension or weakened gate is used.

The stronger final identity assertion initially compared the capability PID to
the transport PID from test_tts_transport_started (two assertion failures, not a
runtime replacement). Corrected the test to capture the original capability PID
before handoff; the transport retains its independent DOWN monitor.

Final seven-case private_review recheck passes (19.8 s, seed 0), including the
stronger cleanup and identity assertions. No native case or full umbrella suite
was run; late-attachment diagnosis remains separate and unresolved.
Final root formatting check, strict Credo (1,076 source files) and diff checks pass.
