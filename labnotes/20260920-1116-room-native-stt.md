# Room native STT

## Scope

Migrate the ordinary Morse room input path from the legacy transport adapter to the
allocation-local semantic STT session. Keep Deepgram on a private compatibility bridge until
its native provider checkpoint. Verification is bounded to focused tests and, only if needed,
a concurrency run capped at half the machine's online schedulers.

## Checkpoint log

- 2026-09-20: Began B1 by selecting `Provider.MorseCodeSTT.Session` in the existing room
  round-trip test and removing its transport registration. The test already asserts caller and
  connection attribution, final text, completed input turns, decoded output, playback completion,
  and a second response turn.
- Red evidence: `mix test test/vxpipe/call_engine/provider/morse_code/room_round_trip_test.exs
  --seed 0` failed 1/1 at room startup with `:unsupported_call_plan` on the caller's
  `speech_to_text` capability. This is the expected legacy-resolution failure: the catalog still
  selects `Provider.MorseCodeSTT`, while the configured provider is the native session and has no
  transport entry.
- Green implementation: the catalog now resolves Morse STT to the semantic session; the runtime
  accepts a transport-free STT selection; and the room starts a connection-local supervision tree
  containing its speech scope, capability, ingress, and native allocation workers. The existing
  room capability converts only acknowledged semantic events into its established policy-scoped
  turn signals.
- First green attempt found a project-owned integration error: the new tree passed the room
  authority as the ingress diagnostic owner, which emitted an unsupported
  `{:vxpipe_media_ingress, ..., {:delivered, sequence}}` message and stopped the room. The prior
  room path intentionally left that optional observer unset. Removing the newly added observer
  preserved the established contract.
- Green evidence: `mix test test/vxpipe/call_engine/provider/morse_code/room_round_trip_test.exs
  --seed 0` passed 1/1 after the ingress-owner correction.

## Integration findings

- The production boundary is one temporary `ConnectionTree` below the room capability
  supervisor. It owns one `Speech.CapabilityTree`, the STT capability and ingress. Exact
  capability-to-tree registration lets room cleanup terminate the complete connection subtree
  even when the capability is suspended. No application-wide speech process coordinates calls.
- Native Morse starts directly through `Speech.Session`. Hosted Deepgram is retained through the
  private `SpeechToText.LegacyBridge`; its socket, connector and protocol mapping remain inside
  that connection's allocation until checkpoint C replaces it.
- A direct bridge-close test reproduced an orphaned transport when its close callback failed.
  The bridge now fails its own allocation, whose links and supervision terminate the transport.
- Policy adoption tests reproduced two lease races: the preparation owner could exit immediately
  after adoption, and it could exit while the old session retirement was held. The commit path now
  checks the original owner and deadline after adoption and again after retirement acceptance. A
  failed post-retirement check closes the adopted session and fails closed instead of restoring an
  already-retired source.
- A suspended old session reproduced policy commit waiting for full teardown. Retirement now
  waits only for local close acceptance under the original policy deadline; OTP completes subtree
  shutdown independently.
- A provider that emitted an accepted final transcript and then failed its audio call reproduced
  loss of that final evidence through the real async ingress path. The channel now rejects the
  failed in-flight frame as closed, stops admitting new input, and drains the already-bounded final
  event queue before failure teardown. If the consumer does not acknowledge the final event, the
  existing call timeout terminates the drain.

## Isolation and review evidence

- `speech/startup_isolation_test.exs` now holds a native provider before bind and separately holds
  the hosted bridge transport. In both cases another connection-local native Morse tree becomes
  ready and recognizes `E` before the held initializer is released.
- `speech/scoped_room_experiment_test.exs` injects loss of an allocation tree and loss of the
  connection's speech capability tree through production room composition. The affected
  connection tree closes; a sibling connection in the same room still recognizes `E`, invokes
  the model and completes exact PCM playback.
- The focused startup and scoped-room isolation set passes 14/14 tests. The final-drain integration
  and standalone STT session set passes 20/20 tests. An earlier combined 70-test run had one
  1-second media-policy admission timeout while host load was about twice the eight logical CPUs;
  after waiting for the second prepared provider's actual readiness, the scoped suite passed 70/70
  across ten repeats.
- A broader 74-test room slice exposed an ordering race: a failed STT tree could mark the room
  readiness probe failed before the lifecycle's specific `:speech_to_text_unavailable` event was
  handled, producing generic `:startup_unavailable`. The room now cancels and fences active
  readiness/release probes before delivering the specific lifecycle failure. The exact case passed
  20 repeated runs, and the seven-file room slice then passed 74/74.
- Checkpoint review found that the first connection tree passed hosted private initialization in
  retained supervisor arguments. A red status test printed a synthetic private header from both
  the outer child specification and connection tree. `Speech.PrivateInit` now holds the value in a
  redacted, expiring one-shot process; both supervisors retain only its opaque handle, and the
  capability claims the value at its existing private initialization boundary. Parent/tree status
  and child-failure logs no longer contain the sentinel.
- The same review found candidate readiness was combining the current provider resources with the
  selected prepared resources. A focused red assertion observed five resources with a duplicated
  ingress/STT pair. Candidate preparation now returns the connection resource plus only the
  selected ingress/STT generation; the exact test passes.
- Final review found the one-shot private holder survived until expiry if its creator died before
  claim. A deterministic owner-loss test failed before the change. The holder now monitors its
  creator, terminates immediately on `:DOWN`, and rejects a later claim; final Astra review reports
  no remaining P0/P1/P2 finding.
- The combined native STT checkpoint set, including the previously omitted 26-test room
  media-policy suite, passed 101/101 before the final owner-monitor repair. The affected startup
  isolation and scoped-room set then passed 16/16 with the new regression included.
- GPT-6 Astra xhigh found no remaining P0/P1 source defect after the final-drain repair. It required
  the room-level fault and held-start evidence above before checkpoint acceptance.

## Pending acceptance

- Re-run the focused suites and all five umbrella gates. Update the milestone and durable decision
  document only from passing evidence.

## Bounded production-room load

The run used `ERL_FLAGS='+S 8:8'`, so the benchmark capped itself at four concurrent calls on the
eight-logical-CPU host. Unrelated host load was elevated; these are contention results and do not
establish production capacity.

- The ordinary production-native workload completed 32/32 burst turns and 8/8 paced turns. Every
  turn retained exact `E` text, event counts, attribution/correlation and expected PCM output.
- Burst p95 was 0.361 ms ingress admission, 1.871 ms first text, 2.550 ms turn end, 0.474 ms first
  audio and 6.379 ms total. Paced p95 was 0.442 ms admission, 240.904 ms first text including the
  scheduled input, 0.520 ms turn end, 0.242 ms first audio and 903.685 ms total.
- Process count was unchanged across both lanes. Process memory rose by about 3.3 MB during the
  burst samples and 1.3 MB during paced samples before context teardown; this short run is not a
  retained-memory measurement.
- The first four-call control-stress attempt and a two-call repeat timed out waiting for a recorder
  `:started` event. The ordinary paced lane had already passed at four calls. Inspection found the
  benchmark could install its waiter before `Call.turn/2` reset the recorder, losing the waiter.
  A deterministic post-reset barrier reproduced and repaired that harness race.
- After the barrier, the two-call control and four-call stress lanes both passed. At four healthy
  paced rooms, a separate room committed policy in 3.305 ms and another interrupted blocked output
  at the sink in 0.184 ms while all four healthy turns completed. No call shared a speech scope or
  startup queue.

Machine-readable reports:
`20260920-1116-room-native-stt-load.json`,
`20260920-1116-room-native-stt-stress-control.json`, and
`20260920-1116-room-native-stt-stress.json`.
