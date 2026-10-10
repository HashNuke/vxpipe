# Comparative pinned-call load harness

Scope: dedicated script, CallEngine test support and tests, methodology documentation,
and milestone F load breakdown. Baseline `5e7fed4c`; isolated assigned load branch.
No production STS/provider/Gateway/author-contract changes, hosted calls, credentials,
history replay, remote operations or manifest enablement.

## Plan and design review

Read workspace instructions, the milestone index, STS milestone F and relevant
STS ownership/input/output contracts, prerequisites, transcript-mode room tests,
and the existing Call-Spec-driven-call fixtures. The latter lives directly under
`test/vxpipe/call_engine/`, not its `room_authority/` directory.
Before tests/implementation, split F's allocation-insufficient load item into
implementation, bounded-contract tests, metrics, smoke and quiet integrated gates.
The methodology document records the choice of pinned room calls and clock-paced
synthetic PCM consumption, and the rejected allocation-only/immediate-playback paths.

Use a fixed local diagnostic model response so all modes take `HI` and return
`RECEIVED HI`. Start calls concurrently, synchronize readiness, complete one turn,
interrupt the second with a third microphone utterance, complete recovery, then
kill one local room authority and complete a fourth turn in each healthy room.
Room and helper descendants are monitored through supervised termination.

## Red/green evidence

- Initial three percentile/bounds/PCM-ledger tests failed with missing modules.
  Both the initial owning-child Mix command and a dependency-free ExUnit invocation
  showed that expected red; the latter then passed 3/3 after implementation.
- The sink test failed because its module was absent, then passed once implemented.
  It checks elapsed PCM acknowledgement and stale completion fencing on interruption.
- The tagged lane initially failed because the runner was absent.
- Real-room smoke exposed harness bugs, not proven runtime defects: sink correlation
  IDs differ from public turn IDs; cleanup must tolerate registry-removal races;
  Morse TTS configuration requires `maximum_requests`. Corrected those only in
  harness support. The initial silent worker failure produced a 90-second barrier
  timeout; failures now notify the coordinator immediately and phases cap at 15 seconds.
- Review found ordinary STT's default ingress owner is nil. Its initial zero drop
  observation was therefore unsupported. Recorded an additional milestone subtask
  before adding the observer test. That test failed for the absent module, then
  passed after wiring the existing optional owner notifications. Final smoke
  reconciles all 162/216 ordinary STT input frames with actual delivery notifications.
- A tightened bounds assertion rejected single-call isolation runs: red showed
  `:ok` for one call; the guard now requires 2–10 calls.
- Final support review added a red assertion that clearing an active sink returns
  its actually consumed PCM duration, not zero. Clear now reports consumed time,
  counts discarded chunks separately and fences the old timer.

## Contended smoke evidence

`bin/sts-call-load smoke`, with installed dependency sources supplied via
`MIX_DEPS_PATH`, uses an isolated `_build` and two schedulers. The final observed
three-mode run passes **3 tests, 0 failures**, seed 0, about 25 seconds. Each mode:

- Two admitted/ready calls; 378 offered microphone frames across seven inputs.
- Five publicly completed replies; two public interruptions; one healthy room
  completes its post-fault input/reply; both rooms and helper processes clean up.
- Zero observed input rejection/ingress drops and output rejections; decoded replies
  and public transcripts match. Intentional interrupted chunks are separately counted.
- All eleven requested latency categories contain measured samples and emit
  nearest-rank p50/p95/p99. Sampled mailbox growth, memory, PCM/chunk counters and
  monitored descendant counts accompany the reports. STS does not expose a delivered
  input counter, so that field remains null; its actual drop counter is measured.

These are functional smoke results under possible contention, not final capacity
or comparative performance evidence. Do not use the emitted smoke latency values
as the quiet-window milestone result. No ten-call measured run was performed.

Final focused child recheck: the five harness contracts plus all three two-call
smoke modes pass **8 tests, 0 failures**, seed 0, two schedulers, 25.5 seconds.
Changed-file format verification, `git diff --check`, shell syntax validation and
owning-child test-environment `mix compile --warnings-as-errors` pass. No full
umbrella suite or final measured comparison was run. Native dependency output
was built under this checkout's own `_build`, while installed dependency sources
were reused via `MIX_DEPS_PATH`.

## Limits and handoff

The parent retains the quiet integrated ten-call window, independent review and
all final serial umbrella gates. Output-STT timeout/usage and output-policy audit
work is parent scope; this harness neither repairs nor claims to prove those gates.
No proven runtime blocker was found by these smoke workloads.

Reproduce with the script or the focused commands in `docs/development/sts-comparative-call-load.md`.
The lane is tagged `:integration`, excluded by default. Synthetic sink consumption
does not prove physical hearing, WebRTC/carrier transport or provider reconnection.
Room-authority fault injection proves the local room-supervision isolation boundary.
The machine reports four CPUs and roughly 7.6 GiB RAM; two schedulers and a 1 GB
total BEAM memory guard remain within the requested approximate half-resource budget.
