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
- Private handoff continuity and its two review repairs are awaiting independent
  rereview before integration. Native late attachment ordering remains separate.
- Broad gates will run on the committed integrated runtime; no previous umbrella
  result is attributed to these new changes.
