# Silero native CPU threading

Decision, 2026-11-20: production Silero sessions explicitly use one intra-operator
thread. Retain the existing room/source ownership, independent recurrent state,
shared diagnostic inference admission and supervised in-process execution.

## Evidence and cause

The first fixed warm configured workload used 34.17 process CPU-seconds with
fallback collection enabled versus 0.67 with it disabled over approximately 20
seconds, for one human input. This is preliminary evidence, not the full repeated
paired acceptance matrix. In a separate instrumented run, three threads created
at model load accounted for 31.91 of 33.69 sampled thread CPU-seconds (94.7%).
The calling dirty-I/O thread accounted for 0.56 seconds. Perf stack sampling was
unavailable under the host's existing policy; no global profiling policy changed.
Thus thread attribution is measured; spinning as the mechanism is an inference
from the runtime's configuration and documented behavior, not a sampled-stack proof.

The pinned Ortex binding creates a default ONNX session. ONNX documents that its
[intra-op pool may spin while waiting](https://onnxruntime.ai/docs/performance/tune-performance/threading.html).
The [Silero wrapper](https://github.com/snakers4/silero-vad/blob/v6.2/src/silero_vad/utils_vad.py)
uses one intra-op thread; its maintainer explains that this small model does not
benefit from a larger pool. The pinned Rust `ort` binding uses sequential graph
execution, so an inter-op setting is unnecessary here.

## Implementation and boundaries

The checksum-pinned [Ortex patch](../../patches/ortex/README.md) adds an optional
fourth thread argument while retaining existing load arities and defaults. Silero
passes one in its production model loader. The native boundary rejects invalid,
negative or overflowing thread counts before conversion. Setup, CI and release
preparation apply and compile the verified patch; unknown dependency edits fail
closed rather than being overwritten. The model file and checksum are unchanged.

One intra-op thread means the calling inference thread performs the computation
without additional pool workers. It does not cap total VM threads, serialize all
operational VAD calls or establish native fault isolation. Existing operational
concurrency and diagnostic admission remain unchanged. Model calls remain native
code in the BEAM process with the previously documented VM-wide failure risk.

## Alternatives and acceptance

- Leaving defaults retains the demonstrated worker CPU cost.
- Benchmark-only environment overrides would fail to measure production behavior
  and are rejected. This setting applies to every production Silero session.
- Embedding session configuration into model metadata would change the pinned
  artifact and introduce an environment-dependent loading contract; it is unnecessary.
- Replacing Ortex or introducing a separate inference service would add deployment
  and protocol scope before testing the existing runtime's supported thread control.
  External isolation remains an option if measured budgets or fault requirements
  require it; this change makes no fault-containment claim.

The fresh-VM Linux regression first failed with three newly created native workers
and now passes with none. Existing model probability references, PCM chunking and
reset behavior pass unchanged. Invalid argument and legacy loading checks pass.
Detailed artifacts and configured warm measurements are recorded in the
[checkpoint labnotes](../../labnotes/20261120-0008-diagnostics-native-cpu.md).

This is a declared production implementation revision before further paired
acceptance. Old measurements remain evidence for the old configuration. New paired
comparisons must use the same patched production configuration in both phases,
retain CPU cgroup enforcement and the existing budgets, and still prove coverage,
latency, cold startup and the full supported topology matrix before pilot activation.

## Immutable tensor preparation

The [tensor-reuse checkpoint](../../labnotes/20261120-0030-diagnostics-tensor-reuse.md)
caches the native signed-64 16 kHz scalar in the model while leaving all recurrent
state per stream. PCM normalization now constructs the same float32 bytes directly.
This removes a repeated native upload; it does not change scheduler policy or
establish a CPU-budget pass. The configured run retains the outstanding CPU cost.

## CPU inference scheduling

The production CPU-only Silero path now explicitly calls `Ortex.run_cpu/2`.
[OTP's NIF scheduling guidance](https://www.erlang.org/docs/26/man/erl_nif.html)
classifies CPU-bound dirty work as dirty CPU work. The upstream inference entry
used DirtyIo; the explicit CPU entry corrects that classification without changing
other callers' scheduling. Both entries call the same model implementation and
share tensor/result/error conversion. Model initialization remains DirtyIo.

This preserves source ownership, operational concurrency, diagnostic admission,
model outputs and the in-process fault boundary. It does not make native execution
interruptible. No VM scheduler flags or benchmark budgets change. Changing every
Ortex caller globally was rejected because other execution providers may wait on
external devices. The checksum-verified upgrade preserves previously patched
checkouts and rejects unknown edits.

The focused native contract checks positive CPU-entry invocation, no legacy-entry
invocation and byte-identical outputs. Existing reference probabilities, chunking
and reset checks pass. See the [scheduling checkpoint](../../labnotes/20261120-0037-diagnostics-cpu-scheduling.md)
for measurements; full paired and topology acceptance remains open.
