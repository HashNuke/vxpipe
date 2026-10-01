# Local speech activity runtime

## Purpose and decision

Implement actual local CPU speech classification and confirmed acoustic boundaries
for the remaining ElevenLabs realtime STT integration. The previously pinned
model/runtime experiment supplies reproducible inputs. Keep recognition segments
and acoustic turn ownership separate. This checkpoint does not register STT,
change shared STS contracts or run another paid provider call.

Select the pinned Silero v6.2.3 model and Ortex revision already verified in the
isolated native experiment, with Nx 0.11.0. CallEngine owns both direct uses and
the corresponding lockfile changes. Package the unmodified model with its MIT
notice; verify its digest at load and use the application priv directory. No
runtime download, Python subprocess or provider credential is involved.

## Red-green checkpoints

The first boundary test fails because ActivityBoundary is absent: one expected
failure, seed 801917. Implement classified-frame onset/silence confirmation; one
check passes, seed 178228. Additional reset/invalid-classification and native
stream tests first fail in five checks with three expected failures, seed 126668.
Implement fixed hysteresis, reset, PCM normalization/context/recurrent assembly,
model packaging and pinned dependencies; five checks pass, seed 964693.

The first runtime test fails because ActivityRuntime is absent, seed 871396.
Extend the failing contracts before implementation: four expected failures,
seed 707561. Implement lazy loading, bounded job admission, caller monitors,
cancellation, safe deadlines/errors and status redaction. Nine combined checks
pass, seed 340210. The allocation supervisor failure test first fails in seven
checks with one expected failure, seed 459661; add the local one_for_all tree.
Seventeen combined application/model/runtime checks pass, seed 557981.

## Ownership correction before acceptance

Initial implementation put private inference workers in an application-wide
pool. Reviewing the speech contract identifies that mismatch: private execution
belongs beneath each allocation. Stop that initial root test run deliberately;
its partial results are not acceptance evidence. The umbrella changes cwd while
running child suites, so a process lookup restricted to the root initially finds
no process; matching its umbrella child cwd identifies the single active test.
Only that test process is terminated, and its handle confirms terminal state.

Write a failing application ownership check before changing composition. It
fails because a global ActivityRuntime is present: five checks, one expected
failure, seed 633724. Replace the global pool with a lazy cache for only the
public model resource. Require explicit names for allocation inference trees;
use one job slot by default. No private PCM or recurrent state enters the cache.
Twenty-one checks pass, seed 586553. Add independent-allocation failure proof;
twenty-two checks pass, seed 853209.

## Final focused evidence

Twenty-three checks pass, seed 865692, including the existing application checks:

- Native probabilities match 130 stored official-wrapper float32 reference values
  within 1e-6 on the committed public fixture. Irregular chunk boundaries and a
  reset reproduce the same results. Fifty-two frames exceed the onset threshold.
- The supervised allocation helper classifies actual accepted PCM and supplies
  one confirmed acoustic onset/end on that fixture.
- Incomplete frames are retained without padding or acoustic sample advancement;
  invalid aligned-input sizes fail without accepting more data.
- Silence, a 440 Hz tone and deterministic seeded noise are bounded negative
  controls. This is not general acoustic quality or noise-robustness evidence.
- Four consecutive 32 ms frames at >= 0.5 confirm onset; sixteen below 0.35
  confirm endpoint. Intermediate/resumed voice clears pending silence. Sample
  positions identify the start of the confirmed interval; no timer supplies
  missing acoustic evidence.
- Admission rejects busy input without acceptance. One active job per caller,
  fixed deadlines, safe loader/inference failures and redacted diagnostics pass.
- Cancellation retains the job slot until terminal task evidence. Caller loss
  retires its work. Another caller cannot cancel it. Runtime failure retires its
  own supervised workers while an independent allocation's work completes.

Only Linux x86-64 native build/inference is verified here. Rust dependency
compilation emits upstream lifetime warnings; project Elixir compilation with
warnings-as-errors passes. Native calls are not guaranteed to stop immediately
when an Elixir process is killed. The runtime retains cancellation capacity until
actual settlement, rather than claiming a hard native interruption guarantee.

## Required gates and next work

After the ownership correction, format and warnings-as-errors compilation pass.
Strict Credo passes on 1,174 source files and the unused-dependency check passes.
The corrected existing Lean model/replay lane passes one test, seed 146596; this
does not add a formal model of the private acoustic classifier. The corrected
default umbrella run completes: 2,997 tests, zero failures, 92 exclusions, seed
936184, including all 1,790 CallEngine and 522 Gateway tests. Its process handle
returns exit zero. All five required root gates pass. No UI or scoped service metadata is
changed, so no new browser acceptance is claimed. Preserve the unrelated user
content configuration change.

Next, start the helper within the actual Scribe allocation, execute ordered
recognition actions, correlate pending caller turns, bound retained input and
commit deadlines, and reset all private state at permission/allocation changes.
Review explicit local acoustic provenance in STT admission and its consumers;
shared STS authority remains unchanged. Then prove scoped publication/startup,
room behavior, Console capability metadata and one bounded selected live case.
Reference project names and implementation methods remain outside repository docs.
