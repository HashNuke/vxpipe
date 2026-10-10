# Refresh speech milestone

2026-09-19. Documentation-only refresh requested while the implementation goal remains
paused. Created with `bin/create-labnotes refresh-speech-milestone`. No runtime changes,
new load tests, checkpoint acceptance, goal resume, rollback or commit are authorized by this
status/planning request. All earlier uncommitted work is preserved.

## Findings and updates

The milestone already contained the ownership replan, small implementation tasks, prerequisites,
file mappings, runnable outcomes and exit gates in order R → A → D → B → C → E → F → G → H.
Its top-level status remained zero of nine checkpoints complete. It linked the newer experiment,
but its task/evidence sections did not yet explicitly incorporate the subsequent discussion of
latency, capacity, fault handling and OTP-replaceable cleanup code.

Updated `labnotes/milestones/simpler-speech-integrations.md` and its index entry:

- Clarified that the reproduced global-startup defect belongs to the first uncommitted
  prototype; corresponding original-path controls passed. Existing production rooms are
  unchanged. The test-only bridge experiment does not establish final room parentage.
- Recorded the 12,996 measured ordinary turns, 12 loaded control scenarios and 11 focused
  tests separately from implementation progress. Preserved mixed latency results and the
  nonrepeating output tail; no performance equivalence or capacity limit is claimed.
- Required agreed latency budgets before room-input migration and retained native TTS proof
  before that migration. Capacity claims conditionally require a sustained paced ramp and
  resource measurements; a new production-capacity certification is not silently required.
- R distinguishes cleanup/unavailability timing from explicit replacement readiness and
  tests allocation versus shared-capability failure. B/E repeat these checks in real rooms.
  No automatic reconnect, fallback or replay was added to scope.
- B3 identifies removable connector lifetime chains while preserving event ordering and lease
  monitoring. E3 replaces per-chunk TTS tasks with locally owned persistent output execution,
  retaining credit, interruption and failure acknowledgements. E5 explicitly includes output
  recipient revocation, private output and recording-policy coverage.
- H6 records concrete deletions and retained domain responsibilities. Moving code or adding a
  framework does not count as a measured simplification; no arbitrary code-size target is set.
- Participant identity remains explicit; the plan does not move every capability beneath its
  participant supervisor. The room still chooses which exact generation/purpose to close.

## Design review and verification

Local review keeps all nine checkpoint identities and dependency order unchanged. Existing
A1/A3 partial prototype checkmarks are preserved; no checkpoint exit or index item is checked.
R/A/D remain isolated slices before B; C/F remove temporary bridges; H removes final globals
and audits deletions. The experiment results are evidence only, not milestone completion.

The existing authorized GPT-6 Astra xhigh reviewer checked the refreshed milestone and index
read-only. No material correction was required. It confirmed prerequisite order, retention
of lease/event/credit/interruption/playback responsibilities, distinct failure and replacement
measurements, and appropriately limited latency/capacity claims. This is a design review,
not runtime acceptance.

Verification passed: 139 relative documentation links; matching nine-checkpoint section,
overview-table and evidence-ledger order; nine unchecked exits; preserved A1/A3 partial
prototype checks; unchecked milestone index; and `git diff --check`. The milestone contains
44 implementation task entries. Reviewed the final status and relevant documentation changes;
all pre-existing runtime/test/research changes remain intact. Runtime tests are unnecessary
for this documentation-only refresh and were not rerun; the previously recorded red root
gate remains visible in the milestone.
