# Audit credential readers

## Scope and baseline

Continued from the clean `f24f399` scope-correction checkpoint. The previous goal turn made
progress by committing the user's clarified requirements. This checkpoint audits existing
AI/speech credential readers and fixes cached credentials used to construct new source speech
clients. It adds no transfer/recovery feature and no third-party credential lifecycle operation.

## Findings and change

- Initial model/speech, opening, agent destination and connection STT resolve through the
  injected source. Calls supplies the encrypted repository bridge. Private destination STT keeps
  its configuration within one preparation attempt.
- Private briefing copied the source agent's existing TTS configuration into a new client.
  Source restoration did the same after losing that client. Both skipped a current lookup.
- Resolve the source participant's pinned selection in the existing bounded worker before new
  client construction. Briefing resolves before outbound dialing; restoration retains its existing
  750 ms budget. Use the request's current activation ID for returning source agents.
- Leave already running source clients alone. A missing briefing credential follows existing
  preparation failure handling; a missing required restoration credential starts no transport and
  follows existing terminal recovery failure handling.
- Independent source audit also found reachable global hosted readers under legacy `CreateRoom`.
  Record them as remaining checkpoint 2 work; do not claim this focused fix closes the checkpoint.

The durable [reader inventory](20260915-1521-credential-reader-boundaries.md) records paths, rationale,
rejected alternatives and remaining destination binding/override checks.

## Red / green evidence

- Added a mutable test credential source and two cases in `HumanWebTransferRoomTest` using a
  named source-voice binding. Focused red: two tests, two failures; no fresh lookup occurred and
  the briefing transport used the earlier synthetic key.
- Strengthened the existing source-restoration test to inspect the replacement transport's
  credentials. Focused red: one test, one failure; it received the earlier synthetic key.
- After implementation, the three cases passed. Added unavailable-restoration coverage to the
  same existing test harness: four focused cases pass, with no replacement transport on failure.
- Initial log redirection used the wrong relative depth from the umbrella child and failed before
  Mix ran; corrected to the root `tmp/` directory. No test result is attributed to that failed command.

## Review and remaining verification

GPT 6 Astra xhigh independently audited the readers, confirmed both cached-client findings and
identified the remaining legacy global bypass. It found no further planned-reader privacy defect.
The focused five-file implementation review found no blocking issues, including activation
identity, resolve-before-dial ordering, deadline cancellation, local Morse behavior and privacy.
The broader Engine group passed 66 tests with zero failures (agent/human transfer room tests,
inline activation and agent model tests; seed 235296, max cases four).

All five root gates passed after review:

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix test --preload-modules --max-requires 1 --max-cases 4 --seed 235296
mix deps.unlock --check-unused
```

The full test run completed 1,513 tests, zero failures and 30 excluded: MCP 37, Agent Runtime 93,
Engine 686, Calls 81, Gateway 413, Artifacts 20, Persistence 77 and Console 106. No implementation
changed during these checks. Native cases passed in this run; no claim is made about the cause of
previous timing observations. Logs remain in ignored `tmp/source-speech-root-*.log` files.

Documentation links, JSON examples, whitespace and exact checkpoint paths were verified before
staging. The milestone remains one of seven checkpoints complete; checkpoint 2 is still partial.
