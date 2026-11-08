# Explicit MCP session owners

Date: 2026-11-08. Baseline: `adca5f37`, committed and pushed after Astra xhigh
approval and all root/protocol/preparation gates.

## Scope and reproductions

Continue T1 with explicit host-owned session isolation. A host supplies its own
named DynamicSupervisor; resolve that owner once to an exact local PID, scope
session registration by that PID plus the unchanged credential key, and keep
exact parent/integration/client identities in lifecycle operations. This slice
does not claim blocked-start cancellation or the common shutdown budget.

- Before source changes, an isolated existing-BEAM probe reproduced four gaps:
  ignored owner options cause shared clients, requested owner stop leaves the
  client alive, dead ownership falls back to global sharing, and changed endpoint
  policy is silently reused. Four failures, seed 589612.
- Added owner-app tests before implementation. Initial run: 10 tests, 9 failures,
  seed 474553. Compatible reuse already passes; isolation, dead-owner rejection,
  effective policy comparison, exact close, revocation fanout and failed-open
  isolation fail as expected. Added scoped lookup/foreign-handle acceptance before
  implementing those new API contracts. Final red: 11 tests, 10 failures,
  seed 665589. Initial implementation passes the owner, legacy connection and
  telemetry slice: 24 tests, zero failures, seed 518734.

Legacy open/key-close remain explicitly transitional while shipped consumers
migrate. An explicitly supplied invalid owner must never use the legacy path.
Current authorization and post-start revocation checks remain authoritative.
Compare normalized effective options after runtime overrides, including runtime
identity, without storing raw credentials in registration metadata.

## Implementation and review

- Hosts supply an ordinary supervised DynamicSupervisor, avoiding an extra owner
  process or identity framework. Registration uses its exact PID; connection
  handles retain that parent as well as the integration/client PIDs. Scoped
  lookup and `owned_by?/2` reject foreign or stale handles. Exact close never
  resolves a replacement parent by name.
- Owner registration metadata contains the parent PID, runtime module and a digest
  of normalized effective options; each client entry identifies its integration
  owner. No raw credentials are retained there. Revocation enumerates both legacy and explicit-owner sessions
  without changing the credential key. Failed initialization closes only the exact
  child it started; a concurrent opener cannot clean up another opener's session.
- A controlled initialization gate reproduced premature reuse of a registered
  but uninitialized client: 12 tests, 1 failure, seed 99765. Reuse now checks
  current authority and waits for runtime readiness. Focused green: 25 tests,
  zero failures, seed 761168. Full caller/deadline cancellation is still separate.
- Astra xhigh review reproduced a duplicate-key normalization mismatch:
  Keyword.get uses the first value but Map.new kept the last. Added the regression
  before the fix: 13 tests, 1 failure, seed 210141. Normalize merged runtime options
  using first-value semantics before passing them to the runtime and hashing them.
  This preserves what the runtime actually reads and prevents false compatibility.
- The duplicate fix passed 26 focused tests, seed 721860. Broader verification
  then passed MCP default (185 tests, 23 excluded, seed 886662), wire (23 tests,
  seed 818907) and Call Engine remote MCP including integration (36 tests,
  seed 616644).
- Review reproduced the same publication gap through public lookup/handle
  validation. Added a separate gate test before fixing it: 14 tests, 1 failure,
  seed 839584. Public lookup now checks the registered runtime's readiness;
  internal raw registry access remains available only to the startup path. No
  extra readiness process or mutable publication registry was introduced.
- That correction passes the 27-test focused slice, seed 291707. Root format,
  warnings-as-errors compile and strict Credo pass. MCP default then passes
  186 tests (23 excluded), seed 739396; wire passes 23, seed 363835.
- Added real-wire verification of the original owner-isolation contract. Two
  owners use an equal synthetic credential key but receive distinct clients and
  remote session IDs. Stopping the first host produces owned worker DOWN and GET
  socket closure; the second still executes echo using its original session.
  The fixture assigns unique synthetic IDs and echoes the request session header.
  All 10 transport lifetime cases pass, seed 616097. This is standalone loopback
  evidence, not saved-database or admitted-call acceptance.
- Astra reproduced a mixed-incarnation lookup with a debugger scheduling pause:
  read integration owner A, replace its session with B, resume before reading the
  client. Lookup combined owner A with client B. A controlled registry-boundary
  regression reproduced the same invalid pairing before correction: 15 tests,
  1 failure, seed 831345. Client registration now identifies its integration owner;
  client, runtime and policy reads require that same exact incarnation. A mismatch
  fails instead of constructing a mixed handle.
- The corrected focused slice passes 28 tests, seed 443623. Astra reran the exact
  debugger replacement probe against the compiled correction: lookup returns
  `:error`, and the replacement remains current/usable. No remaining blocking
  source findings were reported; final root/wire gates and staged review follow.

## Final verification

- All five root gates pass: format, warnings-as-errors compile, strict Credo,
  umbrella tests and unused dependency check. The full suite reports 5,017 tests,
  zero failures and 275 excluded, seed 580491, in 742.0 seconds.
- The final tagged wire slice passes 24 tests, seed 626532, including the new
  two-owner session/worker/socket isolation case. No source-cutover or speech
  state machine changed, so Lean was not required. No UI changed.
- Relative documentation links and staged whitespace checks pass. Final GPT-6
  Astra xhigh review approved the exact 12-path staged checkpoint with no valid
  outstanding findings after inspecting the final gate evidence.

Blocked initialization/caller cancellation, complete retirement fencing and the
shared deadline remain future T1 work. No participant wiring, background catalog
jobs, saved-call acceptance or performance completion is claimed here.
