# Credentialless MCP discovery

URL entry starts a bounded backend preflight. It performs two discovery stages,
not a fixed two HTTP requests: protected-resource discovery identifies the
authorization server, then OAuth/OIDC metadata discovery identifies its endpoints
and capabilities. Well-known fallbacks and permitted redirects can require more
requests. Storybook models these outcomes with fixtures. Production HTTP routing,
permissions and modal acceptance remain separate gates in the
[Integrations milestone](../../labnotes/milestones/integrations-directory-and-tenant-mcps.md).

## Discovery and selection

`ResourceMetadata` probes the supplied HTTPS MCP endpoint. A Bearer challenge's
`resource_metadata` URL takes precedence. Without that parameter, it tries
`/.well-known/oauth-protected-resource` with the endpoint path, then the origin
root path. The returned resource must exactly equal the requested endpoint.
Authorization-server identities are bounded, distinct HTTPS URLs without query,
fragment or userinfo. Multiple issuers require explicit selection; a supplied
selection must be advertised.

`OAuthMetadata` tries OAuth authorization-server metadata with the issuer path
inserted after its well-known prefix, then OIDC insertion, then OIDC appending.
It validates the exact issuer, endpoint policy and all retained capability fields.
A malformed document is terminal; discovery does not skip it to find a more
permissive document. Only the allowlisted metadata fields cross the result boundary.

Absent resource metadata alone never establishes anonymous access. Without an
explicit issuer, `Preflight` uses the transient
[connection checker](mcp-connection-checks.md) to initialize anonymously and read
the tool catalog. Only a successful check suggests no authentication. With a valid
explicit issuer, missing resource metadata permits issuer discovery for Own-client
configuration. This fallback cannot override invalid, mismatched or unavailable
resource metadata, and does not suggest CIMD/DCR. Supplied issuer input is validated
before any discovery I/O; invalid input returns a fixed error.

Successful results retain the caller's endpoint and revision. Other outcomes
distinguish issuer choice, incomplete issuer metadata, unsupported OAuth capabilities
and unknown connectivity. They do not register clients, request tokens, invoke
tools or save tenant connections.

## Capability and challenge contracts

`OAuthCapabilities` owns pure validation shared by discovery and later OAuth
construction/signing code. Browser authorization requires code, S256 and advertised
issuer-response protection for the installation's shared callback. Machine grants
require explicit client-credentials support and an implemented confidential client
method. Private-key JWT requires advertised RS256, PS256 or ES256 support; discovery
does not supply an algorithm default. A token-only server is accepted when its
explicit grants exclude browser authorization.

Retained capability arrays contain at most 32 nonempty strings of at most 256
bytes. Scope arrays contain at most 64 RFC 6749 scope tokens of at most 256 bytes.
CIMD and issuer-response flags must be booleans. JWT methods require a nonempty,
bounded signing-algorithm array. These sizes are installation limits, not new
protocol requirements.

The pinned cowlib parser handles challenge parameters but rejects permitted
whitespace around `=` and bare Bearer schemes. `AuthenticationChallenge` normalizes
only unquoted separator whitespace and recognizes bare Bearer challenges at
unquoted comma boundaries. Quoted/escaped content is preserved; it does not invent
parameters for a bare scheme. Cowlib still parses parameter syntax. Duplicate
parameters, multiple Bearer challenges and invalid scope tokens are rejected.
Challenge scopes take precedence over advertised resource scopes.

## Ownership and limits

`PreflightRunner` admits at most eight active operations, with a 15-second budget
from admission, a 500 ms per-tenant start interval and at most 1,024 recent tenant
entries. A completed task is accepted only before its recorded deadline, even if
its result was queued earlier. Expiry and caller death retire the operation task.
The application owns the task supervisor and runner in a one-for-all subtree, so
runner restart also retires its active tasks. The public call uses a separate
20-second caller budget; scheduler delay and cleanup mean these are not a hard
wall-clock response guarantee.

`DiscoveryIO` binds the dependency's separately spawned DNS/HTTP callbacks to the
preflight owner. Owner death kills held I/O. Callback exceptions, throws and exits
are normalized inside the callback worker before they can become raw OTP reports.
The default dependency HTTP adapter already handles its own failures; the added
regression demonstrates an injected-callback boundary, not a remote secret leak.

Metadata fetches use the pinned ExMCP destination validation, full DNS-answer
validation and address pinning. Fetch options are fixed: HTTPS, no insecure loopback,
no cross-origin redirects, at most two redirects, 64 KiB per response and 128 KiB
per fetch traversal; DNS/connect/request phase budgets are one/two/three seconds.
Those byte budgets apply to each fetch traversal, not the entire preflight. The
runner bounds the composed operation. Request input cannot inject transport
callbacks, policies or credentials.

## Decisions and evidence

Reusing the dependency's credential-acquiring discovery flow was rejected because
preflight must remain read-only. Reusing its metadata fetcher retains its transport
policy without token acquisition. Capability predicates live outside authorization
construction/signing so this foundation can compile independently. A small parser
compatibility layer preserves the pinned parser instead of replacing its grammar.

Focused tests cover fallback order, exact identities, selection, metadata bounds,
scope grammar, challenge compatibility, manual fallback, late completion, callback
failure redaction and composed DNS/HTTP cancellation. Runner restart is tested in
the isolated test BEAM. See [checkpoint evidence](../../labnotes/20261107-0031-review-mcp-discovery.md).

Protocol references: [approved MCP authorization profile](https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization),
[HTTP authentication grammar](https://www.rfc-editor.org/rfc/rfc9110.html#section-11.2),
[OAuth scope grammar](https://www.rfc-editor.org/rfc/rfc6749.html#section-3.3) and
[authorization-server metadata](https://www.rfc-editor.org/rfc/rfc8414.html#section-2).
