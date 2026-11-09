# Native tool interruption

## Scope

Continue C3 of shared participant tool execution. The previous status-only turn
made no implementation progress. Worktree started clean at `61efd923`.

Speech interruption currently calls provider interruption for every pending tool
turn, even when it has no audio. Ordinary Morse removes that association; shared
invocation work survives but cannot deliver its outcome. Reversible hold also
retires every tool association. Full room-binding equality separately rejects a
completion when only `activity_turn` changes. Tests now require final delivery
after speech interruption/activity changes and ordinary as well as duplex MCP
transfer success/failure. These changes precede the implementation.

Keep source/activation identity, policy revocation and audio fencing intact. No
new provider protocol, tool executor or MCP client. Close-for-cutover remains
terminal. Independent design/source review requested from the existing Astra
review agent; full conversation parity remains unfinished.

## Implementation and verification

Six initial red failures reproduced (seed `140209`); ordinary/duplex transfer and
interruption acceptance then passed (8 tests, seed `320087` had the two remaining
room-hold failures; after room retention, 8/8 passed). Removed the unused capability
hold-mode query and its room-only special branch. Audio output and response-origin
fencing remain unchanged. Accepted-result authority uses stable source identity
and policy scope; queued hangup effects still require current open input authority.

Genuine provider cancellation also reproduced a silent stranded outcome (seed
`582914`). It now marks transport delivery unavailable while preserving the
bounded invocation. Completion terminates explicitly unless an authorized
terminal transfer already retires the source. Ordinary interruption never
artificially cancels tool-only provider turns.

Focused capability, room, identity, MCP and transfer lane: 174 tests, zero failures,
seed `735725`. Expanded capability/room/tool/agent-runtime/LLM-MCP lane: 595 tests,
zero failures, 8 exclusions, seed `24900`. The expanded lane also proves in-flight
call end and owner loss remove native MCP worker, client, session supervisor,
owner and capability within one-second assertion bounds. C2 lifetime task now
passes (7/20 overall). C3 remains open.

Lean build, oracle and replay passed (1 test, seed `469882`). Formatting, compile
with warnings as errors, strict Credo and unused dependencies passed before the
review fix below. Full umbrella verification has now started for this checkpoint.

## Review reproduction

Astra found an inverse cancellation race: if completion is retained behind invalid
policy scope before provider cancellation, the latter previously marked delivery
unavailable but no second completion notification arrived. The test reproduced
with synthetic policy injection (seed `234955`), then with the real
MediaPolicy.Authority.leave operation (seed `737674`). The existing bridge now
redelivers its already-held lease on matching cancellation; no operation is
resubmitted. Lifecycle/identity lane after the fix: 60 tests, zero failures,
seed `76265`. Re-review requested; final root evidence pending.

Origin-aware stop-hold sessions still require a valid semantic completion path;
ordinary Morse is not evidence for that distinct operation. External/hybrid
quiescence and close-for-cutover remain strict. Conversation modes, shared budgets,
terminal discard and fresh-sequence replay are still subsequent milestone work.

## Final checkpoint evidence

All five root checks pass after the review fix. Full umbrella suite: **5,137 tests,
zero failures, 371 excluded**, seed `380795`. Formatting, warnings-as-errors
compilation, strict Credo and unused dependencies passed. The Lean lane above
covers the hold/interruption state-machine change; the subsequent bridge
redelivery fix does not change the modelled transitions. Relative documentation
links and checklist/index count validation pass.

GPT-6 Astra xhigh final read-only source, test and documentation review approved
with no remaining actionable findings. The reported inverse cancellation race
was reproduced before fixing; no other source/test findings remained. This is
one coherent interruption/lifetime checkpoint, not completion of the full
shared-participant milestone. No provider implementation changed and no deployment.
