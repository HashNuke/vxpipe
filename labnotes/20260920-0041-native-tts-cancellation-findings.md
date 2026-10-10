# Native TTS cancellation findings

> Relocated from `docs/native-tts-cancellation-findings.md` on 2026-10-09. First recorded source commit: `642779e0afe9` (2026-09-20T07:41:06+07:00).
> Historical research/implementation archive. Original status, failures, proposals and acceptance claims below describe their recorded checkpoints; relocation does not update or reapprove them.
> Related task records: [20260919-2245-repair-tts-cancellation](20260919-2245-repair-tts-cancellation.md).
> Maintained contracts/progress: [speech-provider-contract](../docs/speech-provider-contract.md), [speech-session-ownership](../docs/speech-session-ownership.md), [simpler-speech-integrations](milestones/simpler-speech-integrations.md). Detailed contract refinements are deferred to the separately reviewed documentation work.

The user approved repair after the tested cancellation pause. Five reproduced
regressions are now fixed; 11 cancellation tests and the broader 120-case
speech/Morse/usage selection pass. GPT-6 Astra xhigh reviewed the repaired source
without a remaining blocker for this bounded slice. Cancellation/fault load and all
five current root gates pass; the final umbrella rerun has 1,897 tests, zero failures
and 40 exclusions (seed 520598). Checkpoint D remains uncommitted and unaccepted. R/A remain the
accepted baseline at `935d554`; production rooms still use the legacy providers.
The later [early-admission change](20260920-0041-native-tts-request-admission.md) is paused after
a new cancellation regression; the successful results here describe the preceding
repair source and do not certify that later change.

The earlier [handoff repair](20260920-0041-native-tts-deadline-findings.md) passed its own full
verification before this cancellation implementation was added.

## Reproduction

From `apps/vxpipe_call_engine`:

```sh
mix test test/vxpipe/call_engine/speech/tts_cancellation_test.exs --seed 670445
```

The run on 2026-09-19 finished with **4 tests, 2 failures**, in 0.8 seconds.
These original red observations were preserved before the user-approved repair.

1. **Repeating a settled fence closes a usable allocation.** The test synthesizes
   `E`, withholds audio credit, fences output, completes cancellation with zero
   confirmed playback, and acknowledges the cancelled terminal. Repeating the
   same fence returns `{:error, :command_timeout}`. A subsequent `speak("T")` on
   the same allocation returns `{:error, :closed}`. This proves failed reuse,
   not merely an unexpected error label.
2. **Replacement acknowledgement releases stale audio.** After fencing, the test
   replays a real old envelope as a delayed Output-to-Channel cast, then finishes
   cancellation. It holds the replacement provider immediately after speak
   acceptance, so fresh audio cannot obscure the observation. Acknowledging the
   replacement's `input_submitted` delivers the old envelope. This is a controlled
   queued-message simulation, not a frequency measurement under ordinary load.
   The envelope retains its old request identity and `validate_audio` rejects
   stale envelopes; this test does not demonstrate audible old audio.

The earlier two tests passed: held-credit cancellation permits independently
checked different-text replacement, completed cancel-result replay is harmless,
and an abandoned fence retires provider, Output and allocation tree by deadline.
A broader **111-case speech/Morse/STT-usage** selection also passed before the two
new regressions were added (seed 844779). Those passes do not override the failures.

## Original causes and applied repair

Before the repair, Output cleared its current request after settlement, but Channel
retained the old fenced request reference. A repeated fence reached Output's empty
slot, and Channel treated its stale-request rejection as an uncertain timeout,
retiring the allocation. The repair returns the exact retained completed ticket
before attempting another mutation; a repeated pending fence checks its original
deadline.

Channel also accepted a cast for a fenced/terminal request and saved it in
`pending_audio`; that value survived settlement/new admission. Dispatch used the
replacement's flags without matching the pending envelope's request identity. The
repair rejects these casts, clears pending audio when settling/beginning, and
requires exact current request identity at dispatch. Output retains its independent
freshness validation.

GPT-6 Astra xhigh identified both paths during source review; the focused tests
confirmed them. Three additional review findings were then reproduced by focused
tests before implementation:

- The provider's cancelled event needs a post-Output-handoff original-deadline
  and allocation check even when its cancel callback is still pending.
- A repeated pending fence must not return an already-expired ticket ahead of
  the queued watchdog.
- Playback validation originally capped the supplied actual total at credited
  bytes. A sink may accept/play an outstanding chunk before its credit ACK
  reaches Output; interruption reporting must resolve that case without deriving
  actual playback from generated bytes.

Keep authority, timers and effects in Channel, credit/playback counters in Output,
and the existing Input executor. After the regression tests are green, a pure TTS
request-state value can separate the growing request bookkeeping without adding
another process or authority. Ignoring stale-envelope delivery because later
validation rejects it, treating repeated cancellation as a fatal error, or weakening
the regression assertions are rejected alternatives.

## Verification of the approved repair

The combined regression selection first ran **7 tests, 5 failures**, seed 670445,
in 1.6 seconds: settled replay, queued audio, late cancelled publication, expired
pending replay and an uncredited 10 ms playback report all failed as predicted.
The minimal repair then passed all seven with the same seed in 1.1 seconds.

Additional tests cover callback-before-terminal, terminal-before-callback,
absent-terminal expiry and a foreign caller timing out on an old ticket while
replacement audio remains usable. All **11 cancellation tests pass** (seed 670445),
as do **120 speech/Morse/STT-usage cases**. The playback test validates caller
reports and accounting; it is not physical sink evidence. The repair adds no
process and does not derive actual playback from generated or credited bytes.

GPT-6 Astra xhigh reviewed both the regression barriers and repaired source. The
current/last ticket cache stays bounded, read-only replay does not claim mutation
authority, and stale ACKs cannot double-count the outstanding snapshot. No new
reliability blocker was found in this bounded slice.

The approved repair is verified. Complete pending-acceptance cancellation, ordinary
playback settlement, long-phrase and standalone demo/load gates before accepting D. The preceding repair's
1,886-test/full-load result remains separate evidence for its earlier source.

See the original [cancellation labnote](20260919-2224-native-tts-cancellation.md)
and [repair labnote](20260919-2245-repair-tts-cancellation.md).


## Cancellation load evidence

Run serially from `apps/vxpipe_call_engine`:

```sh
MIX_ENV=test mix run bench/tts_cancellation.exs /tmp/tts-cancellation.json
```

All **18 trials passed** in 8.2 seconds: 1/8/32 scopes × three repeats × two
credit states, each with 24 cycles per scope. Each scope keeps one STT and one TTS
allocation throughout. Across all trials: **5,904 cancelled E requests, 5,904
completed replacement T requests and 5,904 STT turns**. STT completes while the E
chunk is withheld. Every T is checked against independently constructed PCM.
The caller supplies 10 ms for E and zero for the completed T's remaining sink
lifetime; reported session totals must equal exactly 10 ms per cycle.

Each cycle checks duplicate fence/cancel, old result eviction, a delayed old audio
cast, old credit/timer messages, and exact request identity. All scopes finish with
empty session supervisors and monitored provider/Output/tree teardown. The memory
snapshots are taken at different lifecycle stages (sessions ready before the trial,
scopes removed afterward), so they do not measure a like-for-like delta or establish
a peak/leak bound. Final process count is 244 in every trial; total VM memory after each trial ranges from
86.19 to 88.42 MB. Closing both allocations takes at most 1.793 ms in this run.

For 32 scopes, each cell is **p95/p99 milliseconds**, measured separately per repeat
and credit mode (768 samples per cell):

| Repeat | Credit | Fence | Cancel terminal | Replacement first audio | Replacement generation end | STT text | STT end |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | pending | 0.151/0.325 | 0.786/1.022 | 0.609/0.940 | 17.640/18.273 | 0.894/1.241 | 0.610/0.864 |
| 1 | credited | 0.133/0.227 | 0.586/0.794 | 0.528/0.701 | 17.650/17.923 | 0.694/0.993 | 0.509/0.669 |
| 2 | pending | 0.215/0.368 | 0.965/1.432 | 0.666/1.113 | 20.386/29.681 | 1.112/1.859 | 0.725/1.392 |
| 2 | credited | 0.142/0.252 | 0.710/2.196 | 0.583/0.899 | 19.340/20.616 | 0.766/1.125 | 0.555/0.946 |
| 3 | pending | 0.193/0.453 | 0.755/1.068 | 0.679/1.043 | 20.424/29.259 | 0.992/1.753 | 0.705/1.209 |
| 3 | credited | 0.151/0.312 | 0.720/0.997 | 0.576/0.799 | 20.497/24.285 | 0.902/1.478 | 0.614/0.863 |

Retain the tails: maximum STT text observation is 8.215 ms and maximum first E
audio is 7.169 ms in the third pending-credit trial. Replacement generation-end
maximum is 31.257 ms. These results do not establish a comparative regression,
speedup or capacity ceiling. The test ran on Elixir 1.19.5 / OTP 28 with eight
online schedulers, with unpaced native generation and immediate simulated sink
acceptance. No competing project BEAM diagnostic was run concurrently.

Astra reviewed the harness without a blocker for this bounded diagnostic. Only
active E cancellation is timed; completed T drain cancellation is checked for
correctness. Initial E first-audio timing includes validation and the PCM assertion;
replacement T first-audio is sampled before validation, so these are not identical
comparison boundaries.

Cancel-terminal timing is observed after the cancel API returns; generation-end
includes completed-event ACK; sink-acceptance end includes final audio-credit ACK.
The benchmark records these distinct boundaries in its JSON. The numeric playback
reports are accounting evidence, not audible/physical playback or a real sink clock.
Fixed mode order, no warmup, local providers and short repetitions limit timing
interpretation. Ordinary sink settlement, rooms and hosted providers remain separate
D/later-checkpoint gates.

Full distributions for all counts/repeats are retained in the
[load artifact](20260919-2245-tts-cancellation.json).


## Umbrella verification and retained failures

The initial root run on this repair used seed **520598**: **1,897 tests, two
failures, 40 excluded**. Engine passed all 799 cases. Gateway's two failures were
existing custom-URL-wait phone-transfer scenarios after destination loss: Telnyx
missed the failure observation within 2 seconds; Twilio missed recovery speech
within 2 seconds. No causal connection to the native speech repair was established.
These harnesses use the legacy test transports, which D has not migrated.

Both generated scenario groups then passed in isolation with the same seed:
**10 tests, zero failures, 16 excluded**, in 21.3 seconds. No timeout or source was
changed. The subsequent **full same-seed umbrella rerun passed: 1,897 tests, zero
failures, 40 excluded**. The initial failures remain part of this record; their cause
is not established by a passing rerun. Formatting, warnings-as-errors compilation,
strict Credo and the unused-dependency check also passed. No runtime source changed
between these runs. Counts by app: MCP 37, Agent Runtime 95, Call Engine 799, Calls
117, Gateway 460, Artifacts 20, Persistence 184 and Console 185.

The existing TTS handoff/failure diagnostic also passed on this source: **36 trials**,
**3,936 successful TTS and 3,936 STT turns**, plus **492 intentionally failed Output
allocations and explicit TTS replacements**, in 11.7 seconds. It retains the
previously documented direct/adopted startup and 0/2 ms simulated sink-acceptance
workload and limitations; see the [handoff report](20260920-0041-native-tts-deadline-findings.md).
Worst observed fault notification/teardown/replacement-ready times are
5.568/5.569/9.971 ms; the first two include observation after sibling STT finishes,
and replacement-ready includes that cleanup. These are observed upper bounds, not
a comparison against main or a recovery guarantee. Final process count is 245 in
every handoff trial. Current distributions are retained in the
[handoff artifact](20260919-2245-tts-handoff.json).
