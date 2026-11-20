# Ortex CPU session threading

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
