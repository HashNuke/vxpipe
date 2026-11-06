# Review MCP OAuth flow

- Protocol and durable-storage checkpoints committed independently as `d3fb8c6d`
  and `0086e6bf`. Reviewing browser start/callback orchestration before staging it.
- Known remaining workflow requirements: failed callbacks currently return JSON
  without trusted return context; revoked retained identities cannot start OAuth
  reconnect; listed template identity remains a later requirement.
- Proposed callback recovery uses only context from a successfully claimed attempt,
  rechecks current authority/installation on errors as well as success, and returns
  fixed failure/denial status plus an opaque attempt ID to the same tenant view.
  Malformed or unclaimed state and current-authority failures remain bare errors.
  UI draft recovery must retain only nonsecret fields and match the returned attempt.
- Source review additionally identified missing composed callback admission/deadline
  and cancellation, and expiry computed after slow MCP validation. Per-request HTTP
  limits exist, but do not establish the whole-operation contract. Token lifetime
  must be anchored to reception or conservatively before exchange, not after tools
  discovery. Fixes require held-I/O and controlled-time regressions before staging.
- A controlled-clock expiry regression failed, then passed after anchoring expiry
  conservatively before token exchange. Six completion tests pass. The separate
  callback boundary regression reproduced missing capacity rejection and timeouts
  at held DNS, token HTTP and MCP checks (seven tests, four failures).
- Added a dedicated supervised completion runner using the existing bounded job
  implementation, with eight slots, fifteen-second lifetime and no tenant cooldown.
  Admission precedes code redemption but follows authenticated one-time state claim.
  This keeps claimed context available to Calls for bounded failure recovery; busy
  or timed-out completion requires a fresh authorization attempt. No one-shot code
  is redeemed on capacity rejection. Caller-death cases also cover worker cleanup.
  All thirteen completion/boundary cases pass. A queued successful completion
  released after the runner deadline returns the trusted failure redirect, persists
  no connection, and leaves the durable attempt consumed. The registered runner
  restart test retires its task supervisor, completion and nested I/O workers and
  accepts fresh work afterward.

- Claimed failures now return fixed status and bound attempt ID only after fresh
  authority/installation checks. Preclaim errors remain bare. Redirects preserve
  the authenticated tenant category/search/cursor and ignore attacker query fields.
  The red recovery test had three failures; all thirteen endpoint/return tests passed.
- Reconnect uses public retained metadata before optional DCR registration reuse.
  Static/revoked records retain identity, namespace and directory binding with new
  credentials; missing old keys permit fresh registration. The red fixture tests
  had three failures; all twenty-three Calls attempt/reconnect cases then passed.
- Split browser and runtime-renewal tests around a shared local HTTP/database case
  template so the browser commit has no dependency on later runtime orchestration.
  The combined split group passes thirty tests. The browser lane has eight tagged
  cases; runtime renewal remains a separate, uncommitted checkpoint.
- Independent adversarial source re-review reports no new blocker and accepts
  claim-before-admission with its documented fresh-attempt policy. It requested
  stronger registered-supervisor restart evidence, now passing. Final exact-index
  review of all thirty-eight files reports no blocker, including the milestone
  index update. Format, warnings-as-errors compile, strict Credo, unused dependency
  check and the full umbrella suite pass: 4,875 tests, zero failures, 190 excluded
  (seed 531640). This full-worktree gate includes later uncommitted work; staged
  independence was checked separately by source review. No rendered UI or external
  provider interoperability claim is made by this backend checkpoint.
