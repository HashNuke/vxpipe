# Explicit MCP hosts

## Change and rationale

Remove the transitional root connection pool now that calls and catalogs supply
explicit hosts. Missing owners fail closed, lookup requires the same host, and
close accepts only an exact handle. Local grant revocation still reaches every
host using that credential generation. Remove obsolete unscoped retirement/count
matching and the internal three-argument handle constructor. Independent checks
retain their existing supervision and registration; no replacement coordinator.

Migrate library fixtures and isolated Console node fixtures to explicit hosts.
The conformance/reference CLI clients use temporary caller-linked supervisors.
Their exact handles close before the hosts stop. Test helpers start hosts through
ExUnit; helpers invoked inside a task receive the host from the test process.

## Reproduction and verification

- Initial regression: opening without an owner unexpectedly succeeded. The
  focused test failed as expected (seed 160147), then the owned-session file
  passed 18 tests (seed 496349). Logs: `vxpipe-explicit-hosts-red.log` and
  `vxpipe-explicit-hosts-owned.log` in the temporary test output directory.
- Initial migrated core lane passed 42 tests, seed 23274. This includes identity
  churn in isolated BEAMs, telemetry, credentials and owner isolation.
- The broader lifecycle lane reproduced one fixture migration error: a task
  attempted `ExUnit.start_supervised!`. Pass the test-owned host into that helper;
  preserve the original cumulative SSE response-limit assertions.
- Both shipped CLI adapters still used the removed API. The official fixture
  lane reproduced all three failures before migration. Independent Astra probes
  also reproduced both adapter rejection and the helper's ExUnit context error.
- After both fixes, 104 MCP lifecycle, protocol, connection-check and official
  conformance/reference cases pass, seed 794191 (`vxpipe-explicit-hosts-wire.log`).
- Saved WebRTC, transfer, in-flight, boundary and phone plus cross-node runtime
  and renewal regression lanes pass 33 tests, seed 44771
  (`vxpipe-explicit-hosts-console.log`). Participant session ancestry/isolation
  passes 3 tests, seed 272031 (`vxpipe-explicit-hosts-call-engine.log`).
- Catalog loader and wire integration pass 17 tests, seed 897786
  (`vxpipe-explicit-hosts-catalog.log`).
- Root format, warnings-as-errors compilation, strict Credo and unused-dependency
  check pass. The full umbrella passes 5,057 tests with zero failures and 338
  excluded, seed 373187 (`vxpipe-explicit-hosts-root.log`).
- Independent GPT-6 Astra xhigh source re-review is clean after both reproduced
  fixes. Final exact 28-path staged review also approves the checkpoint with no
  outstanding findings. Renewal ownership and tenant catalog jobs remain
  separate pending checkpoints.

## Boundaries

No UI, saved IDs, tool selection or database migration changes. Trusted callers
must supply an owner for open/lookup and retain the handle for close. A rolling
mixed-version deployment must drain old-node sessions before claiming universal
participant ownership. The full milestone remains open.

## Commands

From `apps/vxpipe_mcp`, after the initial focused core run:

```sh
mix test test/integration test/vxpipe/mcp/wire_failure_test.exs test/vxpipe/mcp/wire_limit_test.exs test/vxpipe/mcp/owned_connections_test.exs test/vxpipe/mcp/connections_test.exs test/vxpipe/mcp/telemetry_test.exs --include integration
```

From `apps/vxpipe_console`:

```sh
mix test test/integration/saved_mcp_runtime_test.exs test/integration/saved_mcp_transfer_test.exs test/integration/saved_mcp_inflight_test.exs test/integration/saved_mcp_boundaries_test.exs test/integration/saved_mcp_telephony_test.exs test/integration/mcp_runtime_nodes_test.exs test/integration/mcp_renewal_nodes_test.exs --include integration
```

From `apps/vxpipe_call_engine`, run the participant session file and the catalog
loader/wire files recorded above with `--include integration`. The five standard
completion commands run from the umbrella root; no source-cutover, speech state
machine or UI changes require an additional Lean/browser lane.
