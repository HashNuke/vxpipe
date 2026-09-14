# Transfer desk disconnect

- The readmission browser check exposed a stale desk display: its WebRTC peer reported
  `disconnected`, but the page continued to say “Listen to the private briefing” with a disabled
  Accept button. The browser adapter handled only terminal `failed`/`closed` and channel closure.
- Scope decision: expose interruption through the existing status, ledger and Disconnect control.
  Keep the peer during transient connectivity loss and restore the prior transfer state when it
  reconnects. Do not add a reconnection coordinator, timeout, automatic retry or new UI component.
  This fixes the stale display; it does not establish the cause of the earlier briefing timeout.
- Extended the two existing transport/page cases with disconnected/reconnected transitions and
  unavailable acceptance. Both failed before implementation: missing interruption callback and no
  notification (`vxpipe-desk-disconnect-red.log`). Both now pass with the existing setup test;
  TypeScript checking passes (`vxpipe-desk-disconnect-green.log`, `vxpipe-desk-disconnect-typecheck.log`).
- Rendered the changed page in agent-browser Chrome at 390×844 and 1440×900. Browser-only simulated
  admission, media and connection events showed interruption with a readable Disconnect action,
  restored the disabled briefing acceptance after reconnect, and returned to Connect after manual
  disconnection. Both screenshots were visually inspected. This is rendered state verification,
  not a new live-provider handoff check. The owned browser was closed before root compilation.
- Browser-fixture correction: the first simulated session omitted required call/participant fields;
  the application correctly rejected it. Added the real response shape to the temporary fixture.
  This was a verification setup error and required no product change.
- Local screenshots are `vxpipe-desk-disconnect-{mobile,desktop}.png`. The full Console assets
  suite and required root gates are running; no development server restart or dependency change.

- Final verification: all five root gates pass, with 1,300 tests, zero failures and 15 exclusions
  at concurrency four, seed 226627. All 11 Console asset checks pass and TypeScript passes.
  Results/logs are `vxpipe-desk-disconnect-final-*` and `vxpipe-desk-disconnect-assets.log`.
  Changed documentation links resolve; only evidence/documentation edits followed verification.
