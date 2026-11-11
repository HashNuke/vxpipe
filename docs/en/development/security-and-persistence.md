---
title: Identity, persistence and security boundaries
description: Authorization, encrypted records, OAuth ownership and safe request boundaries.
sidebar:
  order: 6
---

## Authority and transactions

Identity owns account/role policy; Calls owns tenant resources and call workflows.
Persistence implements their ports, constraints and transaction boundaries.
Authenticate the actor, resolve the real resource tenant, then authorize the
operation. User-supplied IDs and cached browser permission state confer no authority.

Mutations revalidate relevant authority inside the transaction. A role change
checks both the current and requested account category; an Admin cannot demote
another Admin and then manage that account as an ordinary user. The final enabled
Superadmin remains protected. Ordinary role grants come from a fixed permission
catalog; strings, prefixes and wildcard matches cannot invent authority.

Tenant assignments cap assigned-scope grants. Built-in operational access and
privileged account-management permissions remain distinct. API-key issuance must
not delegate more authority than its issuer possesses.

Database transactions never wait for provider network work. Long operations
read validated identity/generation, perform bounded I/O, then conditionally commit
against current authority and the observed generation. Stale results fail closed.

## Credential domains

| Credential | Where it is used |
| --- | --- |
| Browser session | Console login and authorized session-only product operations. |
| Vxpipe API key | External product HTTP operations within its explicit scopes. |
| Participant join token | One scoped call admission. |
| Inbound OAuth grant | External client access to Vxpipe platform MCP. |
| Provider credential | Vxpipe's request to an AI/speech/carrier provider. |
| Outbound MCP grant | One tenant connection's authorization on an external MCP. |

Do not substitute one for another. An Authorization header never falls back to a
browser session. `/mcp` rejects static Vxpipe keys. Browser account revocation does
not retroactively terminate admitted calls or rotate independently issued keys.

Passwords use Argon2. Opaque browser tokens and API keys are stored as digests;
public IDs and masked hints are separate metadata. Setup/recovery proofs are
single-use, expiring secrets. Authentication attempts use database-backed limits;
required-store failures do not grant access. Browser mutations retain CSRF and
origin checks.

## Encryption at rest

Provider and outbound MCP secrets use the installation keyring with OTP
AES-256-GCM, fresh nonces and authenticated identity metadata. The envelope is
bound to its purpose, owner, record identity and relevant version/configuration
fields. Copying ciphertext to another tenant or changing authenticated identity
does not create a usable secret.

Key IDs are immutable; key material lives outside PostgreSQL. Reads of inventories
use safe metadata without decrypting all rows. Private structs redact inspection,
and sensitive queries disable SQL logging/query telemetry that could contain
parameters or results. Supervisor child arguments also need nonsecret handles:
custom `Inspect` alone cannot sanitize an OTP crash report's raw arguments.

Provider inheritance is by exact provider/name: an existing tenant record wins,
including an invalid/unreadable one. Only absence permits the allowed platform
binding. MCP connections have a non-null tenant owner and no platform fallback.

See [Operations](../usage/operations.md#rotate-the-installation-encryption-key)
for coordinated key rotation across provider records, MCP grants and pending
authorization attempts. Re-encryption must not change the external credential.

## Inbound platform MCP OAuth

Gateway/ExMCP own the MCP protocol boundary. Boruta processes OAuth through
Identity/Persistence adapters; Console owns login and consent. The approved
profile uses public-client authorization code, PKCE S256, CIMD, bounded DCR and
rotating refresh credentials. It is not a general OIDC identity-provider product.

Discovery and challenges use the configured Installation URL and resource
audience. Redirects match registered values, allowing native loopback ports to
vary during authorization. Consent delegates the user's
current permissions and tenant scope; every invocation rechecks authorization.
Revocation prevents continued access even through an existing MCP session.
HTTP API keys and participant admission tokens remain separate.

See [Platform MCP client identification](platform-mcp-clients.md) for CIMD
retrieval, metadata caching and the public-client profile.

## Outbound MCP OAuth

Protocol preparation performs fresh protected-resource/issuer discovery and
validates supported endpoints, issuer, resource, client method and S256 before
starting an authorization attempt. Credentialless preflight never registers a
client or obtains tokens. Invalid/mismatched metadata is not equivalent to missing
metadata and cannot trigger a permissive fallback.

CIMD uses the installation's HTTPS client metadata URL and supported public-client
authentication. DCR performs bounded registration when advertised. Own-client
configuration supplies the supported pre-registered identity. Custom machine
grants require advertised client-credentials support and an implemented confidential
client method; listed recipes may impose a narrower authorization-code flow.

Attempts are encrypted, short-lived and bound to user/session, tenant, draft,
connection generation, installation revision, issuer, callback and resource.
State is stored as a digest. Console's shared callback locates the attempt for the
same browser identity, rechecks authority, claims it once and exchanges the code
without automatic replay. It initializes the MCP and discovers tools before a
conditional save. A failed replacement preserves the working connection.

This durable attempt store supports callbacks on another application instance.
A node-local OAuth listener/transaction registry would not provide that property.
Only nonsecret matching draft context returns to the browser after cancellation
or failure; provider tokens and PKCE material stay server-side.

## Renewal and request credentials

Grant generation/configuration identity is separate from ordinary access-token
revision. Normal renewal must not change selected tool identity. A durable claim
coordinates refresh-token rotation across callers/nodes; commit accepts only the
matching claim and grant revision. An uncertain token exchange retains an ambiguity
fence rather than retrying a potentially consumed token.

Machine grants reacquire access through their configured client method; an
unexpected returned refresh token is not adopted as a delegated grant.
Disconnect/replacement fences old renewal results and erases usable secrets.

Each outbound MCP HTTP operation resolves current headers against the pinned
tenant, connection, generation, endpoint and method. Sessions keep nonsecret
resolver descriptors, not a bootstrap token snapshot in supervisor arguments.
OAuth renewal never opens browser consent from a call request, and a challenge
does not authorize automatic replay of a submitted tool.

## Network and data boundaries

Endpoint validation retains meaningful MCP paths and nonsecret query values.
Recognized credential query names, userinfo and invalid encodings are rejected;
operators still must not hide secrets under arbitrary path/query names.
Discovery, redirect and resource fetching enforce their bounded public-destination
policy. A tenant-supplied URL is not authority to access local infrastructure.

Provider transports keep headers and buffered payloads out of routine status and
telemetry. The owned Mint/WebSocket path avoids dependency telemetry that exposed
connection credentials; filtering one subscriber would leave other subscribers
exposed. Raw protocol evidence is private unless explicitly projected safely.

The Installation URL uses a bounded per-node ETS cache, not request Host headers.
Expired unavailable state is not silently served forever. The editor reads the
authoritative revision; local writes invalidate cached origin state. Explicit
deployment overrides and accepted carrier-leg snapshots retain their own owners.

## Verification

Test denied cross-tenant reads/writes, privilege-category changes, stale generations,
revocation during I/O, authenticated ciphertext binding and actual request-header
selection. Independent-node OAuth tests cover callback/renewal coordination;
they do not prove that live call rooms migrate across nodes. See
[Testing and verification](testing.md) for protocol and application lanes.
