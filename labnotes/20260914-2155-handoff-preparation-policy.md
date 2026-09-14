# Handoff preparation policy

- Previous turn made progress: b0f4fd2 added native model/TTS delay and failed-model recovery
  evidence; all five root gates passed. Revalidated HEAD and worktree before continuing. Only
  the other agent's untracked call-room visual labnote remains outside this task.
- Current gap: HumanMediaHandoff retries stale candidates during readiness collection, cues and
  final commit, but initial Preparation.run_candidate errors immediately fail the transfer.
- Reuse the embedded connection's existing deferred readiness acknowledgement to pause its
  candidate-preparation callback. No production test hook or new fixture process is necessary.
- Red: two focused initial-preparation policy cases fail because the original phase is unavailable
  after the change; the caller receives a recovery drain instead of continuing the accepted
  handoff. Cases cover removal of STT demand and an unrelated membership policy revision.
  Evidence: vxpipe-initial-preparation-red.log, 2 tests, 2 failures.
- Implement retry only for stale-candidate/changed-room graph results, including typed resource
  failures carrying stale_candidate. The initial approach assumed failed candidate cleanup was sufficient; the next result disproved it.
  Keep the same prepared participant, worker, attempt deadline, held outputs and existing wait
  players; recapture required resources and add only newly required listeners.
- First retry implementation passed removal-of-demand but stalled the unrelated case. The
  preparation boundary discarded every partial lease on failure, including the healthy private
  replacement STT session, then opened a new transport on retry. Retrying after cleanup violates
  the required resource-retention contract. Preserve partial leases while the same owner retries;
  keep the existing run_candidate cleanup behavior for callers that do not retry.
- Green after retaining partial leases: both initial-preparation cases pass with the same
  provider transport, room resources, worker, audience scope and deadline. Removed STT is stopped;
  an unrelated revision does not start a replacement. Both finish the mandatory cue and activate.
- Removed an unused alias exposed by moving cleanup to the preparation boundary.
- Broader focused checks pass: 57 tests, zero failures across human handoff, agent handoff and
  readiness inventory. No browser or development-server interaction was needed.
- Design review recorded in the milestone and existing incremental-media-policy document:
  immediate cleanup remains the default API; the retrying handoff owns returned partial leases.
  Failed/nonreusable leases are discarded, and existing owner/deadline cleanup remains in force.
- All five root completion gates passed after the fix: format, warnings-as-errors compile,
  strict Credo, umbrella tests and unused-lock check. Umbrella: 1,306 tests, zero failures,
  15 exclusions, seed 894531, max_cases 4. Engine: 600 tests; Gateway: 336 tests including the
  existing 20 native transfer cases. Temporary log prefix: vxpipe-preparation-policy-gates-.
- The unrelated phase-loss recovery and Morse audio intermittency were not reproduced or
  explained by this change. Keep those concerns open; do not attribute them to this policy race.
- Sent progress through pushnotify at the regression, cleanup finding and focused-green stages.
