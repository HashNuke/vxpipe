# Settings acceptance contract research

## Scope and method

Read-only research for the remaining cross-node effective-status acceptance item
in `labnotes/milestones/passive-call-latency-diagnostics.md`. No implementation,
deployment, Mix/native/provider tests, credentials, environment contents, or
process arguments were accessed. The existing untracked effective-status note
was read and preserved. The use-railway skill was consulted for deployment
configuration inspection; no Railway operations were needed.

## Evidence

- Milestone settings contract requires disabling capture on every worker and
  pending status until revocation acknowledgements or lease expiry establish
  effective disable. Its checkpoint C item remains unchecked.
- `docs/design/latency-diagnostics-runtime-limits.md` explicitly rejects both
  connected-node discovery as complete membership and one API node's elapsed
  time as unconditional evidence that every worker lease expired. The earlier
  question about an operating clock-progress guarantee remains unanswered.
- `scripts/qa/compose.yaml` defines one named application container and sets
  `RELEASE_DISTRIBUTION: none`. `scripts/qa/vxpipe.service` runs that compose
  application. This is evidence of the QA topology, not an admission fence
  preventing another process or host from reading the same settings database.
- `docs/en/usage/install/railway.md` recommends starting with one application
  replica and says additional replicas require call/media routing. It does not
  define an authoritative capture-worker population or enforce singleton access.
- `apps/vxpipe_call_engine/lib/vxpipe/call_engine/application.ex` starts a local
  settings reader/projection supervisor; room registries are local registries.
  Targeted searches of application runtime code, config and QA scripts found no
  Node discovery, distributed membership, or capture-authority admission system.
- `config/runtime.exs` connects the projection loader to
  `Vxpipe.Persistence.DiagnosticsSettingsStore.snapshot/0`. The store reads the
  durable row directly; browser responses expose saved enabled/revision values,
  not worker acknowledgements. The console controller forwards those values.
- `SettingsLease` bounds authority to 3000 local monotonic milliseconds from
  the read start. `SettingsProjection` polls every 1000 milliseconds, discards
  late responses and supports direct local status/grant checks. These are useful
  fail-closed local contracts, not installation-wide observation.
- `DiagnosticsSettingsControl.tsx` truthfully displays collection status
  unavailable when the production API omits it. Only story fixtures currently
  synthesize applying/applied transitions.

## Smallest implementation proposal, pending scope decision

Keep the durable setting as the only enable authority. If useful, expose a
separate local observation with explicit scope, observed revision, and
enabled/disabled/unavailable state, sampled from the existing projection without
cross-node timestamps. For a saved disabled revision R, only an exact matching
local disabled observation may say this worker observed Off; mismatches and
unavailable projections cannot confirm the saved revision. UI wording must say
this worker, and installation-wide collection status must remain unavailable.
Enabling means permission, not readiness or complete coverage. No timer, cluster
discovery, new registry, or request-path database polling is necessary.

That scoped feature would be honest and small, but it does NOT satisfy the
current milestone's global effective-disable acceptance. Do not mark checkpoint
C complete or reinterpret its requirement without approval. Existing UI already
handles the safe unavailable fallback, so adding local status is optional rather
than a prerequisite for benchmarking.

To complete the unchanged global requirement, the remaining decision is either
an explicitly accepted operating clock-progress bound (followed by the already
documented fresh post-grace authoritative read protocol), or a complete enforced
capture-authority set and acknowledgements. The latter has no existing foundation
and would exceed the instruction against adding cluster membership for this
feature. A simpler approved milestone scope change can retain bounded local
leases and truthful unavailable installation status, explicitly deferring global
confirmation. QA's apparent singleton topology alone must not imply that approval.

## Verification and barriers

Source inspection only. Two searches included nonexistent directories
(`docs/en/deployment`, `apps/vxpipe_server/lib`); searches were corrected to the
actual install documentation and application files. No runtime topology proof or
global acknowledgement test was claimed. Existing peer tests use controlled
clocks and establish local expiry behavior, not a cross-host elapsed-time bound.
