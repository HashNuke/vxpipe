# Acoustic native replay

Prepared a focused Engine integration contract in
`test/integration/acoustic_acceptance_test.exs`. It generates the frozen controlled
corpus, verifies PCM hashes, and requires actual production fallback and
operational-reuse paths with complete progress and preserved raw packets.
The helper is deliberately not implemented yet: red execution awaits the shared
Mix/native lane. No detector has run on these frozen sources.

Approved bounded design: fallback uses native SourceSupervisor/SourceAdmission/
SourceWorker. Reuse starts production ConversationalSTT with the existing local
SpeechOnsetProbe recognizer, attaches production DiagnosticSubscription to a
reuse SourceWorker, and forwards timestamped frames. No provider socket exists.
Await each frame's acoustic progress before feeding the next frame. This pacing
is offline acoustic accuracy evidence, not load/performance or live coverage.
Do not identify the same AcousticReplay invocation as two separate modes.

Root review led to two red-green Python corrections before any native execution:
frozen reference digest enforcement and chronological internal pause/resume
matching. Their detailed evidence is in the acoustic-sample-provenance labnote.

Native red executed after lane grant: expected helper-not-implemented failure.
After helper implementation, two trial executions timed out awaiting first-frame
progress; neither yielded a valid result. Harness used rounded real receipt times
relative to a microsecond origin, which can make the first offset negative; rapid
offline input also violates contiguous receipt-clock assumptions. Switched to an
explicit synthetic contiguous receipt clock for sample-accuracy replay only.
Native retry awaits lane return from egress's short focused correction.

Root caught a coverage-report weakness before accepting results: requested length
was being called completed length. Each consumed progress packet now fences the
worker and asserts actual ActivityBoundary.samples against the frame target; reuse
also fences operational stream.samples, fallback checks its native stream.samples.
Final report uses observed boundary samples and capture pending/overflow/discarded/
invalid counters, requiring zero drops. JSON nil is preserved as null. Hysteresis
finalized-sample progress is not incorrectly required to equal inference samples.

## Final bounded native result

The synthetic receipt-clock correction passed all 24 case/mode combinations.
Final targeted command from `apps/vxpipe_call_engine`:

```sh
VXPIPE_ACOUSTIC_REPORT=/tmp/vxpipe-acoustic-native-results.json mix test --only acoustic_accuracy test/integration/acoustic_acceptance_test.exs
```

Final run: **1 test, 0 failures, 2.6 seconds**, seed 34437. All 12 conditions
were exercised in each distinct production acoustic path. Every 512-sample frame
was acknowledged and fenced against actual consumed boundary/native-stream sample
counts; each input capture ended with zero pending, overflow, discarded or invalid
counts. No source resets. No actual provider calls, browser media, load test, or
wall-clock latency claims. Synthetic contiguous receipt time exists only to retain
valid sample-to-clock mapping while replaying faster than real time.

Artifacts:

- [Raw native traces](20261120-0232-acoustic-native-replay.json), SHA-256
  `f9811f61a010cf348c68697958b88eb3190ed4727bbcc205998e12d038a5d555`.
- [Scored traces](20261120-0232-acoustic-native-replay-scores.json), SHA-256
  `931e1bb8aa4eba08a4505a1fb106756255f0a41d38f00209f7f2694b07fac3b2`.
- Frozen reference SHA-256
  `a2d9d0137dca2972bc99769f43407aac1a1027e91e36da2db97248c9c31f4bf6`.
- Model `silero_v6.2.3`, SHA-256
  `1a153a22f4509e292a94e67d6f9b85e8deb25b4988682b7e174c65279d8788e3`.
- Source revision `adab603c46934ffa3209e88cd598b31ae3620551` plus actual working-tree
  hashes in raw `provenance.file_sha256`: helper, test, evaluator, SourceWorker,
  InferenceTap, ConversationalSTT, ActivityBoundary and Silero. The helper/test were
  uncommitted; source revision alone is not claimed to reproduce their contents.

### Errors by mode and controlled condition

Every row below was independently executed in **benchmark_only** and
**operational_reuse**. Both modes produced identical raw sample boundaries and
therefore the same intervals; their separate records remain in the artifacts.
Each cell is a possible signed error range in milliseconds, detector minus visual
reference; negative means early. These are uncertainty ranges, not confidence
intervals or midpoint estimates.

| Caller / controlled condition | Onset error ms | Outer end error ms | Absolute end error ms | Missing outer boundaries, each mode |
| --- | --- | --- | --- | --- |
| female / clean | [-13, 7] | [42, 232] | [42, 232] | 0/1 |
| female / quiet tail | [-13, 7] | [-246, -56] | [56, 246] | 0/1 |
| female / noise | [-13, 7] | [10, 200] | [10, 200] | 0/1 |
| female / echo | [-13, 7] | [74, 264] | [74, 264] | 0/1 |
| female / overlap | [51, 71] | [170, 360] | [170, 360] | 0/1 |
| female / pause-resume | [-13, 7] | [26, 216] | [26, 216] | 0/1 |
| male / clean | [67, 77] | [32, 112] | [32, 112] | 0/1 |
| male / quiet tail | [67, 77] | [-64, 16] | [0, 64] | 0/1 |
| male / noise | [35, 45] | [32, 112] | [32, 112] | 0/1 |
| male / echo | [67, 77] | [64, 144] | [64, 144] | 0/1 |
| male / overlap | [67, 77] | [32, 112] | [32, 112] | 0/1 |
| male / pause-resume | [67, 77] | [36, 116] | [36, 116] | 0/1 |

Onset absolute errors are [0,13] ms for [-13,7] ms, otherwise the listed positive
signed ranges. Per mode, missing outer-boundary cases: **0/12**. This is a small
case-level descriptive rate, not a universal expected miss rate.

Pause-resume first-end errors: female [42,232] ms and male [32,112] ms. Resumed
onset errors: female [3,23] ms and male [7,17] ms. All four mode/caller pause-resume
pairs are chronologically unique; no missing or ambiguous pair in this pilot.
Every pause-resume case produced two segments; other cases produced one. There
were no wholly-before/after-reference detections. These observations are not a
claim of phoneme/turn segmentation correctness.

The early quiet-tail and late overlap estimates are material observed limitations,
not failures to conceal or evidence for a universal 32 ms accuracy guarantee.
The reference is independently visually reviewed narrowband read speech with
explicit uncertainty, not human-listening-labelled natural conversations. Provider
STT end and actual agent-stop delays are separate measurements, not generated by
this offline acoustic replay. Independent GPT-6 Astra xhigh review is clean: its
own 24-case replay passed and matched every recorded trace and score. This closes
the bounded labelled-replay quantification gate, not live/browser acceptance.

The reported 0/12 incomplete cases per mode means missing outer sample boundaries
only. First segments retain the production `partial_start` flags in raw packets;
these results do not establish complete production diagnostic reports.

### Reproduce score derivation

No new model run or labels are involved in scoring. From repository root:

```python
import hashlib, json, sys
from pathlib import Path
sys.path.insert(0, 'scripts/diagnostics')
from acoustic_acceptance import evaluate
path = Path('labnotes/20261120-0232-acoustic-native-replay.json')
raw = path.read_bytes()
data = json.loads(raw)
cases = {case['id']: case for case in data['manifest']['cases']}
rows = []
for trace in data['traces']:
    case = cases[trace['case_id']]
    rows.append({'mode': trace['mode'], 'case': trace['case_id'],
                 'score': evaluate(case['reference'], trace['segments'], case['sample_rate'])})
result = {'native_artifact_sha256': hashlib.sha256(raw).hexdigest(),
          'reference_sha256': data['reference_sha256'], 'scope': data['scope'], 'rows': rows}
Path('/tmp/recomputed-acoustic-scores.json').write_text(json.dumps(result, indent=2) + '\n')
```
