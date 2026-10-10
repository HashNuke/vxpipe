# Scoped speech experiment

2026-09-19. User authorized an isolated prototype/load experiment before approving the
room migration. The implementation milestone remains paused; this experiment changes test
support, tests, an opt-in benchmark and documentation only. Existing uncommitted runtime
prototype files are preserved.

## Approach and boundaries

Test-only `SpeechExperiment` modules provide an explicit local DynamicSupervisor, temporary
allocation supervisors, independently responsive control and persistent Morse decoder/encoder
workers. Worker initialization happens after lightweight OTP startup and can be held by an
acknowledged test gate. Each allocation monitors its real capability/connector owner. Workers
and control are significant temporary siblings; retirement shuts down both. TTS keeps one
outstanding output credit and filters retired generation messages. A private test bridge
projects semantic events into the existing provider transport boundary.

Real room scenarios use CallSpec compilation, ModelFixture, CallEngine.push_audio, actual room
policy/turn/interruption logic and the existing output sink. Precreated local test scopes avoid
calling a room supervisor synchronously while it is already starting a capability. This proves
behavior through a bridge, not final capability nesting, production scope admission, removal
of old global output/connector task supervisors, hosted protocol support or milestone R.

The existing reviewer independently checked the approach and required truthful PCM connection
readiness, revocation of both transcript consumers, PCM-onset barge-in before the end gap,
correlated arrival timestamps and distinguishing sink arrival from acceptance/playback.

## Red/green evidence so far

- First scope test failed because Scope was absent, then passed after implementation. A fixture
  initially used a 600 Hz sine against the default 700 Hz detector; corrected independent PCM to
  the advertised 700 Hz/4096 amplitude. This was fixture mismatch, not an application regression.
- First real-room experiment failed because Call support was absent. Its separate readiness
  assertion exposed the existing test connection's hardcoded Opus48 kHz track. Added an optional
  explicit input track, preserving the old default. Real room round trips now match independent
  input text and exact independent output PCM on both legacy and scoped paths.
- Permission revocation, expired admission, held-start expiry, one-credit TTS and stale-output
  isolation pass. The blocked-output barge-in test first failed at the missing test sink unblock
  operation; added a bounded toggle allowed only when no write is pending. Seven focused tests
  then passed at seed 0, including PCM onset interruption before the second final gap and one
  clean replacement response.

## Load method

The opt-in bench compares real rooms at 1/8/32 concurrency with three alternating path repeats,
twenty measured burst turns after three warmups, and a separate paced 20 ms input lane. It checks
every transcript/turn/completion count and exact output PCM. A held initializer shares the
first scoped call's explicit supervisor while other speech continues. Its worker is monitored
throughout and closed explicitly afterward.

Recorder timestamps events on arrival rather than after selective receives. Output timing is
first sink invocation and sink finish, not audible playback. Playback acknowledgement is a
controlled immediate test acknowledgement. Production global output-task execution remains in
both compared paths.

## Review corrections and focused verification

- A new exact-replacement-PCM assertion first failed because the recorder combined the
  interrupted request's first frame with replacement output. It now retains frame correlation
  identities, compares only the current turn's PCM, and rejects wrong room/incarnation/
  connection/turn attribution. Legitimate old frames received before the new turn remain
  distinguishable; injected stale generation events/credits cannot appear in the replacement.
- Review required TTS submission to reject before readiness and failed output credit to retire
  its allocation. Both assertions failed against the initial prototype, then passed after
  correcting Control. Readiness rechecks the absolute deadline even when the ready message
  precedes the timer in a suspended control's mailbox. A credit-expiry timer exists, but the
  focused failure test exercises a rejected credit, not a timed-out one.
- Owner-loss tests monitor tree/control/worker individually. A new healthy allocation afterward
  proves the scope remains usable. The separate held-initializer test proves concurrent sibling
  progress. Call.stop now monitors all allocation descendants before shutting down the real
  room, and observes their termination before stopping the outer test scope.
- Real STT prepare/discard/adopt tests preserve the active allocation on discard, adopt a fresh
  resource through actual room joining, ignore injected old-PID EndOfTurn messages, and finish
  subsequent input correctly. A fixture restriction override was needed to test replacement
  rather than accidentally requesting disablement.
- The final focused command passed 11 tests at seed 42 after the timestamp wrapper correction.
  Earlier focused passes at seeds 0/42 preceded that correction. The experiment has no hosted
  network lane and does not claim full proposed-provider conformance.

## Measurement audit and retained evidence

The first main run passed 8,868 turns, but raw-sample audit found 48 negative TTS deltas across
first_audio/sink_finish. Room TextOutput and sink notifications have different senders;
subtracting observer receipt times was an invalid causal anchor. The same test-only TTSMeter
now captures monotonic time immediately before delegated Speak submission on both paths.
Recorder subtracts that source timestamp and the main benchmark rejects negative durations.
This includes recorder scheduling, not pure provider time. The sequential normal-turn marker
does not identify a replacement turn; replacement timing is deliberately absent from the
stress report. The reviewer independently checked these boundaries.

The [first-pass summaries](20260919-1711-scoped-speech-first-pass.json) explicitly invalidate
their TTS fields but retain the valid STT measurements. In particular, the original paced
turn-end p95 was 2.801 ms existing versus 15.307 ms scoped, across 48 turns per path. That
unfavorable observation prompted a fresh-VM follow-up; it was not discarded after fixing
unrelated TTS timing.

Final runs were serial, with no concurrent test/build commands:

- [Main](20260919-1711-scoped-speech-metrics.json): 8,868 measured turns plus 1,476 warmups;
  71.3 seconds, one benchmark test, zero failures. All attribution/content/count checks and
  nonnegative timing checks passed. Per-trial process-count delta was zero throughout; process
  memory changed and conversation/history/GC effects are not a leak or capacity proof.
- [Paced follow-up](20260919-1711-scoped-speech-paced-check.json): 288 measured turns
  (144/path), 49.8 seconds, zero failures. Turn-end p95/p99 was 2.773/5.200 ms existing versus
  2.418/3.875 ms scoped. The initial paced ordering did not reproduce consistently.
- [Burst follow-up](20260919-1711-scoped-speech-burst-check.json): 3,840 measured turns
  (1,920/path), 5.5 seconds, zero failures. Turn-end p95/p99 was 4.513/7.867 ms existing versus
  5.708/9.529 ms scoped. All three paired repeat p95s were higher for scoped execution.
- [Control stress](20260919-1711-scoped-speech-stress.json): 12 trials, 14.5 seconds, zero
  failures. 240 healthy paced turns stayed unfinished before and after control actions, then
  completed correctly. Twelve policy calls revoked transcript routing/saving and rejected
  later recognition; twelve blocked outputs interrupted on PCM onset before the end gap and
  produced exact replacement responses. The policy calls first completed a prime turn.
  At 32 healthy calls, scoped onset-to-sink interruption was 0.082–0.096 ms and the whole
  revoke/teardown/denied-input operation was 0.456–0.507 ms (three samples each).

The main corrected run had a larger scoped burst output tail: pooled sink-finish p99 was
213.800 ms; repeat 2's p99 was 222.757 ms. The separate burst follow-up measured 16.282 ms pooled
scoped versus 28.680 ms existing. Retain the outlier and the repeatable smaller turn-end
overhead; neither performance equivalence nor causally demonstrated call instability follows
from these short runs. Paired order alternates across three repeats, but host scheduling,
thermal state and shared VM resources are not experimentally isolated.

The burst selector initially used constant module attributes in cond, producing compiler
unreachable-clause warnings. Replaced that selector with a runtime argv case, preserving the
same scenarios. This is a benchmark dispatch correction, not a provider/runtime change.

## Completion checks and decision

- Root `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix credo --strict`
  and `mix deps.unlock --check-unused` passed. Credo checked 987 source files with no issues.
- Full root `mix test` exited 2. CallEngine reported 732 tests with the known global-session
  startup regression as its failure. The umbrella failure manifest also recorded Gateway's
  actual prepared WebRTC decoder test. The streamed full log was truncated; do not invent
  that failure's exception or assert a cause from the manifest alone.
- Root `mix test --failed` reran both. The decoder test passed; the global-session test still
  failed: 0/8 sessions completed while startup was held for 300 ms, despite 100 ms budgets.
  Existing production rooms still use the original path; the experiment does not repair or
  accept that rejected global prototype. The full root test gate remains non-green.
- Gateway's complete `room_audio_ingress_policy_test.exs` subsequently passed all 13 tests at
  seed 42. The initial decoder failure remains an unassigned intermittent observation; no
  unrelated runtime/test change was made to hide it.
- The existing GPT-6 Astra xhigh reviewer checked topology/contract gaps, the timestamp
  correction, and final numerical claims. It independently recomputed the JSON percentiles,
  per-repeat ordering and stress ranges without finding a material mismatch. Its requested
  qualification of replacement timing and full permission coverage is in the report.
- Local documentation verification checked 162 relative links and parsed every experiment
  JSON file. `git diff --check` passed. The final status/diff review preserves prior work.
- No production source, dependency or configuration was changed by this experiment. Existing
  uncommitted production prototype work was preserved. No checkpoint was marked implemented,
  no commit created, and no goal resume/rollback performed.

Decision: retain local semantic execution as a candidate, with production migration paused.
The durable [report](20260919-1124-scoped-speech-experiment.md) records measured latency differences,
behavioral evidence and exclusions. Agree latency acceptance budgets before migrating; use
source/worker/publication timestamps to assign the burst overhead before treating it as a
production defect. Checkpoints R/B/E still own actual capability nesting, admission/lease
contracts and complete input/output/privacy/opening/private-transfer acceptance.
