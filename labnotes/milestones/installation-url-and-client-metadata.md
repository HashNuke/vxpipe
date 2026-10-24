# Installation URL and MCP client metadata

Prerequisites: [Console authentication](console-authentication-and-user-management.md),
[MCP OAuth](mcp-oauth.md) and the reviewed
[Installation URL stories](../../docs/development/installation-url-storybook.md).
Contract: [Installation URL](../../docs/installation-url.md).

Runnable slice: persisted first-run URL/account setup and Superadmin settings,
public CIMD/DCR metadata foundation and current-origin telephony/MCP consumers.
Complete outbound OAuth is explicitly outside this slice.

Status: implemented and locally verified, 2026-10-24. Included in the Installation
URL backend/cache checkpoint; not deployed.
The approved cache follow-up below is also implemented and verified.

## Design review

Ownership and prerequisite order reviewed separately from implementation. Identity
owns setting policy, Persistence owns atomic storage, Console owns session routes,
MCP owns outbound metadata, Gateway consumes an injected read port. Existing
inbound OAuth and retained telephony service snapshots are prerequisites. Explicit
overrides and unconfigured-upgrade fallback remain; storage errors fail closed.
No listener reconfiguration, external redirect rewriting or token migration.

## Implementation and acceptance

- [x] Red/green normalization and atomic URL/account setup.
- [x] Superadmin settings with revisions, session revocation and atomic audit.
- [x] Real Console setup/settings integration and navigation.
- [x] CIMD endpoint and reusable DCR metadata, without an outbound OAuth flow.
- [x] Dynamic telephony callbacks/media/signature context and Console links.
- [x] Dynamic MCP discovery, audience, protocol admission and browser consent.
- [x] Preserve deployment overrides and accepted telephony leg snapshots.
- [x] Render desktop/mobile confirmation and production setup wizard.
- [x] Run root completion checks, resolve failures, and record passing owning-suite reruns.

Evidence: [checkpoint labnote](../20261024-2034-installation-url-backend.md).

## ETS cache follow-up

Design review: a per-instance cache preserves the existing public accessor and
dependency direction. Persistence starts it after Repo, Identity owns the optional
cache API, and consumers remain unchanged. A 30-second TTL bounds cross-instance
staleness without a new service. Local invalidation follows successful repository
writes; asynchronous loads never publish an uncommitted return value and cannot
overwrite a subsequent invalidation. Loader failures are distinct from missing
configuration. No changes to UI, deployment origins or MCP route ownership.

- [x] Red/green repeated/nil reads, concurrent misses, invalidation races and expiry.
- [x] Bound refresh tasks, waiting callers and outage retry; verify loader/owner cleanup.
- [x] Verify independent-instance refresh and real-store setup/save invalidation.
- [x] Compose the cache after Repo and inject it through runtime configuration.
- [x] Update the durable URL/cache contract and checkpoint labnotes.
- [x] Run root verification gates and confirm all application suites pass, including a same-seed Call Engine rerun after an initial unrelated deadline timing failure.

Evidence: [cache labnote](../20261024-2246-installation-url-cache.md).
