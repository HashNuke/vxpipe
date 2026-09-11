# Human Web Transfers

## Checkpoint: compile a bounded human destination

- Added a red compiler test for a catalog human using the exact web
  `receive`/`transfer` connection intent, an optional fixed notice, and a required private briefing
  reason. The focused test initially failed at the unsupported `transfer_notice` field.
- Schema `20260911.02` now keeps entry and transfer admissions distinct, pins the notice in the
  resolved plan, and permits only agent destinations or web humans with transfer admission.
- Human destinations always require the transfer tool's bounded `reason`; no address, unrestricted
  variables, or conversation history enters model-visible tool arguments.
- Rejected using ordinary `start_call` admission for a transfer destination because it would erase
  the admission boundary needed by the pending private lane.
- Verification: the focused compiler test passes with 12 tests, and the complete Call Engine suite
  passes with 333 tests, 0 failures, 1 excluded.
- The first umbrella pass exposed one unrelated timing-sensitive model-inference timeout assertion;
  its focused rerun passed. The clean full rerun passed formatting, warnings-as-errors compilation,
  all application suites (MCP 37/3 excluded, Agent Runtime 58/2, Call Engine 333/1, Calls 37,
  Persistence 25, Gateway 87/4, Console 57), strict Credo (4,509 modules/functions), and unused
  dependency-lock checks.
