# Transfer desk readmission

- Previous goal turn made progress: committed stale-policy retries and spoken recovery as `ab1d965`
  and `b06d539`. Real browser retry then exposed a permanent persisted admission after a failed
  private connection. Revalidated the worktree and preserved the other agent's docs-site work.
- Design review: retain consumed tokens/admissions, mark an exact admission released, and replace
  lifetime call/participant uniqueness with active-admission uniqueness. The current Gateway session
  owns reservation expiry and connection termination; no UI bypass or second transfer coordinator.
  Scope, alternatives and migration implications are in `docs/transfer-admission-lifecycle.md`.
- Extended the existing persistence admission test to release support, reissue/claim a new token,
  preserve history/start/incarnation and reject stale/wrong-token release and consumed-token replay.
  Initial red: missing `Calls.release_admission/2` (`vxpipe-transfer-readmission-store-red.log`).
  Implemented exact transactional release and the partial index; the focused case passes in
  `vxpipe-transfer-readmission-store-green.log`. The test database migration completed successfully.
- Added Gateway session lifetime cases for unclaimed expiry, request-owner loss before binding,
  and bound connection loss after credential TTL. All three initially failed without release or
  binding support (`vxpipe-transfer-readmission-session-red.log`). They now pass with the existing
  HTTP admission checks. Added failed-release retry and foreign-caller rejection cases and connected
  the actual WebRTC recovery cases to a session release callback; broader verification is running.
- Destination sessions carry the callback privately. Their snapshots expose an internal owner only
  to transport setup, never in public JSON. The WebRTC connection monitors that owner; the session
  monitors the connection incarnation. Session state inspection excludes the callback and claim.
  A failed database release retains the reservation and retries, rather than making another claim
  available on uncertain evidence. Ordinary caller-session lifetime is unchanged.
- Dev migration, real-browser retry and final umbrella verification remain to be completed. No
  running server has been restarted and no UI code has changed.

- Resumed after the user's accounting request. That reply was a status-only turn with no code
  progress; revalidated the dirty worktree and the existing browser processes before proceeding.
  The focused Gateway run passed 35 cases and Calls passed 12; development and test migrations
  both completed without restarting the running server.
- The first browser retry exposed two rejected caller text submissions before another transfer
  tool started. Diagnostics showed two model-unavailable failures. A later prompt started a new
  tool call without a code/provider configuration change. One connected retry produced no audible
  briefing before its deadline. These attempts are failures, not successful retry evidence; their
  exact cause is not established by the generic client error or the diagnostics aggregate.
- Extended the existing destination-loss WebRTC recovery case through another actual transfer:
  new private briefing audio, acceptance readiness, fresh destination STT, transfer activation and
  decoded support audio on the original caller. The three recovery cases passed immediately;
  this is additional integration evidence, not a reproduced regression requiring another fix.
- Reloaded the owned desk, requested another transfer in the original running call, and completed
  briefing, acceptance, preparation, cue and activation through the rendered sample. The caller
  retained its one original connected peer across four tool attempts. Live Deepgram produced final
  support and caller transcripts; synthesized microphone speech crossed both actual WebRTC paths.
  Both peers decoded the connection cue. Desktop 1440×900 and mobile 390×844 screenshots were
  visually inspected, with readable controls and no horizontal overflow.
- Local evidence is `vxpipe-readmission-{caller,desk}-probe.json`,
  `vxpipe-readmission-browser-evidence.json` and the caller-desktop/active-mobile screenshots.
  Probes contain controlled test speech and safe event/audio measurements. Physical two-device
  audibility and the unexplained earlier briefing failure remain outside this successful check.
- Removed incidental formatting changes in pre-existing Calls/Persistence code so the checkpoint
  stays focused. Closed the owned caller, desk and diagnostics browsers. The extra CDP inspection
  endpoint was already unavailable when closing; the original desk daemon confirmed closure.
  Final root formatting, warnings-as-errors compile and strict Credo pass; umbrella tests are running.

- Final root verification passes formatting, warnings-as-errors compilation, strict Credo, all
  umbrella tests and unused dependencies. The run contains 1,300 tests, zero failures and 15
  exclusions at concurrency four, seed 306911, including 598 engine and 332 Gateway cases.
  Results/logs are `vxpipe-readmission-final-*`; only evidence/documentation edits followed.
  The milestone/index and curated implementation notes now record the fixed admission boundary
  and successful retry while leaving all full delivery checkpoints open.
