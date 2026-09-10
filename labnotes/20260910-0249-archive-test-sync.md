# Archive test synchronization

## 2026-09-10 — diagnosis and repair

- The complete umbrella suite twice failed
  `DefinitionDrivenCallTest` while waiting for an update snapshot; the same test passed by
  itself with the same seed.
- The test configured an archive handoff capacity of four. During call startup, its blocked
  baseline snapshot plus two participant facts and the room-opened fact can occupy all four
  slots. Sending the baseline writer's result does not synchronously make a slot available:
  the writer task and subscriber still have to process that result.
- When the variable update won that scheduling race, its local update correctly succeeded
  while the nonblocking archive handoff correctly rejected the fifth item as full. The test
  then waited for a snapshot that had intentionally been dropped. This was a test setup bug,
  not a production archival or Call Variables failure.
- The test is about the room-owned Call Variables process remaining independent from
  `RoomAuthority`; bounded-overflow behavior has its own focused tests. Its fixture capacity
  is now eight, enough for the startup burst and the update without relying on scheduler
  timing. No storage acknowledgement was added to the live update path.
- Red evidence: two exact-state root runs failed at the update-snapshot assertion after five
  seconds while showing the three startup facts in the test mailbox. The focused test passed
  with each failing seed, confirming the scheduling dependency.
- Green evidence: the focused test passes with the capacity-eight fixture, and the complete
  umbrella suite passes MCP 27/0, call engine 181/0, Calls 35/0, Persistence 25/0, Gateway
  66/0, and Console 55/0. Three MCP, two call-engine, and four gateway integration tests
  remain excluded from the default lane as designed.
