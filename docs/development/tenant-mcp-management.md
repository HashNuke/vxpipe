# Tenant static MCP management

This checkpoint exposes custom static MCP connections and credentialless discovery
through Console's existing session/CSRF and tenant Services permission boundaries.
Native provider credentials, bindings, overrides and removal continue using their
existing Services operations. Listed MCP recipes, browser OAuth and production
modal acceptance remain separate [milestone gates](../../labnotes/milestones/integrations-directory-and-tenant-mcps.md).

## Operations and authority

`MCPConnections` owns principal authorization and current-authority checks. Console
adapts HTTP requests and supplies the real identity refresh function. Persistence
owns encrypted storage and generation comparison; the MCP application owns endpoint,
authentication, transport and catalog validation. No network check runs inside a
repository transaction.

All routes require a browser session and use private/no-store responses. Reads
require `tenant_services.read`; mutations and discovery require
`tenant_services.write` and CSRF. There are no platform MCP management routes.

| Route under `/api/tenants/:tenant` | Behavior |
| --- | --- |
| `GET /mcp-connections` | Connected public metadata and tool counts |
| `GET /mcp-connections/:id` | Public details and cached tools |
| `POST /mcp-discovery` | Credentialless endpoint/revision preflight |
| `POST /mcp-connections` | Validate fresh static input, check MCP, then create |
| `PATCH /mcp-connections/:id` | Replace at the observed generation, or refresh tools |
| `POST /mcp-connections/:id/reconnect` | Explicitly restore a revoked identity with fresh input |
| `DELETE /mcp-connections/:id` | Revoke at the observed generation and erase secrets |

Tenant existence and write authority are checked before probing. The same user and
session must still have current write authority after network work and before a
write. Failed checks never become anonymous connections. Discovery also rechecks
authority before returning its endpoint/revision-bound result.

## Replace, refresh and reconnect

Static input contains endpoint, method and credentials. Supported methods are none,
bearer, custom headers and Basic. Only active-method fields are accepted. For an
existing connected record, omitted credentials preserve the saved material only
when endpoint and method exactly match. A complete replacement first reads public
identity/generation metadata and does not decrypt the old payload. Missing old
keys or an unreadable old envelope therefore do not prevent a fresh replacement;
omitted-credential retention still requires successful decryption.

Tool refresh uses `{generation, refresh_tools: true}`. It resolves the current
credentials, validates the MCP and updates only server name/catalog at that
generation. It never rewrites credentials or increments configuration generation.
The repository preserves any independently rotated OAuth grant when that later
flow uses the same catalog update operation.

Revoked rows retain ID, namespace and endpoint identity but contain no credentials
or tools. Normal list/detail operations omit them. A duplicate create against a
revoked identity returns HTTP 409 with `mcp_reconnect_required`, `connection_id`
and the retained `generation`; it does not restore the row. The explicit reconnect
request supplies those identifiers and complete fresh credentials. It requires a
currently revoked record, unchanged endpoint/directory identity, successful MCP
validation and current write authority. Repository replacement uses the observed
generation, preserves ID/namespace and advances the generation. A concurrent
replacement or revocation makes the proposal stale.

The trusted repository's `get_retained` operation returns metadata without
decryption, including revoked records, scoped to the exact tenant. It is not a
public read endpoint. Reconnect never resolves or reuses revoked credentials.
Connected duplicates retain the existing `mcp_connection_exists` conflict. A
reconnect against a connected row returns `mcp_reconnect_not_required`.

## Public endpoints and secrets

The endpoint is public configuration stored outside the encrypted payload. Secrets
belong in credential fields. Before preflight or connection I/O, the shared
endpoint validator rejects recognized credential query names, including token,
access/refresh/ID/OAuth/API tokens, API keys, authorization, passwords, client
secrets, signatures, session identifiers and authorization codes. Checks normalize
case, percent encoding and punctuation in the complete name and its root before
any bracket suffix, including nonempty suffixes such as `token[0]`.
Malformed escapes and nested percent-encoded names are rejected. Both ampersand
and raw semicolon separators are checked. Nonsecret queries such as `region=eu`
and `api-version=2` retain their exact values and identity.

This policy recognizes parameter names; it cannot infer arbitrary secrets hidden
under unrelated names or in paths. Console additionally filters endpoint and
credentials from request logs. Public projections allowlist metadata and never
include credential maps. Resolved connection snapshots have opaque inspection.

## Decisions and verification

Silently creating a new row after revoke was rejected because it changes namespace
and bypasses retained identity conflicts. Silently restoring on create was rejected
because a reconnect must carry an observed generation. Resolving old ciphertext
before every update was rejected because it prevents repair with fresh credentials.
Static endpoint fixtures use the actual Console probe adapter with an injected
connection checker; OAuth fixtures/tests are separate to keep this slice runnable.

Tests cover read/write authority, deleted tenants, stale writes, masked retention,
fresh repair, reconnect proposals, secret-free results, endpoint-query rejection,
CSRF and static catalog refresh. Storage tests separately cover retained metadata,
namespace preservation and generation serialization. See
[checkpoint evidence](../../labnotes/20261107-0052-review-mcp-management.md).
