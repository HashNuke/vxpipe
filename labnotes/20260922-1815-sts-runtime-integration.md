# STS runtime integration

## Transcript and raw Google activity checkpoints

- Main checkpoint `f78b7f91` commits provider transcript settlement, tests and
  contracts after 133 focused checks and independent xhigh source review. Its
  post-generation acceptance deadline cannot restart behind sink finalization.
- Integrated the independent raw-mapping research as `4d89fb25` and the Google
  codec from `c4ab0c8b`. The pinned upstream receive/converter evidence was read
  by the parent; an independent xhigh source reviewer found no actionable codec
  regression, without rerunning tests or fetching upstream evidence independently.
- Main codec/session/output run: **43 tests, zero failures**, seed 0, from the
  Call Engine child, `ERL_FLAGS='+S 2:2'`. Command:

  ```sh
  mix test test/vxpipe/providers/google/sts_test.exs \
    test/vxpipe/providers/google/sts_session_test.exs \
    test/vxpipe/providers/google/sts_output_test.exs --seed 0
  ```

- Raw decoding does not repair caller activity-end/controller admission. Existing
  fixtures that manually admit output remain narrow protocol evidence. Google
  remains unadvertised; no hosted call, history replay or billable check ran.
- Integrated private handoff continuity and the review repairs from `7715d4e7`,
  `e543d969`, `e9a32226` and `39f16427`, preserving later main milestone tasks.
  Main's 117 focused tests passed. Independent rereview found a further queued
  readiness plus connection-loss race; the parent added that exact red and fixed
  scoped pre-barrier classification. The integrated group now passes 118 tests.
  See `labnotes/20260922-1820-private-connection-review.md`. Native late attachment
  ordering remains separate and unresolved.
- Broad gates will run on the committed integrated runtime; no previous umbrella
  result is attributed to these new changes.

## Output recognition format admission

- Integrated `2d549c09` after parent and independent xhigh source review. No
  actionable source finding; the reviewer did not rerun tests. Startup compares
  validated generated-output and recognizer-input formats before allocating a
  room or resolving credentials. Incompatible formats fail explicitly; no
  conversion, microphone-rate substitution or human-STT coupling is introduced.
- Main compatibility run passes **54 tests, zero failures**, seed 0: the
  `plan_startup` directory, `call_spec/sts_selection_test.exs`, and unchanged
  `room_authority/sts_transcript_modes_test.exs`, from Call Engine with two
  schedulers. The provider contract is synchronized with this admission rule.
- Direct low-level allocations and generated-audio/hosted acceptance remain
  outside this startup checkpoint. Google STS is still unadvertised.

## Post-commit gates

- Format and warnings-as-errors compile passed at `9bf245a5`, but strict Credo
  found PlanStartup's new size violation. Recorded and repaired it separately as
  `f9db3319`, preserving behavior; 54 focused checks remain green.
- All four static gates pass at `f9db3319`: root format, warnings-as-errors
  compile, strict Credo and unused-lock verification. Full umbrella test evidence
  is pending; no new runtime edits will overlap that run's baseline.
