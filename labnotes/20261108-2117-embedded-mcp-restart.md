# Embedded MCP restart sources

## Confirmed gap and scope

Independent GPT-6 Astra xhigh source review found that RuntimeGraph retains the
complete IntegrationCatalog in the permanent IntegrationOwner child specification.
CallEngine.runtime_options replaces the original CatalogStore reference with its
snapshot. Embedded client configuration can therefore survive in retained terms;
Inspect redaction does not remove it.

A temporary probe reused the existing live-call fixture and an actual host-owned
CatalogStore, started a prepared room, and obtained the activation owner's saved
child specification with `:supervisor.get_childspec/2`. Searching its raw serialized
term found a synthetic credential marker. The expected regression fails once,
seed 141376 (`vxpipe-embedded-mcp-restart-red.log`). An earlier probe failed only
because it used a nonexistent Elixir Supervisor wrapper; that result is not
behavioral evidence. No production change preceded the valid reproduction.

## Next coherent checkpoint

Preserve the existing private catalog source through room/participant retained
options and resolve exact pinned integrations inside the existing bounded
initializer on each start and recovery. Keep the saved runtime resolver descriptors,
RoomAuthority's budgets, and current restart limits. Do not introduce another
coordinator, credential service, or resolver closure containing the private snapshot.
Define the existing inline embedded-catalog migration explicitly; a source change
or unavailable store must fail closed instead of using a stale private snapshot.

Reuse the current ancestry, two-call isolation, alias/pin/native-only, recovery,
saved/embedded execution and STS-rejection lanes. Add narrow assertions only for
missing source/privacy/recovery contracts. The preceding renewal checkpoint was
reviewed and pushed as `ce27f0d9` before production implementation here began.

## Reviewed source contract

The bounded follow-up review recommends `IntegrationCatalog.restart_source/1`:
retain a host store reference, or accept the existing closed saved-descriptor
catalog shape. Inline client options contain only endpoint, authentication `:none`,
and a RuntimeAuthProvider with no bound session. A narrow MCP-owned predicate
validates that provider and its resolver context (`:configured`, PID, reference,
or tuples of PIDs/references), matching Calls' existing nonsecret grammar.
Ordinary RuntimeAuthProvider initialization remains unchanged for standalone use.

Private inline callers migrate to an existing host-owned CatalogStore, started
empty and then published so its own saved child specification is also nonsecret.
No plain safe flag, arbitrary callback closure or generic secret scanning is
needed. Carry the reference through runtime options, RoomAuthority's retained
transfer startup options, participant specs and activation specs; changing only
IntegrationOwner would leave upstream copies. Resolve and check exact pins inside
the existing bounded initializer, sharing its original deadline across resolution
and opening. Credential leases must remain owned by the binding process rather
than a temporary resolution worker.

## Implementation evidence

- The canonical live-call tests reproduce retained private state and stale recovery
  after source replacement/removal: three expected failures, seed 486626. Recovery
  tests admit the caller first; before that correction they tested an uncommitted
  activation that could not recover regardless of the source.
- Descriptor validation first failed one new MCP test, seed 656527; the closed
  catalog source boundary failed two tests, seed 667000. Both were implemented
  only after their red checks.
- Runtime options now retain the validated source through existing room/participant
  fields. Plan startup validates pins without retaining the snapshot. The owner
  resolves it inside its existing initialization task, then acquires leases itself
  and opens selected clients using the same deadline. No new process type or queue.
- Private inline fixtures were migrated to existing host-owned stores. The source
  migration run first reported ten old-owner failures among thirteen tests,
  seed 599837. The migrated Call Engine owner/catalog/agent/invocation/real-wire lane
  passes all 84 tests, seed 993503. The initial three regressions pass, seed 956485.
- MCP authentication checks pass thirteen tests, six integration cases excluded,
  seed 346977. Saved runtime/transfer/in-flight/boundary/phone acceptance passes
  all 22 tests, seed 154185. The held source-lookup test passes, seed 373188,
  proving the original 500 ms initialization budget cancels the lookup worker
  and resuming the source cannot trigger a later client open.
- Final source review, remaining T2 acceptance consolidation and root gates are
  pending. No additional milestone item is checked by intermediate evidence.

## Review and final focused verification

Independent Astra review reproduced a malformed-descriptor regression: provider
initialization rejects invalid fields with a credential exit, so the new predicate
could exit instead of returning false. Owner-app regressions independently reproduce
the issue: one failure among fourteen MCP tests, seed 180028, and one among two
catalog-source tests, seed 790431. The predicate now converts only that existing
credential-rejection exit to false. Ordinary provider initialization is unchanged.

The final combined Call Engine lane passes 101 tests, seed 363273. It includes the
held lookup deadline, explicit same-activation alias sharing, conflicting deadline
and response-limit rejection before opening, native graph behavior and native STS
missing-owner rejection. All twenty authentication-provider cases, including the
tagged transport lane and malformed-descriptor regression, pass with seed 749225.
Saved-call compatibility remains the 22-test green run recorded above.

The reviewer assessed all four remaining T2 items against these cases and existing
participant real-wire, committed recovery, stale-handle, saved WebRTC/phone and
native-only storage evidence. That supports completing T2 after final gates, without
a new coordinator or provider path. Final source re-review is approved with no
outstanding valid findings; the reviewer's two exact reproductions pass with seeds
932375 and 642067. Root format, warnings-as-errors compile, strict Credo and unused
dependency checks pass. The full umbrella run passes 5,077 tests with zero failures and 344 excluded,
seed 296639. All five root gates are now green on the final source. The remaining
four T2 items are checked, bringing implementation to 14 of 29; full-milestone
T3/T3b/T4 requirements remain separate.

The full test process completed successfully (exit 0). No production or test source
changed during that run. Only documentation was updated afterward. The next catalog
checkpoint has a separate labnote and temporary red tests; neither is part of this
staged embedded-restart checkpoint.
