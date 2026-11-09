# Native saved MCP

## Scope and starting evidence

Continue from `8ebc3a6a`, committed and pushed with a clean worktree (9/20 tasks).
The preceding goal turn made progress: shared conversation admission and invocation
bounds were implemented, reviewed, committed and pushed. Full umbrella checks
passed at `fa7e2a35`; the bounds checkpoint added 133 focused and 3,039 relevant
application tests, with quick root gates, Lean and clean Astra xhigh review.

Close C2's remaining saved-authority acceptance using Console's existing
`SavedMCPRuntimeCase`, database repository, HTTP admission, authenticated disconnect
route and local MCP wire server. Existing Call Engine cases already prove selected
aliases, stale pins, tenant isolation, independent catalog ownership, transfer
success/rollback, and owned teardown. Direct credential-lease revocation does not
substitute for a saved-connection change.

## Acceptance evidence

Five new native cases pass without production changes (seed `1749`):

- Disconnect and credential replacement during an actual submitted wire call
  allow exactly that outcome, reject later invocation, and keep the admitted call
  operational. Teardown ends the participant-owned session subtree; no retry or
  tool discovery is issued.
- Disconnect and replacement after preparation reject native admission before
  any MCP protocol operation and leave the durable call failed without an
  incarnation.
- Catalog schema change rejects a stale prepared pin. Fresh native admission
  rejects old arguments before business work and executes the selected alias with
  current allowed arguments. Result events travel through the admitted WebRTC
  peer; the existing fixture checks public messages for credential/endpoint leaks.

These are acceptance tests of existing shared behavior, so no failing-test-driven
runtime change was needed. The native model is the local Morse semantic fixture;
no live provider or deployed service is used. Existing LLM saved-authority and
transfer cases will run alongside them before closing the task. Independent
source/test review found no actionable issues and approved C2 closure after the
combined verification.

Final combined lane: **18 tests, zero failures**, seed `912608`, with `--include
integration` selecting native saved MCP plus existing LLM in-flight, boundary and
transfer cases. Formatting, warnings-as-errors compilation, strict Credo and unused
dependency checks pass. No production or speech-state-machine change was needed.
The milestone/index now record C2 5/5, 10/20 overall, and 1/4 whole checkpoints.
Full integrated milestone acceptance remains open; nothing was deployed.
