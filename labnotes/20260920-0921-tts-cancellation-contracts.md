# TTS cancellation contracts

## 2026-09-20 — D4 contract audit

- D2 already satisfies D4's held-credit replacement and pending-provider-acceptance
  cancellation slices. Focused tests cover stale credit, one cancelled terminal,
  replacement PCM, both Input/cancel orderings and definite pre-submission rejection.
- The first unimplemented D4 slice was historical TTS accounting. The live event
  queue alone did not expose accounting fields, and allocation revocation makes
  later event acknowledgement invalid.
- The initial candidate sent bounded, payload-free cumulative facts before Channel
  replied to provider submission/audio calls. It introduced no speech-owned process,
  table or journal.

## 2026-09-20 — Initial red/green

- The first red run failed at compile time because `Speech.TTSUsage` did not exist.
  The first candidate made admission-only zero usage and allocation/scope failure
  retention green.
- A playback red test then failed because accounting had no authenticated
  request/session playback totals. The repair kept provider generation separate from
  caller-reported sink playback and required settlement before replacement.
- A terminal-metadata red test failed because a provider request ID first reported at
  completion was lost. OutputState now accepts that first terminal value, retains an
  identical repeated value and rejects conflicts.
- Definite rejection after admission/fence/cancel remains zero usage. Submission
  evidence only exists after a real provider `input_submitted` event.

## 2026-09-20 — Independent-flow defect and repair

- The first candidate used a separate usage recipient. Review found it could queue
  per-chunk facts independently while the media consumer continued granting credit,
  so the recipient option was removed.
- A second candidate sent facts to the media consumer. Astra review found PID equality
  still did not bound a selective-receive mailbox: the consumer could acknowledge
  audio while leaving usage facts queued. The benchmark's coalescing map measured one
  active request but did not measure those queued messages.
- A focused red test reproduced the defect causally in the uncommitted D4 delta. A
  16-character Morse request accumulated 77 standalone facts while the consumer
  acknowledged all media.
- The repair removed standalone fact publication. Channel now attaches an immutable,
  payload-free `TTSUsage` snapshot to the bounded Event and Audio envelopes. Their
  existing acknowledgement/credit protocols bound delivery, so there is no second
  queue, process, receipt or storage protocol.
- Playback stays in the authenticated `Session.cancel/3` return. A successful return
  proves the provider callback accepted the cancellation. If the callback wins the
  race, replacement remains blocked until the terminal settles the request.
  Duplicating playback and settlement into a later asynchronous snapshot was removed.
- The repaired 16-character test receives 75 audio envelopes with monotonic embedded
  snapshots, observes the 24,000-byte terminal total and receives no independent fact
  messages.

## 2026-09-20 — Failure evidence

- The failure test now captures and monitors the exact live Channel before injection.
  It holds the actual consumer before provider submission and withholds the submission
  event ACK. The provider observer confirms that both its submission and first PCM calls
  returned successfully before failure injection.
- Provider/allocation loss, whole capability-scope loss and independent lifetime-owner
  loss each produce the exact Channel and allocation-tree `:DOWN`. Only afterward
  does the test release the consumer and inspect the ordered submission event and held
  320-byte generated snapshot.
- This replaced a permissive check that accepted any dead PID and used
  `Process.alive?/1`. The current test uses exact monitors and no liveness polling.
- Live media acknowledgement remains revoked after failure. The embedded snapshot is
  historical evidence copied before Channel accepted the provider operation.
- This red test initially failed in all three fault modes because Channel acknowledged
  the PCM call while retaining its envelope behind the unacknowledged submission event.
  Channel now sends the ordered audio envelope before returning provider success while
  validation and sink credit remain gated on the submission ACK. New synthesis also
  requires the earlier event queue to be idle, preventing submission evidence from
  queuing behind an unrelated event.
- Two later red tests reproduced the terminal form of the same gap without audio:
  `completed` and `cancelled` each returned `:ok` to the provider while their event and
  terminal-only provider request ID remained buffered behind the held submission ACK,
  then disappeared when the allocation failed. Channel now pre-delivers only the
  matching terminal behind an awaiting submission, records that delivery in the
  existing bounded EventQueue, and promotes it after submission ACK without a duplicate.
- Astra requested a live acceptance case because the failure tests stopped Channel before
  exercising promotion. The added test rejects a terminal ACK while submission owns the
  slot, ACKs submission, observes no duplicate, ACKs the retained terminal, settles the
  request and admits a replacement.
- The broader suite initially reported one intermittent stale-caller failure. A focused
  rerun passed and inspection showed the test could suspend Channel before it had
  observed the replacement Input worker's result, accidentally exercising the 100 ms
  replacement deadline. Synchronizing the Input and Channel with `:sys.get_state/1`
  made the stated prerequisite causal. Five repetitions and the sequential focused and
  broader selections pass. Concurrent Mix test runs were discarded after unrelated
  readiness cases also timed out under build/scheduler contention.

## 2026-09-20 — Verification so far

- Focused TTS: 38 tests, zero failures, seed 530504.
- Broader speech/Morse/usage: 164 tests, zero failures, seed 530504.
- Enabled-usage cancellation load: 18 trials; 5,904
  cancellation/replacement/STT cycles; 132,840 usage-bearing envelopes; no
  independent usage messages; fixed 244 post-trial processes.
- Relative trial-p95 medians versus the D2 same-workload artifact: first audio
  216.5 → 205 µs; cancellation return 145.5 → 112 µs; replacement first audio
  166 → 164 µs; STT end 273.5 → 239.5 µs. Maximum trial-p95 first audio changes
  1,042 → 1,026 µs. Individual trials vary both ways, so this establishes no
  earlier correctness/concurrency/cleanup failure, not a stable latency result.
- Raw load evidence: `20260920-0921-tts-cancellation-usage.{json,log}`.
- Final GPT-6 Astra xhigh review found no remaining blocker after the live promotion
  test and acknowledgement-bound wording correction.
- The first final umbrella run (seed 530504) reported two unrelated timing failures:
  scoped-room participant admission lost its media-policy enforcer deadline, and a
  Telnyx storage-loss handoff missed source recovery speech. The exact scoped-room
  case then passed alone in 234 ms; all five generated Telnyx loss modes passed alone,
  including the failed custom-URL/destination mode. No D4 module or contract appears
  in either failure path. A clean full rerun remains required before D4 acceptance.
- The default-concurrency rerun began under host-wide pressure and produced 15 short-deadline
  failures across unrelated MCP catalog, room mixer, transcript, tools, Morse STT/TTS,
  WebRTC and Telnyx paths. At inspection the 8-CPU machine had load averages
  9.28/9.02/7.83, unrelated Storybook and Spotlight processes consuming substantial CPU,
  heavy memory compression and 18 GiB free on a 98%-used data volume. This distribution
  is not evidence of a D4 regression. The full suite is being repeated with ExUnit
  concurrency reduced to four, preserving every test and the same seed while matching
  this machine's available capacity.
- The four-case-capped full run was worse under increasing external pressure: 28 Call Engine
  and one Gateway failure moved across unrelated startup, catalog, room, recording, tool,
  STT/TTS and media-pipeline deadlines. Reducing ExUnit concurrency did not repair a saturated
  host. Per the user's resource bound, no fourth full run or additional load run was started.
  D4 remains unchecked with the umbrella test gate open. Format, compile, Credo and unused
  dependency gates pass; the focused/broader D4 selections and final isolated load remain green.
