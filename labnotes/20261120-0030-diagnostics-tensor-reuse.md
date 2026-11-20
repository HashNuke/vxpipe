# Diagnostics tensor reuse

## Scope and evidence

The warmed Silero path recreated and uploaded the same 16 kHz scalar for every
frame. A focused native-boundary counter measured 64 uploads for 32 changing PCM
frames, after initial recurrent-state setup. The test requires at most one changing
input upload per warmed frame and failed on the previous implementation
(`vxpipe-silero-tensor-reuse-red.log`). Artifact names refer to the host temporary
directory.

Cache the immutable signed-64 sample-rate tensor in the loaded model, already on
the Ortex backend. Recurrent state and context remain in each participant stream.
The pinned binding clones the signed-64 array when constructing a session input;
it does not mutate the shared constant. Model inspection remains redacted. Model
weights, one-thread session configuration, source admission and failure handling
are unchanged.

The PCM conversion also constructs a native-endian float32 binary directly rather
than a boxed float list. Signed little-endian decoding and normalization by 32768
remain identical; reshape preserves the 1×512 frame input. The exhaustive comparison
in `vxpipe-silero-pcm-equivalence.log` confirms identical bytes for all 65,536 int16
values. This is a mechanical representation change, not a new acoustic algorithm.

## Verification and remaining cost

- `vxpipe-silero-tensor-reuse-green.log`: 4/4 native checks pass, covering upload
  count, no native worker pool, invalid binding arguments and legacy arities.
- `vxpipe-silero-tensor-reference-green.log`: existing Silero probability reference,
  PCM chunking/reset, input validation, silence/noise and supervised inference checks
  pass 4/4. Both runs use isolated bounded test VMs.
- Review identified a provenance omission: the runner hashed the model loader but
  not the changed `silero.ex` callsite. `vxpipe-tensor-provenance-red.log` reproduces
  that missing path. The runner now includes it before generating native evidence.
- `vxpipe-tensor-reuse-warm-fallback-on` passes the configured warm workload with ten
  measured completed turns, 625 measured frames, 201 resource samples, correct
  durable rows and clean owned-unit/database teardown. Actual measured duration is
  19.999310 seconds, process CPU 3.26 seconds / 0.163006 cores, maximum threads 11,
  interval HWM 272700 KiB and measured PCM p95 246570 ns.

The allocation reduction is proven, but this single run does not demonstrate an
overall CPU improvement over the previous 3.02-second enabled run. Do not relabel
that result as a performance pass. Full paired repetitions, coverage, latency and
cold acceptance remain open, and the CPU budget is unchanged. The preceding
profile identified scheduler waiting as a larger remaining contributor; investigate
CPU inference scheduling before further allocation tuning.

Root format, warnings-as-errors compilation, strict Credo and unused-lock checks
pass (`vxpipe-tensor-reuse-format.log`, `vxpipe-tensor-reuse-compile.log`,
`vxpipe-tensor-reuse-credo.log`, `vxpipe-tensor-reuse-deps.log`). Diagnostic Python
checks pass 53/53 (`vxpipe-tensor-reuse-python.log`). No source-cutover or speech
state-machine transition changed; no new Lean run is claimed.

Final GPT-6 Astra xhigh review is clean. It verifies immutable ownership, scalar
type, PCM equivalence, the corrected provenance path, all 19 recorded hashes and
raw native resource/pacing/cleanup evidence. It confirms the documentation does
not claim overall CPU improvement or budget acceptance.

No full suite, live provider/Telnyx calls, production restart or pilot enablement
is part of this checkpoint. All remaining milestone gates stay open.
