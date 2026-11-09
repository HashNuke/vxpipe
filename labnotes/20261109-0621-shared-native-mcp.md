# Shared native MCP

## Starting point

C1 dispatch checkpoint `f02b4524` is committed and pushed. The milestone has 3/20
completed tasks. The user explicitly requires removing superseded paths rather
than keeping pre-launch compatibility. No deployment is authorized.

## Reproductions and current work

- Added a compiled native-room MCP alias/teardown test. It fails at startup with
  unsupported STS configuration because schema compilation has no MCP owner:
  1 failure, seed `418589`. The implemented native round trip is now green.
- Added a deferred IntegrationOwner initialization test. Existing initialization
  rejected the new mode (1 failure, seed `69077`). After extracting the existing
  initialization body and adding deferred continuation, all 13 owner tests pass.
  The test handles the room-budget query after start_supervised returns, gates
  the connection, and verifies an exact-owner ready notification after release.
  Text initialization remains synchronous because its existing activation/recovery
  lifecycle depends on completing initialization before supervisor startup returns.
- Added shared schema projection independent of executable MCP ownership. The
  initial test failed because project/2 did not exist. An initial attempt to use
  nil-bound ToolDescriptors was rejected by their existing binding invariant;
  that approach was replaced with metadata-only ToolDescriptor.project/1 using
  the same name/description/schema validators as executable descriptors. No fake
  owner or executable placeholder registry is created. All 7 ToolDescriptors
  tests now pass (seed `360724`). Abstract AgentRuntime regression checks also pass: 108 tests, 0 failures,
  8 excluded (seed `493337`).

## Reviewed startup direction

Read-only GPT-6 Astra xhigh design review favors deferred owner initialization
inside the existing native allocation tree. Moving the entire allocation to a
new preparation task would add pending-allocation state and stale-result cleanup;
entry preparation finishes before the source/output sink is available. Reuse the
existing owner initialization, catalog source, credential leases and deadline
rollback. Share only owner/session child construction with text activation; keep
text recovery policy and native temporary/significant child semantics.

The native tree currently starts synchronously from RoomAuthority. IntegrationOwner
queries that room for its budget, so simply adding synchronous owner startup would
create a cyclic wait. Deferred initialization releases supervisor startup while
network work stays bounded in the existing owner initialization machinery.

Executable registries must be bound to the actual returned owner PID after tree
startup, before input admission. Provider configuration receives only validated
schema metadata. Do not use activation-name aliases or fake handles as executable
owners. Thread activation and MCP options explicitly through RoomCapabilitySupervisor,
whose existing whitelist currently drops activation_id.

Readiness dependency queries must run outside capability callbacks, following
AgentRuntime.Readiness. Include the MCP owner resource/generation in the captured
readiness signature. Initial StartupProbe alone is insufficient: OriginRecovery
currently releases replacement input on provider-ready. Both initial and recovered
input must await provider and MCP readiness. Proposed minimal gate: exact-owner
readiness notification to the existing room; provider_ready?/tools_ready? on its
current capability binding; validate the owner PID and activation before setting
the gate. Early notifications queue while lightweight tree startup returns. This
refinement was independently reviewed and is now implemented.

Do not retain the original entry-preparation Task PID, which is dead by attachment.
Use the live allocation/room owner with the original absolute startup deadline.
Recovery needs a separately authorized bounded budget; the proposed bound reuses
application call_lifecycle readiness_timeout_ms. Never reset an initial or transfer
deadline for each selected integration.

## Remaining proof obligations

Prove gated initialization leaves room/capability control responsive and input
closed; provider-first and MCP-first readiness; recovery gating; exact owner PID
replacement; shared deadlines across two integrations; partial rollback, expiry,
owner loss and cancellation; independent simultaneous calls/tenants; unchanged text
recovery; no MCP children without selection; provider metadata privacy; ready-graph
binding validation. Keep the native round-trip test red until the real integration
works. Run the Lean lane when source/recovery readiness transitions change.

The design review found that native capability monitoring previously started only
in prepare_input, leaving deferred initialization/recovery loss unobserved. A
focused test reproduced the missing monitor (1 failure); binding now monitors the
returned capability immediately and input preparation retains that same monitor.
The monitor and shared child construction are now implemented, with the failure
handling and verification below.

Final design review also requires order-independent/idempotent provider/tools
notifications, exact current owner PID plus installed-registry checks, and
post-start binding rollback. Check deadlines again when admitting readiness:
initialization can finish before its notification is handled. An already-ready
room's replacement allocation needs its own bounded watchdog if either readiness
signal never arrives; the initial call startup watchdog no longer protects it.
No fake owner handles or activation-name rebinding should be introduced.

## Implemented ownership checkpoint

Both text and native activations use `RemoteMCP.Activation.children/1` to construct
the existing IntegrationOwner and session DynamicSupervisor. The native tree
keeps its temporary/significant semantics; the text tree keeps its established
restart policy. Native startup projects schemas first, then installs an executable
ToolRegistry pinned to the exact new owner PID. Provider metadata contains no
executable owner or credentials. No provider implementation changed.

Readiness queries the owner outside the capability GenServer. The room waits for
both exact-allocation notifications before preparing input; either order and
duplicates are covered. Initial startup uses the original absolute deadline;
recovery uses the existing application readiness timeout with an owned timer.
The existing shared initializer still bounds catalog reads and all selected
connections together and rolls back partial startup.

The independent reviewer identified loss of the recovery watchdog when a starting
allocation died. Five focused failures reproduced late-ready silent rooms,
pre-ready owner/provider loss, premature timeout acceptance and an uncancelled
timer. Readiness now returns an explicit result to the existing StartupReadiness
failure boundary; current pre-ready DOWN/unavailable is terminal. Established
transfer-source retirement still demonitor/flushes before tree teardown. Stale
events do not terminate a replacement allocation. A real-room gated recovery test
confirms owner loss removes the room, capability and initializer.

A capture-log test reproduced deferred initialization options appearing in crash
logs. The owner now uses the project's existing format_status redaction pattern;
all 14 owner tests pass. No actual credentials were used in the reproduction.

The native compiled-room tests now cover the MCP alias round trip, provider-first
and tools-first readiness, responsive room/capability control, call end during
initialization, simultaneous isolated calls, distinct tenant scopes, stale pins,
credential revocation during an invocation, catalog publication independent of
call lifetime, and successful/failed transfer using the existing duplex fixture.
The fake protocol rejects discovery, so passing invocations also prove there is
no per-invocation catalog rediscovery.

An additional ordinary-Morse transfer experiment reproduced two completion
failures: committed transfer retained its source, and failed transfer lost its
tool outcome after speech cancellation. These are C3's existing interrupted
completion-association gap. The C2 transfer fixture uses the already-supported
duplex session; this is not evidence that ordinary/duplex parity is complete.
C2's full transfer-lifetime task remains unchecked until this is resolved, and C4
must run both fixtures without skips. The next reproduction can use the native
MCP room transfer cases with `native_model: "morse"`.

Focused native/text startup, owner, catalog-budget and transfer regressions:
**116 tests, 0 failures, 8 excluded**, seed `961998`. AgentRuntime's earlier
108-test lane remains the schema-validation evidence. Formatting,
warnings-as-errors compilation and strict Credo pass. Complete root-suite and Lean
results are recorded below. No deployment occurred.

GPT-6 Astra xhigh reviewed the implementation, validated the minimal explicit
failure fix, and found no remaining correctness issues. It confirmed that an
additional scan of every registry binding on readiness would be redundant: the
registry and owner are installed atomically before queued events, and that owner
cannot restart within the temporary native allocation. A stale return spec was
corrected. Final source, test, documentation and progress-count review is approved
with no actionable findings.

All five root completion checks pass for this checkpoint: formatting,
warnings-as-errors compilation, strict Credo, unused dependencies, and **5,129
tests, 0 failures, 371 excluded**, seed `401568`. The Lean build, oracle drift
check and Elixir replay pass (1 conformance test, seed `497304`). The 6/20 checked
tasks and 14 unchecked tasks agree with the index; all local documentation links
resolve. Draft tests for the next completion-settlement checkpoint were prepared
after the Call Engine portion of this run and are not part of this commit or its
test count. No deployment occurred.
