# Replan speech ownership

Date: 2026-09-19. Scope: documentation-only replan requested after the user rejected
application-wide speech execution coupling. Created with `bin/create-labnotes`.
Implementation remains paused. No runtime changes, rollback or commit in this replan.
The preceding prototype, isolated tests and benchmark remain uncommitted in the worktree.

## Starting evidence

- The isolated held-start test reproduced unrelated `Session.start` calls taking
  301–302 ms against 100 ms budgets. Queue wait was excluded from the prototype deadline.
  The original room-scoped STT and connection-task controls passed. This identifies startup
  admission coupling in the prototype; it does not establish a live-call drop or app crash.
- The preceding benchmark completed 68,400 measured local Morse turns with zero failures,
  including 19,200 already-ready semantic turns during held startup. Its burst timings and
  limits remain recorded in [the evidence document](../docs/speech-startup-isolation.md) and
  [canonical metrics](20260919-1624-speech-latency-metrics.json). This replan did not rerun or
  alter those measurements.
- Existing rooms still use the old provider/transport path. Restoring a running room therefore
  does not require reverting the isolated prototype. The first proposed checkpoint replaces
  its global wiring while preserving useful native codec tests and evidence.

## Source findings and decisions

Inspected the application tree, `RoomIncarnationSupervisor`, `RoomCapabilitySupervisor`,
`ParticipantSupervisor`, STT transport connector, policy preparation, runtime identities and
opening text preparation. Current speech capabilities are room capability children; participant
supervision also owns activation work. Opening generation already has a room incarnation.
Existing global speech connection/output task supervisors still serve the old paths.

The revised [ownership proposal](../docs/speech-session-ownership.md) keeps speech beneath
the room capability tree, with separate temporary trees per connection or participant/purpose.
Every shared ancestor admits lightweight children only. Blocking provider work executes
asynchronously inside its allocation. Standalone use requires an explicit local scope.
Moving a blocking provider-start queue to room scope was rejected because same-room siblings
would still couple. Wholesale participant-tree migration was deferred because it expands
scope and does not fit every opening/preparation lifetime.

Lifetime owner, event consumer and preparation/adoption authority are separate. Prepared
allocations begin under their final room parent; adoption changes authority, not OTP parentage.
Generation/purpose-specific handles distinguish allocation close from capability-tree stop.
Migration must update speech lookup, stop, readiness and monitors together; generic direct-child
stop remains valid for non-speech capabilities.

Use persistent local audio workers by default while preserving bounded admission, responsive
cancel/close and accepted-versus-submitted usage. No new application-wide speech executor is
allowed. Legacy task supervisors remain only until their existing callers migrate, then are
removed. The public provider interface remains four STT operations and five TTS operations.

## Checkpoints and design review

Revised order: **R → A → D → B → C → E → F → G → H**. R repairs and proves ownership/admission;
A and D prove native STT and TTS before room migration; B/C migrate STT; E/F migrate TTS;
G establishes conformance and authoring; H removes legacy contracts and verifies all consumers.
Existing A–H identities are retained. Zero of nine checkpoints are accepted. Only previously
completed A1/A3 partial prototype work remains checked; the milestone index remains unchecked.

GPT-6 Astra xhigh reviewed topology, ownership and dependency order separately from runtime
acceptance. Review required cheap shared-ancestor starts, queued cancellation, exact teardown,
owner/lease/consumer separation, no reparenting and coordinated nested-capability migration.
The final review clarified three contracts:

- Allocation-local failure retires that allocation; failed preparation preserves active STT.
  Shared capability-control/session-supervisor loss retires the whole capability tree, with
  unrelated trees remaining usable.
- Startup/adoption deadlines settle at activation. Later operations have independent bounded
  API-entry deadlines; startup timeout is not the active session or accepted TTS request TTL.
- Asynchronous private-init data remains owned until handoff, cancellation or expiry; returning
  `:starting` must not delete it. Retained tree/status/crash information stays redacted.

These corrections are reflected in the ownership proposal, semantic contract and R tasks.
The reviewer rechecked the written clauses and order and reported no remaining design blocker.
That finding approves design consistency only; the original startup regression is unresolved.

## Verification

`git diff --check` passed. A local Markdown check verified 159 relative link targets across
seven changed documents and confirmed matching checkpoint section/table/ledger order,
zero-of-nine acceptance, the original A1/A3 partial checks and the unchecked milestone index.
Reviewed status and relevant diffs; existing runtime/test/prototype files were preserved.
No runtime tests were rerun for this documentation-only turn. Runtime acceptance is not
claimed, and implementation remains paused pending the revised plan.

The proposed gates require separate-room and same-room live PCM progress,
queued expiry/cancellation, exact failure boundaries, stale-stop protection and private-init
cleanup. Later gates add STT/TTS cross-direction isolation, blocked-sink cancellation, paced
and burst latency comparisons, and actual room/browser/hosted verification.
