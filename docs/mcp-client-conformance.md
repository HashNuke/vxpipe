# MCP client conformance profile

Status: partial, pinned evidence for Milestone 10. This document does not claim blanket
MCP client certification.

## Pinned inputs

- Protocol: MCP `2025-11-25`, selected through ExMCP's `:legacy_only` profile.
- Client dependency: ExMCP `1.3.0`, locked by the umbrella.
- Official client harness: `@modelcontextprotocol/conformance@0.1.16`, tag commit
  `21a9a2febd7100d7c17ac1021ee7f2ed9f66a1e0`.
- Additional Everything server fixture: `@modelcontextprotocol/server-everything@2025.11.25`,
  tag commit `0155af3069fb6d593165037a28703cb3a595cf67` (interoperability run pending).

The harness version is invoked exactly by [the opt-in runner](../bin/test-mcp-conformance);
it is not a runtime application dependency. The runner uses `MIX_ENV=test` only to avoid
starting unrelated development voice-provider configuration. The task itself starts only
`:vxpipe_mcp` and its dependencies.

## Internal public API

- `Vxpipe.MCP.ConnectionKey.new/1` constructs the bounded resolved-integration and
  credential-generation identity.
- `Vxpipe.MCP.Connections.open/3`, `lookup/1`, and `close/1` own production HTTPS session
  lifecycle. `open_loopback_test/3` is a distinct loopback-only fixture entry and cannot be
  selected by a production configuration flag.
- `Vxpipe.MCP.Connection.client/1` gives the internal protocol handle to
  `Vxpipe.MCP.Discovery.discover/2` and `Vxpipe.MCP.Invocation.call/5`.
- Discovery returns a complete `Vxpipe.MCP.Catalog` or an error, never a partial catalog.
  Invocation accepts only a tool in that catalog and validates its arguments before the
  ExMCP request boundary.

Tenant lookup, credential resolution, enabled-tool selection, agent grants, call lifetime,
and model projection do not belong to this library. The later live-MCP milestone supplies
those inputs.

## Official client scenario matrix

Run date: 2026-09-09. The harness lists these scenarios for MCP `2025-11-25`.

| Scenario | Status | Evidence or boundary |
| --- | --- | --- |
| `initialize` | Pass | 1/1 scored check; exact revision and client metadata accepted. |
| `tools_call` | Pass | 1/1 scored check; initialized, listed `add_numbers`, then invoked it once. |
| `sse-retry` | Pending | Applicable to the approved recovery contract; not yet implemented in the driver. |
| `elicitation-sep1034-client-defaults` | Not applicable | Server-requested elicitation is explicitly outside this milestone. |
| `auth/metadata-default` | Not applicable | OAuth onboarding is deferred. |
| `auth/metadata-var1` | Not applicable | OAuth onboarding is deferred. |
| `auth/metadata-var2` | Not applicable | OAuth onboarding is deferred. |
| `auth/metadata-var3` | Not applicable | OAuth onboarding is deferred. |
| `auth/basic-cimd` | Not applicable | OAuth/CIMD onboarding is deferred. |
| `auth/scope-from-www-authenticate` | Not applicable | OAuth scope negotiation is deferred. |
| `auth/scope-from-scopes-supported` | Not applicable | OAuth scope negotiation is deferred. |
| `auth/scope-omitted-when-undefined` | Not applicable | OAuth scope negotiation is deferred. |
| `auth/scope-step-up` | Not applicable | OAuth scope negotiation is deferred. |
| `auth/scope-retry-limit` | Not applicable | OAuth scope negotiation is deferred. |
| `auth/token-endpoint-auth-basic` | Not applicable | OAuth token-endpoint authentication is deferred. |
| `auth/token-endpoint-auth-post` | Not applicable | OAuth token-endpoint authentication is deferred. |
| `auth/token-endpoint-auth-none` | Not applicable | OAuth token-endpoint authentication is deferred. |
| `auth/pre-registration` | Not applicable | OAuth client registration is deferred. |

## Reproduction

From the umbrella root:

```sh
bin/test-mcp-conformance
```

The harness creates a fresh loopback server per scenario and appends its URL to the Vxpipe
task. The Vxpipe task dispatches only the two supported scenario strings; any other value
fails explicitly.

## Open compatibility gate

ExMCP 1.3.0 and upstream `master` at `56880c6` read HTTP credential trust from the
application-global `:ex_mcp, :security` configuration rather than from each client. A global
union of tenant origins would weaken per-integration credential binding, so production
credentialed remote sessions remain blocked until this is resolved through a public
dependency boundary. The loopback conformance successes carry no credentialed-production
claim.
