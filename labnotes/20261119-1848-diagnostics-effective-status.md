# Diagnostics effective status

## Open deployment assumption

The current API returns only the durable enabled value/revision. The UI supports
applying/applied/unavailable and finite polling, but only story fixtures produce
applied status. The approved runtime-limits design rejects turning one API node's
elapsed time into an unconditional global lease-expiry proof. No existing complete
capture-authority/worker membership registry was found; the milestone explicitly
forbids adding a new cluster-membership system solely for this migration.

The current Erlang time documentation confirms monotonic clocks can stop during
host suspension: https://www.erlang.org/docs/26/apps/erts/time_correction.html.
An asynchronous user question asks whether supported worker deployments may
require awake hosts and elapsed clocks within 1% of real time. An answer is
required before implementing a proof dependent on that operating guarantee.
Independent Astra design review confirms unknown/applying is safe interim
reporting, but does not complete the milestone's effective-disable acceptance.

If that bound is approved, the tracker grace must cover both fast tracker and slow
worker: 3000 ms × 1.01 / 0.99, rounded upward with timestamp-resolution margin.
Confirmation also requires a fresh primary-store read started after the grace,
matching the exact disabled revision. Errors, conflicting revisions and restart
invalidate the proof. No proof/runtime/UI change has been made on this assumption.
Independent missing-model failure acceptance proceeds while the question remains
pending. Existing story-only applied behavior is not production evidence.
