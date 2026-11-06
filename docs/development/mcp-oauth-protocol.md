# Outbound MCP OAuth protocol

These protocol adapters implement the approved
[MCP 2025-11-25 authorization profile](https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization).
They prepare and validate OAuth exchanges. Durable attempts, session authorization,
encrypted storage, refresh coordination, runtime injection and the production UI
remain separate [milestone slices](../../labnotes/milestones/integrations-directory-and-tenant-mcps.md).

## Preparation and registration

Connect performs fresh resource and issuer discovery. Challenge scopes take
precedence over resource metadata scopes. Multiple advertised issuers require a
selection. Own client may use an explicit issuer only when protected-resource
metadata is missing; invalid, mismatched or unavailable metadata is not bypassed.
Credentialless discovery never registers a client or requests tokens.

Browser authorization requires authorization-code support, S256 and an advertised
issuer response parameter, plus an implemented client authentication method. An
unsupported method or signing algorithm cannot produce a usable suggestion.
The callback comes from the installation's configured
HTTPS origin, and the resource is the exact MCP endpoint. Authorization and token
endpoint query parameters are validated before managed registration side effects.

CIMD uses the installation-owned client metadata URL and public authentication.
It requires both CIMD support and the `none` token authentication method. An absent
methods field uses the RFC 8414 `client_secret_basic` default and cannot imply
public-client support. Discovery suggests DCR or Own client when CIMD is unusable.
The modal exposes no editable CIMD metadata or provider parameters.

DCR selects a supported `none`, `client_secret_basic` or `client_secret_post`
method. An optional initial registration token goes only to the registration
request. Request metadata includes selected scopes and only supported installation
grants: authorization code, plus refresh token when advertised. Empty scope is
omitted. The returned client must preserve the callback and chosen authentication;
issued secrets require a valid finite or non-expiring lifetime.

Explicit returned grant/response types must permit authorization code. Explicit
scope must be valid and include the selected scopes; a superset does not broaden
the subsequent authorization request. Missing grant/response fields use RFC 7591
defaults, and missing scope is tolerated for compatibility. This tolerance does
not make incomplete metadata echoes RFC-conformant. Scope is optional registration
metadata; sending selected scopes is this implementation's interoperability choice.
[RFC 7591](https://www.rfc-editor.org/rfc/rfc7591.html#section-3.2.1)

Saved DCR identity can be reused only when issuer, resource, callback and supported
authentication match, its secret remains usable, and saved scopes cover the newly
selected scopes. Missing scope evidence or new scopes require fresh registration.
An explicit initial token
requests fresh registration. Reuse does not reuse an old authorization state.

## Registered clients and grants

Own client supports public code flow, confidential code flow and explicit
confidential client credentials. Client authentication supports Basic, POST and
private-key JWT with an advertised supported algorithm and matching key. Machine
grants require explicit server support and have no browser callback, authorization
parameters or retained refresh token. Private-key assertions are freshly signed
for each token request and bound to the exact client and token endpoint.

Own-client endpoints must satisfy issuer endpoint policy. Literal provider
parameters and MCP headers are bounded and validated; they cannot replace managed
OAuth fields or transport/authentication headers. Inactive credentials and
parameters are rejected. Prepared structures hide secrets from inspection.

## Token and callback boundaries

Token grants use ExMCP's pinned, redirect-free SecureHTTP boundary with explicit
DNS, connection, request, header and body limits. Project code owns form/client
authentication and raw response validation because the higher-level dependency
parser supplies a missing token type. A successful response must explicitly name
Bearer, provide a token accepted by the project's Bearer transport and use valid
OAuth scope syntax. The 8,192-byte access-token limit is an implementation bound,
not a protocol limit. Errors are fixed codes; provider bodies and credentials are
not returned. Failed or ambiguous token requests are not retried here.
[RFC 6749](https://www.rfc-editor.org/rfc/rfc6749.html#section-5.1),
[RFC 6750](https://www.rfc-editor.org/rfc/rfc6750.html#section-2.1)

Callback parsing rejects duplicate parameters and ambiguous code/error responses.
Issuer comparison is exact before code redemption. The caller must claim bound,
single-use state and own the overall operation deadline; these modules do neither.

## Decisions and evidence

Trusting inferred Bearer type was rejected because it masks a missing required
field. Guessing public authentication from CIMD alone was rejected because it can
produce an unusable handoff. Global DCR grants/scopes were replaced with selected
flow metadata. Raw HTTPS was not reimplemented: ExMCP retains destination policy,
DNS pinning and HTTP limits. See the focused regressions and independent review in
[checkpoint labnotes](../../labnotes/20261107-0113-review-mcp-oauth.md).
