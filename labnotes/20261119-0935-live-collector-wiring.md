# Live collector wiring

Previous checkpoint36d03d47 is pushed: acknowledged Scribe profile query/admission
and immutable storage schema, with clean Engine and Calls/Persistence Astra reviews.
This checkpoint is not implemented yet.

Current source evidence:
- Engine SourceAttachment accepts an injected collector callback and now supplies
  identity, source/run/clock IDs, canonical/provider generation, accepted profile,
  inference mode, settings revision and monotonic origin. It does not supply a
  UTC anchor yet. Add the UTC anchor beside the monotonic origin at context creation.
- Calls Diagnostics.Supervisor already defines bounded writer/collector/task pools,
  but Calls.Application starts only PublicationSupervisor; diagnostics supervision
  is not activated in the normal application tree.
- Engine Application starts only diagnostics settings projection when its runtime
  loader is configured. SourceSupervisor/SourceCoordinator production composition
  is not yet present.
- config/runtime.exs injects the persistence settings loader when the database is
  configured. It can likewise inject a Calls-owned collector callback without
  introducing an Engine-to-Calls compile-time dependency.
- Collector requires a validated immutable LatencyRun before its first write. The
  factory must translate the bounded acknowledged fields into the closed Calls
  profile, preserve inference provenance, and use the existing asynchronous writer.
  Source IDs must become opaque persistent IDs, never serialized BEAM references.

Proposed smallest next slice: a Calls-owned attachment factory, activated Calls
supervision, and an injected runtime callback plus Engine source pool. Start with
red tests for actual run creation from admitted source context, off/unknown settings,
unsupported profile rejection, capacity failure and delayed startup. Then configured
Scribe calls must demonstrate actual persisted turn revisions and finite shutdown.

Startup deadline issue under design review: DynamicSupervisor.start_child has no
finite public-call timeout. A blocked collector/writer supervisor must not hang the
source coordinator indefinitely or create an unclaimed collector after a timeout.
Candidate: bounded admission task, absolute startup deadline checked before and
after Collector writer initialization, and explicit retirement if handoff retrieval
fails. Evaluate a separate bounded admission Task.Supervisor to avoid competing
with persistence tasks; do not add an unbounded queue or synchronous storage IO.
No runtime/test implementation has been started for this slice. Astra design review
requested from review_live_collector; final recommendation still pending.

Initial factory red3/3 now passes3/0: exact immutable acknowledged profile and
source identity, capture return before persistence completes, unknown profile
rejection and settings/revision fencing. Observer profile metadata now comes from
ActivityBoundary and the pinned Silero model version rather than duplicated factory
constants. Source-context UTC-anchor regression failed15/1 before adding the anchor
beside its monotonic origin. This factory is not activated in application wiring.

Design review found that Task.Supervisor admission itself can block indefinitely,
and worker startup/cleanup outside the factory have the same issue. The next change
will bound the entire attachment, using a local owned helper and a shared startup
lease. Production composition should place Engine SourceSupervisor under Calls
Diagnostics.Supervisor alongside collector/writer/task pools: one common parent
then owns the admission gate and all destination queues, and child restarts cannot
reset unresolved debt. Engine still has no Calls dependency.

The lease must track unresolved nested supervisor operations. A Collector init
startup timeout can return while its writer-start request remains queued; merely
releasing a permit on outer completion is unsafe. Increment before dispatch,
decrement only after known completion, and release the common permit once the
attempt is finished and no operations remain. A killed process leaves its debt
reserved. Cancel before killing an expired helper; reject new operations on a
cancelled lease. SourceWorker and Collector must use the remaining absolute budget
for GenServer initialization and retire provisional/cancelled attempts. These
contracts and full runtime composition remain to implement and review.

Startup primitive implementation evidence:
- AttachmentLease reserves bounded common-pool admission, tracks unresolved nested
  operations and fences cancellation/adoption. Killed operation callers retain debt;
  finishing is idempotent and cannot admit new supervisor operations. Initial lease
  tests red3/3, then green; an additional adopted-lifetime contract is retained.
- SourceWorker now rejects cancelled handoffs, retires expired provisional workers
  and retains adopted workers beyond the startup deadline. Focused regression was
  red12/2 before implementation; worker/lease green16/0. Engine diagnostics144/0
  passed before the final remaining-budget start_link adjustment.
- Collector checks its startup lease before writer allocation, before returning a
  handoff and before consuming queued capture. Cancelled evidence cannot produce
  turn revisions; admitted writes still use the existing finite drain. Red6/3
  became green6/0. Suspending the writer supervisor reproduced unbounded startup
  (red7/1); remaining-budget GenServer initialization now times out and preserves
  the unresolved writer admission reservation. Zero-budget startup rejects before
  spawning a process. SourceWorker uses the same remaining-budget initialization.
- Calls factory passes the lease into Collector and accounts for collector admission.
  Cancelled factory regression red4/1; final Calls diagnostics40/0.
- Astra xhigh lease/worker review is clean: independent focused16/0 plus two
  deterministic concurrency probes for cancellation during adoption and multiple
  unresolved operations. Calls factory/collector review remains in progress.
- Root format, compile with warnings-as-errors, strict Credo and unused-lock checks
  pass. Lean and frozen root tests are running. No production pool activation yet;
  SourceCoordinator helper/adoption and common-parent gate wiring remain pending.

Calls review reproduced three concrete failures, now retained and fixed:
- Cancellation skipped packet release: queued packet stayed pending748bytes after
  collector exit. Retained red7/1; close the capture then consume/release the revoked
  packet through CaptureHandoff.message before finalizing.
- A factory call without a startup lease could time out retrieving a suspended
  collector handoff and leave that collector running indefinitely. The new factory
  now requires an AttachmentLease; this is a new API with no existing callers.
  Retained omitted-lease regression red5/1. Reviewer independently verified that an
  explicit lease retires the delayed collector after the failed factory call.
- Cancelling while Collector waits for Writer.handoff still emitted initial running
  persistence. Retained traced/suspended writer regression red6/1; recheck lease and
  capture after handoff, immediately before the first write.
Final Calls diagnostics42/0. The first root suite was deliberately stopped before
these fixes; it is incomplete evidence, not a passing gate. Final re-review and
static checks are in progress; root must be restarted on the fixed frozen tree.

Final Calls Astra xhigh re-review is clean:16 independent tests/probes, including
all three reproduced failure cases. Final root static checks pass. Lean passed on
the same Engine source before the Calls-only review fixes. Full root suite remains
required; production composition is the next implementation checkpoint.
