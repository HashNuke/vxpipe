# Repair TTS cancellation

The user explicitly approved the cancellation repair after the tested pause. The
goal resumed; R/A remain the accepted baseline at `935d554`. The preceding turn
made progress by implementing the first cancellation slice and preserving two
review-confirmed failures. This task fixes those failures and the related
deadline/playback findings before continuing D.

## Red and green

Added tests for cancelled-terminal publication after an on-time Output reply is
processed late, repeated pending fence expiry ahead of its queued watchdog, and
caller-reported playback from an outstanding uncredited chunk. The existing
settled-fence and stale-audio tests remained unchanged.

Pre-repair run: **7 tests, 5 failures**, seed **670445**, 1.6 seconds. It reproduced
both prior failures, a late cancelled terminal, an expired pending ticket returned
as success, and rejection of a legitimate 10 ms report for a 20 ms uncredited chunk.

The minimal repair returns retained completed fence tickets without mutation,
checks pending tickets' original deadlines, drops fenced/terminal audio casts,
clears pending audio on begin/settle and matches request identity at dispatch.
Cancelled terminal publication rechecks deadline and allocation after Output.
Output freezes only the outstanding byte count at fencing; credited plus outstanding
bytes bound the supplied playback report, while actual counters use only that report.
No PCM payload is retained by the fence and no process was added.

Same-seed post-repair run: **7 tests, 0 failures**, 1.1 seconds. Astra reviewed the
test barriers and ceiling decision. The numeric 21 ms rejection/10 ms acceptance
test is report validation/accounting evidence, not a physical sink test.

Added callback-first and terminal-first cancellation ordering coverage with a
small controlled provider, absence-of-terminal expiry/descendant cleanup, and
a foreign caller timing out on an old ticket while a replacement remains usable.
Combined run: **11 tests, 0 failures**, seed **670445**, 1.1 seconds. These tests
exercise existing barrier/authority behavior without changing it. Broader checks,
cancellation-aware load and repaired-source review remain pending.


## Broader verification and load

The broader speech/Morse/STT-usage selection passes **120 tests, zero failures**,
seed **337919**, 2.3 seconds. Astra reviewed the repaired source without a remaining
blocker for this bounded slice. Added `bench/tts_cancellation.exs`: persistent
STT/TTS in 1/8/32 scopes, three repeats, pending/credited modes, 24 cancellation and
replacement cycles per scope. All 18 trials pass in 8.2 seconds. Counts: 5,904
cancelled E, 5,904 independently checked completed T, 5,904 recognized STT turns.

The ledger is supplied 10 ms for E and zero for completed T drain cancellation;
it must equal exactly round × 10. This is numerical caller-report evidence, not
physical playback. The harness also checks stale cast/credit/timer rejection,
idempotent bounded replay, last-result eviction, same-scope STT progress under
withheld TTS credit and exact descendant cleanup. Per-repeat distributions and
limitations are recorded in `docs/native-tts-cancellation-findings.md` and the
adjacent `20260919-2245-tts-cancellation.json`. Process count returns to 244 every
trial; final total memory 86.19–88.42 MB. Largest STT text observation 8.215 ms is
retained, without attributing it causally to the repair.

Current root format/compile/Credo checks pass; full umbrella tests are running.
No cancellation source change was made after starting these checks. Further
load lanes wait until this VM has finished to avoid competing timing workloads.


Astra reviewed the load harness: no blocker for its bounded correctness claim.
The report now explicitly distinguishes initial versus replacement first-audio
measurement boundaries, memory snapshot lifecycle differences, and timed active
cancellation versus correctness-only cancellation after completed generation.


## Next D slice: design review only

While the umbrella checks ran, Astra reviewed the pending-acceptance direction.
Return the engine request identity after bounded admission, keep the existing
Input worker, and keep actual `input_submitted` distinct. Clean pre-submission
provider rejection needs one correlated failed result and no usage. A cancellation
can retain one report until the pending speak callback settles; the original speak,
fence and cancel-call budgets must all remain in force. Fencing must still permit
recording genuine in-flight submission evidence without reopening audio. Rejection
after submission cannot masquerade as a harmless unsubmitted request.

A deterministic test must hold the actual consumer while submission is followed
by allocation failure. Merely queuing `input_submitted` is insufficient because
current event ACKs reject after retirement. Choose and document an authoritative,
bounded settlement/evidence path before implementing that slice. Also cover cancel
before Input claims speak, clean rejection while cancellation waits and post-Output
admission/facade deadline checks. These are planned contract tests, not new proved
instability findings. No source was changed for that next slice during this repair.


## Initial umbrella result and isolated rerun

The first current umbrella run used seed **520598**: **1,897 tests, two failures,
40 excluded**. Both failures are existing Gateway phone-transfer cases with
custom URL waits and destination loss: Telnyx did not observe `phone_transfer_failed`
within 2 s; Twilio did not observe recovery speech within 2 s. Engine's 799 cases
and all other applications passed. No speech-repair cause has been established.
The owning harness still uses legacy test transports; this D path is not integrated.
A prior milestone also records a timing-sensitive missing-recovery-speech failure
(`operator-login-and-admin-dashboard.md`, checkpoint 1), which is context rather
than proof of the exact current cause.

Reran both generated groups from Gateway with the same seed, selecting Telnyx
line 320 and Twilio line 321: **10 tests, zero failures, 16 excluded**, 21.3 s.
No source or timeout was changed. All non-test root gates passed, including the
unused-dependency check run separately after the fail-fast wrapper stopped.
A fresh full umbrella run remains necessary; the isolated pass does not erase the
original failures or establish root acceptance. Before that rerun, run the existing
TTS handoff/failure diagnostic serially on this source. The app VM seen locally is
an existing `mix run --no-halt`, not another diagnostic; it was left untouched.


The serial TTS handoff/fault run passed: **36 trials, 3,936 successful TTS and
3,936 STT turns, 492 intentional Output failures/replacements**, 11.7 seconds.
Artifact: `20260919-2245-tts-handoff.json`. Full root `mix test --seed 520598`
rerun has started on unchanged source. No runtime test timeout or assertion was
weakened in response to the first umbrella result.


A further next-slice design review preferred a consumer-retained, bounded request
receipt over per-request facts in ScopeControl: facts kept only in ScopeControl
would disappear with whole-scope loss. No implementation has been selected yet.
Any receipt must preserve immutable attribution, submission provenance and a
bounded provider request ID, not just a submitted boolean. Atomics alone do not
hold arbitrary metadata; the representation requires an explicit bounded choice.
Generated bytes must mean a named local observation boundary, independent of
credit and actual playback. Live snapshots are provisional; finality needs a seal
or confirmed writer teardown because `closed` can precede descendant DOWN. Absence
of committed submission evidence after failure cannot prove no upstream charge.
Historical reads grant no fresh audio or cancellation authority. The next tests
must include unacknowledged submission followed by allocation and scope loss,
partial publication, repeated events and structurally valid nonfabricated outcomes.
This review is planning only and does not change the approved repair source.


## Final verification of this repair

The full unchanged-source rerun passed with seed **520598**: **1,897 tests, zero
failures, 40 excluded**. App counts: MCP 37, Agent Runtime 95, Engine 799, Calls
117, Gateway 460, Artifacts 20, Persistence 184, Console 185. The prior two Gateway
failures remain recorded above. Their exact cause is not established, and no
causal link to the native cancellation repair was demonstrated. All five root
gates now pass. No code or test timeout was changed between full runs.

Astra cleared repaired source and load methodology. Load artifacts are retained:
5,904 cancellation cycles/replacements/STT turns and the separate 3,936 TTS plus
3,936 STT handoff turns with 492 intentional Output failures/replacements. The
latter's maximum observed safe notification/teardown/replacement-ready timing is
5.568/5.569/9.971 ms, with timing boundaries documented in the findings report.

The approved bounded repair is verified. D still requires pending-acceptance
cancellation, ordinary playback settlement, long-phrase/limits and standalone
playout/demo acceptance. R/A remain accepted, progress 2/9, production rooms
remain legacy, and no D checkpoint commit or whole-goal completion is claimed.
