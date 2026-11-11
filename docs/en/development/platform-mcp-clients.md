---
title: Platform MCP client identification
description: CIMD discovery, client metadata caching and OAuth client identity.
sidebar:
  hidden: true
---

## Decision

The platform MCP accepts public OAuth clients using either a Client ID Metadata
Document (CIMD) URL or dynamic client registration (DCR). Both use the existing
browser consent, PKCE S256, resource binding, token rotation and revocation flow.
This is inbound access to Vxpipe, separate from tenant MCP connections used by
participants during calls.

The protocol remains MCP 2025-11-25. Its [authorization profile](https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization#client-id-metadata-documents)
recommends CIMD. The [CIMD draft](https://datatracker.ietf.org/doc/html/draft-ietf-oauth-client-id-metadata-document-00)
defines URL-based client identifiers. We also return `iss` on approval and denial,
and advertise issuer identification according to [RFC 9207](https://www.rfc-editor.org/rfc/rfc9207.html).

## Identity and validation

A CIMD client ID is an exact HTTPS URL with a non-root path. Userinfo, query,
fragment and dot segments are rejected. The fetched JSON must repeat that exact
identifier and provide a client name and supported redirect URIs. Public-client
authentication is `none`; shared secrets, client assertions and key metadata are
outside this profile. Informational extensions such as a logo are ignored rather
than fetched or rendered.

Only supported HTTPS and literal-loopback redirect URIs are retained. A document
may advertise other callback forms, but they cannot be used with Vxpipe. Loopback
ports may vary; every other part of the registered callback must match exactly.
Once a code is issued, token exchange requires that exact selected redirect,
including its port. DCR accepts `application_type: native`, including Codex's
registration request.

Database foreign keys remain UUIDs. CIMD adds a unique metadata URL on the client
row; only the external URL can identify that client in OAuth requests. Its internal
UUID cannot be substituted at token or authorization endpoints. The adapters map
validated identifiers to internal IDs before invoking Boruta.

## Metadata retrieval and caching

Persistence reuses ExMCP's metadata fetcher with public-address DNS validation,
address pinning and TLS hostname verification. Requests send fixed metadata
headers and no user credentials. Redirects are forbidden. Limits are 64 KiB,
one second for DNS, two seconds to connect and five seconds for the HTTP request.
The existing authorization rate limits and 10,000-client quota also apply.

Validated metadata is stored with `metadata_expires_at`. New authorizations reuse
fresh metadata and fetch expired documents before opening the database transaction.
`Cache-Control: max-age`, `Age`, `no-cache` and `no-store` are respected. Configure
the default and maximum cache lifetime in application configuration:

```elixir
config :vxpipe_persistence, :oauth_client_metadata,
  default_cache_seconds: 300,
  max_cache_seconds: 3_600
```

There is no periodic job: refresh is driven by a new authorization. An unusable
document fails that authorization without redirecting to the client. Existing
approved grants continue to use their persisted identity and current user/grant
authority checks; token exchange and refresh do not perform network discovery.
Metadata is retained as an authorization record even when HTTP caching is disabled,
but it is fetched again before another authorization.

Cache writes serialize with registration and check the observed row revision so
a slower fetch cannot replace a newer result. Each pending consent stores a digest
of the validated metadata. A metadata change requires restarting that consent;
the app cannot approve details different from those it displayed.

## Alternatives and verification

We kept DCR for clients that do not publish metadata, reused ExMCP instead of
building another HTTP/SSRF layer, and retained UUID foreign keys instead of changing
all credential tables to URL identifiers. A separate OAuth server, background
refresh queue and new token mechanism are unnecessary for this feature.

Focused tests cover URL identity, native DCR, callback matching, browser consent,
issuer responses, token exchange/refresh/revocation, metadata expiry, concurrent
refresh results, rejected redirects, private targets and oversized documents.
The persistence cases exercise the real Boruta adapters and database records;
network responses are controlled fixtures, with no third-party credentials.
