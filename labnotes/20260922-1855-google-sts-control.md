# Google STS control profiles

- Baseline runtime `d7c3af73`, documentation HEAD `be617cad`, clean main worktree.
  Its 68 focused checks and four post-commit static gates pass. Coordinated root
  test rerun awaits the independently reproduced native handoff repair.
- Recorded profile and external-boundary tasks before tests. Existing codec
  accepts hybrid while leaving automatic activity detection enabled; its session
  nevertheless sends client activity controls. The official Live reference only
  permits these when automatic detection is disabled. Reject this unproven Google
  combination in pure configuration, without removing the shared hybrid mode.
- Source inspection also finds every external boundary is sent on the wire,
  including idle ends and duplicate starts/ends; ends reuse partial input text
  as terminal caller evidence. Reproduce these project-owned protocol defects.
- Scope: truthful provider/external descriptor claims and idempotent external
  boundary admission. Full overlapping response correlation, caller final-text
  retirement, room controller support and provider interruption/history remain
  explicit unfinished milestone tasks. No hosted call or changed timeout.
- Primary evidence: [Live realtime input](https://ai.google.dev/api/live#BidiGenerateContentRealtimeInput),
  inspected during the preceding controller checkpoint. The documented activity
  precondition informs rejection, not an invented alternate hybrid wire profile.

## Verification

- Initial owning-child group: **57 tests, four failures**. Exact reds: idle
  external end sent a wire activity end, duplicate start sent a second wire start,
  hybrid public configuration succeeded, and external end carried partial input
  text instead of the empty no-final-text convention.
- Restricted only Google STS's pure public/private configuration and descriptor
  supported list. Provider callback rejection remains before duplicate guards.
  External boundary no-ops occur before wire sends; valid ends carry no inferred
  final caller text. No shared hybrid contract, deadline or buffer changed.
- Added private-tampering startup coverage: a config changed to hybrid after
  construction fails initialization without starting the fake socket. Expanded
  focused group: **72 tests, zero failures**, seed 0, `ERL_FLAGS='+S 2:2'`:

  ```sh
  mix test test/vxpipe/providers/google/sts_test.exs \
    test/vxpipe/providers/google/sts_session_test.exs \
    test/vxpipe/providers/google/sts_output_test.exs \
    test/vxpipe/call_engine/capability/google_sts_controller_test.exs \
    test/vxpipe/call_engine/capability/sts_transcript_settlement_test.exs --seed 0
  ```

- Independent xhigh source review found no actionable defect; no tests or hosted
  calls were run by that reviewer. Parent owns the test evidence above.
- The existing provider-mode interrupt encoder still sends client activity end;
  its distinct wire/history repair remains open and explicitly recorded before
  implementation. This checkpoint does not make that path valid or close full
  profile/room acceptance. Provider contracts and integration docs are updated.
