# Passive latency milestone planning

## Scope and decisions

- User requested research and a milestone before implementation, then explicitly
  added default hiding of seven noisy call-details/debug-view event types.
- Preserved the prior untracked research document and labnotes; updated the design
  with durable-record/UI contracts and the corrected provider endpoint semantics.
- Created `labnotes/milestones/passive-call-latency-diagnostics.md`: six runnable
  checkpoints, 34 unchecked tasks. Timeline cleanup is first and independently
  useful; persistence/replay precedes passive live capture and UI integration.
- Updated index totals to 68 active, 53 complete and 15 incomplete, inserting
  before pending voice features without renaming existing milestone identities.
- Followed impeccable planning guidance for the existing Operate surface. The
  accepted user scope already settles the audience, purpose and collapsed UI;
  no extra discovery questions or visual-system changes were needed.

## Research and review evidence

- Read completed archive, inspection, usage, publication and optional-VAD
  prerequisites and pending voice-feature contracts. Reviewed shared React filters,
  Console presenter, Calls inspection ports, archive handoff, audio receipt fields,
  Scribe continuous settlement and existing passive-benchmark research sources.
- Found a material correction: continuous Scribe accumulates committed segments
  and settles on an empty provider partial only after committed text with no draft.
  Provider text commit and actual end-evidence receipt require separate landmarks.
- Local review caught missing run-level coverage, clock-origin identity, late
  revision/deletion rules, separate queue capacity, legacy snapshots, filter paging,
  production authorization, export-completeness independence and native-fault limits;
  added them to the specification. No independent-agent review claimed.
- Existing shared Events defaults on; Logs refers to RTVI. Planned typed Technical
  events classification instead of dropping archive facts or changing logger levels.
- Tables, report and UI remain planned. First live support is scoped to Scribe v2
  over WebRTC/Telnyx; unsupported providers are explicit, not inferred compatible.

## Verification

- Checked local relative links in the milestone and updated design, trailing
  whitespace, terminal newlines and index order/counts. All 68 entries are ordered;
  completed count remains 53. All 34 new implementation tasks remain unchecked.
- `git diff --check` passes. Reviewed index diff and final worktree paths.
- Documentation-only: no setup, runtime suites, browser inspection, provider calls,
  database mutation, deployment or commit performed. Browser/live/root checks are
  explicit implementation gates, not evidence claimed by this planning work.

## App-settings clarification

- User requires benchmarking only while enabled in app settings, with admin and
  superadmin as the only toggle authorities. Replaced the host-option/allowlist
  proposal in the milestone; added durable boolean/revision, audited updates,
  dedicated server authorization, settings UI and propagation/revocation tasks.
- Reviewed existing InstallationSettings authorization and Console page/route:
  those currently protect installation URL with superadmin-only access. The new
  diagnostics operation must not broaden that unrelated permission.
- Added active/new-call enable, disable, partial-start, re-enable, stale-cache and
  unknown-setting tests. Capture stops on disable; only already captured summaries
  may drain. Historical reports remain available under existing inspection rights.
- Planning-only refinement; no runtime changes or commits. Local link, whitespace
  and unchecked-task checks repeated after updating the milestone and design.

## Installation placement and inference reuse

- User specified Installation page, Diagnostics section, exact label Benchmark
  using Silero VAD; updated milestone/design and section-level authorization.
- Inspected ConversationalSTT probability processing, epoch resets and discarded
  acoustic ends, plus historical ScribeInput classification. Reuse computed
  timestamped probabilities without changing control/reset behavior; missing
  endpoint coverage remains incomplete. No duplicate inference to fill gaps.
- Added operational-reuse versus standalone provenance and tests for one model
  execution per source frame, the full setting/call-spec VAD matrix, source
  transitions and disabling diagnostics without stopping operational VAD.
- Documentation-only; no application settings or runtime behavior changed.
