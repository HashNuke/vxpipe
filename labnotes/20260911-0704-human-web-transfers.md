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

## Refactor: participant-neutral room transfer ownership

- Mechanically renamed the room coordinator and its cohesive support namespace from
  `RoomAuthority.AgentTransfer` to `RoomAuthority.ParticipantTransfer`, including its state fields,
  internal messages, and room-supervised worker references.
- The transfer tool and the existing agent-to-agent test remain named for their actual contracts;
  no behavior, public wire format, timeout, or lifecycle rule changed in this refactor.
- Focused verification: all 11 agent-transfer room tests pass after the rename.
- Full verification passes formatting, warnings-as-errors compilation, every umbrella suite with
  the same counts as the prior checkpoint, strict Credo, and unused dependency-lock checks.

## Checkpoint: private web-human room lane

- Added the first end-to-end room test before the runtime behavior. It initially failed to compile
  because `ConnectionAttachment` had no admission or transfer-attempt contract. After that boundary
  existed, the next red run exposed an invalid attempt to project agent transfer history for a human
  destination; human briefing preparation now starts with no implicit conversation history.
- A pending human transfer receives a generated attempt ID. Its provisional connection is bound to
  the catalog destination and is disabled for speech input, room publication, room subscription,
  transcript projection, and participant/Variables authority.
- A dedicated destination TTS capability uses the retained source-agent runtime. It speaks only the
  required bounded reason and optional fixed notice to the destination output sink. The caller sink
  receives no briefing audio.
- `ParticipantTransferControl` records early acceptance and usable-media readiness only for the
  exact actor, participant, connection process, incarnation, and current attempt. The handoff waits
  for both controls and output-sink playback completion. Stale, forged, foreign-process, and
  duplicate controls reject.
- Participant admission applies the existing media-policy commit barrier before the destination
  connection is promoted to ordinary mix-minus media. On success the source agent subtree and its
  speech capability stop, while the room and Call Variables process remain. Dropping the pending
  destination fails and cleans only that attempt; the source remains active.
- Kept the concerns split between the participant-neutral coordinator, human-lane state machine,
  briefing builder, human committer, shared completion projection, connection lifecycle, and typed
  control command rather than adding all callbacks to `RoomAuthority`.
- Focused verification: the three human-transfer room tests pass. The complete Call Engine suite
  passes 336 tests with 0 failures and 1 excluded integration test. Warnings-as-errors compilation
  and strict Credo also pass before the umbrella completion run.
- The first full umbrella test run encountered the existing Console telemetry-isolation race: its
  fixed drop-count assertion observed unrelated concurrent umbrella telemetry. That exact test
  passed alone, and a clean full rerun passed MCP 37/3 excluded, Agent Runtime 58/2, Call Engine
  336/1, Calls 37, Persistence 25, Gateway 87/4, and Console 57.
