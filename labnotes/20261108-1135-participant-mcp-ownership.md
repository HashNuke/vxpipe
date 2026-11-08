# Participant MCP ownership

Date: 2026-11-08. Baseline: `abcd9db8` on `main`.

## Request and scope

Research and specify participant-owned outbound MCP sessions. The user expects
the participant/agent call tree to release its MCP resources when it stops.
Inbound platform MCP stays at application level. This task creates a new milestone
and decision; it does not implement runtime changes or approve the prior milestone.
The user has requested commit/push of repository changes and progress notifications.

## Research

- Traced Gateway `/mcp` and Console Gateway mounting separately from the outbound
  `vxpipe_mcp` application. They are different responsibilities and umbrella apps.
- Verified credential-only global lookup in `ConnectionKey`/`Connections`, the
  root connection supervisor, activation-local bindings and leases, and the lack
  of last-holder session closure. This sharing predates the latest directory work.
- Traced catalog loader/optional refresher, standalone checks and saved runtime
  credentials. Credential grants and durable refresh claims must stay shared;
  operation/client lifetimes must become explicit and independent.
- Read the locked ExMCP revision plus current tracked patch. Async POST uses
  unlinked `spawn_monitor`; Client has no `terminate/2`; explicit disconnect runs
  HTTP cleanup, with DELETE preceding SSE closure. BoundedClient uses a request-
  owned Mint socket. These source findings mean client relocation alone cannot
  establish the requested teardown guarantee. No runtime reproduction claimed.
- Read the official approved 2025-11-25 lifecycle, Streamable HTTP and cancellation
  documents, Elixir Supervisor docs and published ExMCP API docs. Kept the locked
  source authoritative over newer published package behavior.
- Found native STS descriptor construction supplies no remote owner and remote
  bindings reject that state. This ownership slice does not add STS MCP support.

## Decisions and tradeoffs

- Select activation-owned sessions with a fresh runtime incarnation. Stable
  participant IDs and credential identities are insufficient restart/session keys.
- Keep same-activation alias deduplication only with compatible pinned policy.
  Separate exact session close from grant-wide revoke.
- Preserve saved-disconnect in-flight behavior, current request authorization,
  no executor retry, durable renewal fencing and failure-domain boundaries.
- Propose one 1,000 ms graceful cleanup budget per activation, followed by forced
  local teardown with observed completion; network cleanup cannot reset the budget.
- Management/discovery gets bounded independent operation owners. Embedded API
  migration must be explicit; no silent global-sharing compatibility fallback.
- More sessions/initialization work and provider cap pressure are accepted costs;
  transfer overlap, lifecycle churn and measured counts/latency are acceptance gates.
- Explicitly distinguish local cleanup from already accepted remote side effects.

## Planning artifacts and verification

- Decision: `docs/development/participant-mcp-ownership.md`.
- Milestone: `labnotes/milestones/participant-owned-mcp-sessions.md`, with T1–T4,
  failure matrix, manual checks, dependency order and separate specification review.
- Independent Astra xhigh design/adversarial review and focused relative-link,
  checklist/index verification completed; see review corrections below.
- No code, dependency, UI, infrastructure or runtime behavior changed. Full runtime
  gates are deliberately reserved for implementation; this checkpoint needs
  documentation validation rather than claiming previously passed suites as evidence.

## Independent review follow-up

- Astra's source review identified two planning gaps, not newly reproduced bugs:
  global renewal tasks can outlive local descendants until runner DOWN processing,
  and binding/caller fencing does not cover queued/pre-submission transport work.
- Added operation-specific root-runner cancellation/termination acknowledgement,
  rejection of queued requests after owner retirement, and explicit final-submission
  fencing/quiescence. Added deterministic held-auth/DNS/queue release acceptance
  with no new tool POST or token exchange after retirement.
- Review also identified the optional refresher's sibling-supervised `async_nolink`
  job and direct catalog publication as ownership/fencing risks. T3 now requires
  coordinator-incarnation job ownership, hard-death cancellation and stale-publication
  rejection, with held-work kill/restart/release evidence. No runtime bug is claimed.
- Re-review caught inconsistent cleanup-token policy wording. Chose non-renewing
  current credential resolution for cleanup: if DELETE would require renewal,
  skip it. This keeps cancellation/DELETE as the only allowed session cleanup
  traffic and prevents retirement from starting a replacement token exchange.
- Relative links/headings, fences, 57-entry order/count (44 complete/13 incomplete),
  earlier prerequisites, unchanged existing milestone statuses/descriptions, and
  unchecked new implementation gates passed focused validation before this update.
- Final Astra xhigh re-review approved the planning checkpoint with no remaining
  design blocker. The proposed cleanup timing still needs implementation proof;
  implementation and the earlier directory workflow gate remain unchecked.

## Checkpoint validation

- `git diff --check` passed; new-file whitespace, final newline and code-fence
  checks passed separately while the files were untracked.
- All new relative links/heading targets resolve. The 57 ordered entries are
  contiguous, the new prerequisites precede it, delivery/retention follow it,
  and every existing milestone status and description is preserved.
- Only specification-review boxes are complete in the new milestone. Runtime
  tests, browser checks, benchmarks and deployments were not run for this
  documentation-only checkpoint and are not claimed by review approval.
