# Tool worker monitor acknowledgement

The full engine verification for listener changes exposed an existing fixture
race in `Tool.InvocationSupervisorTest`. The worker completed successfully, but
the test observed `:DOWN` with `:noproc` instead of `:normal`. The test monitored
the invocation and immediately released its execution, which is a separate
process; it did not confirm that the invocation had handled the monitor signal.

After installing the monitor, a `:sys.get_state/1` acknowledgement from the worker
now precedes releasing its execution. This changes only test synchronization;
the capacity, result and normal-exit assertions are retained. The seven focused
owning checks pass. The umbrella run that exposed the failure had 653 engine
tests and one failure, using seed 235296, concurrency four and module preloading.
Final root verification will be recorded with the accompanying listener
checkpoint before this fixture correction is committed separately.

The final root run's engine lane passes all 653 tests with one integration
exclusion. Module preloading, seed 235296 and concurrency four are unchanged
from the run that exposed this fixture failure. The complete umbrella finishes
with 1,435 tests, one separate human-only WebRTC audio failure and 16 exclusions.
Formatting, compilation, strict Credo and unused-dependency checks pass. Keep the
full root test gate open; this commit is the verified fixture correction, not
full milestone acceptance. The listener labnote records the separate native
failure and its focused rechecks.
