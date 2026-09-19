# Scoped speech ownership

## Starting checkpoint

- User requested a commit of all existing work before continuing. Commits
  `4cfaa52` and `343829c` record the plan, prototypes and experiment evidence;
  the worktree was clean afterward. Neither accepts an implementation checkpoint.
- Goal resumed at checkpoint R. Existing rooms still use the original providers.
- Baseline focused speech suite: 32 tests, one known startup-isolation failure.
  Eight healthy Morse starts waited behind a held prototype initializer; none
  completed within the observation window. Static root gates passed; full test
  acceptance remains pending the repair.

## Design checks in progress

- The existing global queue must be removed, including the implicit standalone
  fallback. Shared ancestors may only start lightweight local trees.
- Cancellation needs an attempt token before queueing; timing out a call alone
  cannot prevent delayed work from starting.
- Async initialization must retain private options in scope-owned storage until
  claim, cancellation or expiry. Supervisor arguments retain opaque handles only.
- Readiness, initialized provider startup and lease adoption are distinct; settle
  the original deadline only once the required readiness/adoption conditions hold.
- GPT-6 Astra xhigh is reviewing the minimal topology and cancellation/failure
  boundaries independently. No new acceptance gates have passed yet.

## Initial implementation and verification

- Added explicit scope/allocation handles, temporary capability/allocation trees,
  two-slot local admission, scope-owned private initialization, and an allocation
  name gate that registers the provider before its GenServer init. Removed the
  prototype application-wide speech registry and session supervisor.
- Initial lifecycle tests were written and run before implementation: five tests
  failed because `Speech.CapabilityTree` did not exist. After implementation, the
  same five tests passed: exact-generation close, queued cancellation/expiry,
  allocation failure isolation, and capability failure isolation.
- Extended lifecycle tests: eight tests, seven passed and one failed. The passing
  additions check a trapping initializer before bind and use beyond the settled
  startup deadline. This is partial evidence only; old prototype consumers/tests
  and benchmark have not yet been adapted to the explicit scope API, the original
  isolation test has not been rerun, and root acceptance has not been run.

## Tested stop: former lease closes an adopted allocation

The preparation lease and lifetime owner are separate Agent processes; the test
process becomes the new event consumer. Native Morse initializes, the lease gets
prepared readiness, adoption succeeds without changing the supervised parent,
and the new consumer acknowledges its ready event. The old lease then calls close.

Reproduce from `apps/vxpipe_call_engine`:

```shell
mix test test/vxpipe/call_engine/speech/scope_lifecycle_test.exs:10 --seed 42
```

The test compares old-lease close, new-consumer input and monitored tree state:

```elixir
# Required
{{:error, :not_owner}, :ok, :no_termination_observed}
# Observed
{:ok, {:error, :closed}, :terminated}
```

The isolated rerun reproduced this failure (one test, one failure, seven excluded).
This proves a lifetime failure in the new implementation: stale preparation
authority can terminate speech after adoption. It does not prove the existing
production room path is unstable, and no room consumer has migrated.

Cause: `Channel` changes its event consumer on adoption, but `ScopeControl.close`
continues authorizing the immutable handle's original lease/consumer fields.
Its settlement notification currently only cancels the startup timer. The two
control states do not transfer teardown authority together.

Proposed correction after resumption: make adoption atomically settle live
owner/consumer/lease authority in scope control under the original deadline;
retire the preparation lease's close authority and monitor, preserve lifetime
ownership, and use current authority for close and failure notifications. Keep
the exact-generation handle and supervised parent unchanged. Test old-lease
close/death, new-consumer close/death and deadline races before acceptance.

Paused under the user's explicit conditional instruction to report and stop on
tested instability. No fix or further migration is performed after this proof.
The failing R work remains uncommitted for inspection. `343829c` is the committed
pre-R baseline; no reset, revert, amend or other history change was performed.

Independent GPT-6 Astra xhigh review confirmed the causal code path by inspection
after the failing test. It also identified the corresponding authority gaps:
the adopted consumer is not authorized to close, and active failure notifications
still target the former lease. One authoritative lifecycle entry must govern all
three operations. The reviewer did not independently rerun the test.

## Subsequent authorized repair

The user subsequently authorized fixing this defect and required load testing.
The [repair labnote](20260919-1858-adoption-authority-fix.md) records the fix,
red/green evidence, independent review and load results. The stop above is retained
as historical evidence; the bounded authority repair now passes its focused checks.
