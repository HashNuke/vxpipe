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
outside this profile. Optional `client_uri` and `logo_uri` are retained after
HTTPS validation; unrelated informational extensions are ignored.

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

## Consent presentation and callback ownership

Storybook includes **Vxpipe → Console → Authentication → MCP authorization**.
Run `bin/storybook`, then open **Review Request**. **Allow Flow** and **Deny Flow**
exercise the buttons and show the proposed completion screens. Consent shares
`OAuthConsent` with the production page. Other stories cover DCR,
missing/broken logos, all-tenant access, no permissions, unavailable requests,
long names and the light theme. The account, tenant and authority are fixtures.

The production page uses the Console visual system, client branding, signed-in
account identity, readable permission labels, explicit tenant scope and expandable
exact identifiers/callback details. The backend supplies the current authority
snapshot and grant lifetime; Storybook alone supplies synthetic values. Mixed
all-tenant/assigned-tenant authority lists its exact all-tenant actions separately.
Both decisions remain available without preselecting consent. A native HTML form
preserves the authenticated CSRF-protected POST and works without JavaScript.

Today, `AuthorizationController.decide/2` sends a **302 redirect** to the validated
client callback. Approval includes `code`, denial includes `error=access_denied`,
and both include `iss` and the original `state` when present. The receiving client
owns the next screen. The Storybook completion screens are design proposals,
not current production routes. Protocol details and review notes live in this
documentation, not in the proposed app copy. For a native
client such as Codex, the callback may return to a loopback listener on the user's
device. Failure to validate the request stays at Vxpipe without a redirect.
Expired, consumed or otherwise rejected requests use the shared recovery screen
with a Back to Vxpipe link. It retains the HTTP error status and does not display
a client identity or approval receipt from a failed validation.

The approved screen says **Access approved**, without claiming the client has
finished its token exchange. **Back to Vxpipe** is the primary action and returns
to Console home; **Manage connected clients** is a secondary text link. Denial
states that no new access was granted and existing connections are unchanged.

**Vxpipe → Console → Settings → Your connections** includes a complete
revocation journey with connected, empty, loading, unavailable, revoking and
failed-revocation states. The consent and approval screens link to it. Both
Storybook navigation paths reach the separate Your connections page, using an
in-memory adapter for the real component. Revocation requires confirmation; a
successful revoke removes only the selected client and announces the result,
while failure keeps it listed and leaves the dialog available for retry.
Production exposes the standalone `/account/connections` page under Settings →
For you. `/account` contains only the self-account form. Both use the same shared
components as Storybook; production connects them to the session-bound APIs.

### Optional client branding

[`client_name`, `client_uri`, and `logo_uri` are standard DCR metadata](https://www.rfc-editor.org/rfc/rfc7591.html#section-2).
The [MCP CIMD example](https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization#example-metadata-document)
uses the same fields. Name, website and logo describe the client; they do not
prove that Vxpipe has verified or endorsed it.

The Codex Storybook fixture uses supplied public metadata. Production accepts the
same branding fields from either registration method. It renders an HTTPS logo with no
referrer and falls back to the shared Lucide `Plug` icon if the logo is absent,
invalid, or fails to load. The website is optional; DCR does not need to provide
either optional branding field. The remote logo remains an external image
dependency, with the fallback available offline.

Branding URLs are limited to 2,048 bytes, HTTPS and no embedded credentials,
fragments or control characters. New invalid metadata is rejected at registration
or discovery; invalid optional URLs in existing stored records are omitted from
presentation. Missing branding remains valid. Names render as text. Browsers load
logos directly with `no-referrer`; Vxpipe does not proxy arbitrary logo URLs. The
page CSP permits these HTTPS images, and the bounded logo box handles load failures.
Branding participates in the existing metadata digest, so changing only a logo
also invalidates pending consent. The JSON metadata column needs no migration.

A rollback-only local-browser check exercised both DCR and CIMD through actual
HTTP authorization, callback delivery, S256 exchange, an MCP tool invocation,
refresh and revocation. Reusing the code returned 400; using the revoked token
returned 401. Denial returned the original state and issuer. The local CIMD peer
uses the existing test DNS/HTTP adapter seam; public-address validation remains
enabled in production. Focused Identity, Persistence, Console and shared UI tests
cover branding rejection, old records, digest drift and rendered authority.

The completion-screen choice remains open: the client owns the callback page.
Replacing its redirect with a Vxpipe receipt loses code/error delivery; moving the
callback to a new window can break browser clients that rely on their original
window/opener. The current implementation preserves the original-window 302.
A separate receipt would require an explicit browser experience decision; no new
receipt store, session cookie or callback transport has been introduced.

### Personal settings follow-through

The Settings sidebar groups **Your account** and **Your connections**
under **For you**, below the administrative links the user may access. Ordinary
members retain these personal destinations even without any administrative
permissions. Account editing and connection management are separate pages, and
revocation asks for confirmation before submitting. The confirmation uses the
shared component. Both authenticated routes are available without platform
administrative permissions, and the main sidebar's Settings entry falls back to
Your account when no administrative destination is available. Self-account
writes and connection list/revoke operations derive ownership from the current
session; they do not accept a target user from the page.

The [Personal settings and MCP consent milestone](../../../labnotes/milestones/personal-settings-and-mcp-consent.md)
tracks the production route/sidebar cutover, self-account behavior, CIMD/DCR
branding and OAuth completion integration. It remains unchecked until real-app
and protocol acceptance pass.
