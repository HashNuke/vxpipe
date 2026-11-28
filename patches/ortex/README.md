# Ortex CPU session threading and inference scheduling

The pinned Ortex revision creates ONNX sessions with the default intra-operator
thread pool. For the small streaming Silero model, three extra native workers
accounted for about 95% of sampled thread CPU in the isolated one-source probe.

`session-threads.patch` adds an optional fourth `intra_threads` argument to
`Ortex.load`, retaining zero/default behavior for existing arities. The private
`Ortex.Native.init/3` wrapper also retains its default behavior. The NIF decodes a
signed 32-bit integer and rejects negatives before converting to the Rust session
builder's unsigned parameter. Nonintegers and overflow fail at the NIF boundary.
Positive values call `with_intra_threads`; zero leaves upstream defaults intact.

Vxpipe's production Silero loader selects one thread, matching the
[Silero wrapper](https://github.com/snakers4/silero-vad/blob/v6.2/src/silero_vad/utils_vad.py).
With sequential graph execution this avoids an extra intra-op pool. It is not a
whole-VM thread cap: concurrent model invocations still execute on their calling
dirty schedulers. Model weights, recurrent state, admission and inference limits
are unchanged. This preserves the existing in-process native fault boundary.

`bin/patch-ortex` verifies the pinned revision, patch hash and original/patched
source hashes. Unknown or mixed states are preserved and rejected. Setup and CI
apply the patch before compiling Ortex; production release preparation must do the
same (see [QA services](../../scripts/qa/README.md)). Recompile the NIF after patching;
changing only the Elixir module leaves the old native arity and cannot work.

Validation includes pristine/repeated/mixed/modified-source patch preparation,
invalid native argument rejection, legacy arities, a fresh-VM Linux thread-count
regression, and the pinned Silero probability/chunk/reset tests. Remove this patch
when a pinned upstream revision provides the setting and passes these contracts.

## CPU inference entry

The patch also adds `Ortex.run_cpu/2`, used by production Silero with its CPU
execution provider. It shares tensor conversion, output unpacking and error
handling with `run/2`, and calls the same native model implementation on a dirty
CPU scheduler. Existing `run/2` keeps its dirty I/O scheduling for other callers;
initialization is unchanged. CPU execution is not interruptible or fault-isolated.

`cpu-scheduling-upgrade.patch` upgrades the exact previously reviewed thread-only
patch state. The installer checks both patch hashes before doing anything and
requires all five source files to match either the original, previous or current
manifest state. Unknown or mixed edits are rejected without modification. This
supports existing checkouts as well as fresh dependency downloads; rebuild Ortex
with `mix deps.compile ortex --include-children` after applying it.

Focused native tests prove Silero calls the CPU entry and avoids the legacy entry,
and compare both entries' output bytes. Installer tests also cover upgrade and
upgrade-checksum rejection. Scheduling selection does not establish performance
acceptance; measured paired workloads remain required.

The installer then applies `silero-batch.patch` to the verified CPU patch. Its
dirty-CPU entry accepts 1–16 PCM windows with per-stream little-endian float
state and runs the shared CPU session once. The batch manifest pins every
resulting source, including the added Rust module. The CallEngine batch wrapper
maps malformed rows and recoverable inference failures to a fixed reason.
