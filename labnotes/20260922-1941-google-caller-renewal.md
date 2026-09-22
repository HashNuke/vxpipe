# Google caller renewal

- Follow-up xhigh review of `3d3c7d5f` confirms its first two P2s fixed, then
  identifies reversed model-end ordering: interruption before caller end, delayed
  interrupted-model end after caller end, fresh response playback and handle.
  The prior model end still sets the unqualified completion bit and renews the
  socket before the fresh response's model end. Recorded the task in milestone E
  before the test and implementation.
- Red handle `86660`, exit 2: **29 controller tests, one expected failure**.
  The wire is nil at the asserted safe boundary because replacement has already
  begun. This is the reviewer's actual-controller reproduction, not a source-only
  prediction. Run from Call Engine with `ERL_FLAGS='+S 2:2'`:

  ```sh
  mix test test/vxpipe/call_engine/capability/google_sts_controller_test.exs --seed 0
  ```

- Repair: retain a private interrupted-model marker on an unfinished audio caller.
  At its genuine end, if model completion has not yet been observed, monotonically
  latch the allocation's existing resumption ambiguity. Subsequent unqualified
  ends/handles cannot clear it; connection loss fails with no replay/replacement.
  If the interrupted model end was observed before caller end, the existing
  successful renewal test still requires fresh response completion and handle.
  This is an interim safety repair, not full response-overlap acceptance.
- Integrated green handle `63238`, exit 0: **229 tests, zero failures**, seed 0,
  two schedulers, 6.5 seconds. Used the recognition/startup/room regression command
  from `labnotes/20260922-1922-recognition-deadline-proof.md` plus Google
  `sts_test`, `sts_session_test`, `sts_output_test` and the actual
  `google_sts_controller_test`. The three files live under
  `test/vxpipe/providers/google/`; the controller under
  `test/vxpipe/call_engine/capability/`. No hosted execution or acceptance claim.
- Independent xhigh follow-up source review clears this bounded repair: the
  ambiguity marker survives to genuine caller end, the latch is monotonic, and
  both arrival orders have controller regressions. The reviewer did not rerun
  the tests. General response overlap and hosted acceptance remain open.
