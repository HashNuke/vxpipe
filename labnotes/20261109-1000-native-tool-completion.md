# Native tool completion

## Starting point and scope

Continue from pushed `a9c43904` (11/20 milestone tasks). The previous goal turn
made progress: bounded rejection and retained-ID replay were implemented and
reviewed, with 2,385 Call Engine tests and Lean passing. No external blocker.

C3 needs a valid result path after speech-origin retirement, bounded terminal
settlement, and safe usage/race acceptance. Keep execution, authority and MCP
ownership in the existing common engine.

The user explicitly clarified that small adapter API plumbing is permitted:
"Yes—allow adapter plumbing; keep all tool behavior common." This permits existing
adapters to accept the common typed result/context operation. It does not authorize
provider-specific tool policy, MCP execution, new models or deployment.

## Reproductions and decisions

- Origin-aware stop-hold/release plus new unrelated input prunes the original
  context; an admitted result then fails with `:stale_request`. One failing
  capability test reproduced this before production edits (seed `895138`).
- Removing caller policy presence after submission leaves its completed result
  retained forever. The real-room test failed to observe termination (seed
  `938829`). The terminal result path now exits explicitly when original delivery
  authority is gone; room, capability, registry and bridge monitors prove teardown.
- A result completed during a reversible stop-hold initially terminated the room
  (`2 tests, 1 failure`). Preserve that existing lease until successful release,
  then use bridge redelivery. Both completion/release orderings now pass without
  another business submission. Mute holds keep their existing acceptance behavior.

Independent Astra design review confirms the smallest sound boundary is typed
`{:tool_result, call_ref, result}` through Session → Channel/Input → provider
`submit_input/3`. This reuses command bounds, ownership, staged contexts, early-event
gating and timeout cleanup. Original tool authority is captured in its pending
record separately from transient speech epochs. New output uses the currently
authorized response context; old audio contexts stay retired. Context-free
allocations use their existing native result callback through the same Session
operation. Opted-in adapters must implement the typed operation explicitly.

The origin-aware probe now proves local result acceptance, valid current-context
follow-up output, no second result and rejected old-context speech (seed `621603`).
The old cancellation test is renamed to describe queued completion/cancellation
ordering; it no longer claims redelivery caused settlement. Legitimate stop-held
completion/release now exercises retained-lease redelivery instead. Twenty native
completions with retention configured to four prove old IDs evict and only the
newest four remain rejected by the registry's public identity check.

## In progress

Common production changes and focused tests are in the worktree. Adapter tests
are being migrated to the shared Session result operation before minimal protocol
plumbing. Independent implementation review, relevant complete suites, root gates,
Lean, count reconciliation, commit and push still remain. C3 is not checked off.

## Adapter and review evidence

- Migrated existing protocol fixtures to the Session operation first: 69 tests,
  seven expected failures (`436152`) before adapter plumbing. All 69 then passed.
  ElevenLabs, GPT-Live and duplex Morse use the supplied continuation context;
  Google covers both existing context-free and response-start profiles. Direct
  origin-aware result callbacks were removed rather than retained as fallbacks.
- Fresh-context GPT-Live/ElevenLabs and common capability/room regression: 159
  tests, zero failures. The live GPT-Live test was mechanically migrated, not run.
- Independent Astra review identified missing source-controlled release redelivery
  and Google rejecting a fresh result context even at a settled idle boundary.
  Both were reproduced together: five cases, two failures (`953457`). Both then
  passed. Source hold/receipt/arm uses the actual connection handshake. Google
  rejects IN_PROGRESS and omitted status before accepting an exact pending call
  at explicit IDLE, and attributes new output to the supplied context. Full input
  and recovery quiescence still require no pending tools.
- The reviewer requested a precise after-release barrier. The connection now
  reads room state after its own arm reply, proving the room cleared the cutover
  and restored its epoch before the worker completes. This avoids assuming that
  acknowledging the connection means the room has processed its reply.
- Moved Morse result context/queue preparation into its existing ToolReply module;
  strict Credo then passed without another module or policy abstraction.
- Full Call Engine passed: 2,393 tests, zero failures, 100 excluded (`583671`).
  The final test-only handshake barrier and unused helper argument removal were
  made afterward and receive focused re-verification. Root formatting, compile,
  strict Credo and unused-dependency checks passed; final Lean evidence follows.

This checkpoint closes C3 semantic delivery and bounded lease/ID settlement:
13/20 tasks, C3 4/5. General race/usage, shared conformance/receptionist acceptance,
local performance evidence and final umbrella gates remain open. No deployment
or vendor live acceptance was performed.

Final verification: the updated release-order and ElevenLabs suites passed
64 tests, zero failures (`550933`). All quick root gates pass after the final
code edits. Lean build, oracle drift check and Elixir replay passed (`506397`).
Final review approved source/tests/counts and found stale pending-language in
three docs; those statements are now reconciled or explicitly historical.
