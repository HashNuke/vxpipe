# Installation URL

The Installation URL is the canonical public origin: scheme, domain and optional
port. Console setup saves it atomically with the first Superadmin and session.
Superadmins can subsequently edit it under Settings → Installation. Existing
installations can configure it there without repeating account setup.

## Ownership and storage

Identity owns normalization/access policy; Persistence implements the installation
port using the authentication singleton. Nullable `public_url` and monotonic
`public_url_revision` migrate old rows without inventing a public address.
Settings accept browser sessions only, enforce CSRF, revalidate write authority,
and audit changes atomically. Stale revisions return 409. Identical saves do not
increment the revision. Revoked sessions and non-Superadmins cannot write.

- `GET /api/installation` returns `{public_url, revision}`.
- `PATCH /api/installation` accepts those fields and returns the canonical result.
- `POST /auth/api/setup` additionally requires `public_url`. Internal bootstrap
  callers may omit it for compatibility with embedded applications.

Paths, queries and fragments are stripped. Credentials, malformed URLs and public
HTTP origins are rejected. HTTP is accepted only for localhost, 127.0.0.1 and ::1.
Request Host/forwarded headers never determine the stored value.

## Consumers

| Area | Saved-origin behavior |
| --- | --- |
| Twilio outbound calls | Instruction URL, status and asynchronous answering-machine callbacks |
| Telnyx outbound calls | Scoped event webhook URL supplied when dialing |
| Telephony media | WSS address for incoming/outgoing streams |
| Twilio verification | Canonical webhook/media URL for signature checks |
| Console Services | Platform/tenant webhook addresses offered for copying |
| Inbound MCP OAuth | Issuer, authorization/token/registration/revocation discovery, default `/mcp` resource and challenges |
| MCP and consent admission | Current trusted origin/host and resource audience |
| Outbound MCP metadata | CIMD identity and DCR callback metadata |

Gateway receives an explicit `public_url_provider`; the database-backed runtime
supplies `Vxpipe.Identity.InstallationSettings`. Public URL reads use a protected
ETS cache inside each BEAM instance, without a Gateway→Persistence dependency.
Only a successfully read unconfigured installation falls back to the existing
APP_HOST/PORT/TLS-derived address.

## Cache lifetime and consistency

`InstallationSettings.public_url/0` keeps its existing interface. Persistence
starts the named cache owner and its loader task supervisor after Repo. Runtime
configuration selects the cache; it does not access the database. The first miss
loads lazily, and concurrent misses share one asynchronous read. Fresh hits access
ETS directly without querying the database or waiting on the cache owner.

- Successful entries, including an unconfigured URL, expire after **30 seconds**.
  A background timer refreshes each instance on the same interval. A separate
  Gateway sharing the database therefore observes remote saves on its next
  refresh, normally within 30 seconds plus the bounded read duration.
- Successful local setup/settings writes invalidate the cache after the repository
  operation returns, cancel any older in-flight read, and start a fresh read.
  Failed writes leave it unchanged. An unavailable cache cannot turn a committed
  database save into a reported save failure.
- Loads have a **2-second timeout**, with at most **128 waiting callers**. Failures
  are cached distinctly as unavailable for **1 second** before retry. Expired
  values are not served during a database outage; a fresh cached value remains
  usable until expiry. Cache-owner failure terminates its linked loader; the
  supervisor restarts the owner with an empty table.
- Settings reads used by the editor bypass the public-URL cache so revision
  conflicts and saved values remain authoritative. Explicit deployment overrides
  still bypass the public-URL lookup where applicable.

An embedding host can supervise `Vxpipe.Identity.InstallationURLCache` and a named
`Task.Supervisor`, then set `installation_url_cache` in its Identity dependencies.
The cache takes `name`, `task_supervisor`, and a zero-argument `loader` returning
`{:ok, %{public_url: canonical_url_or_nil}}`. Hosts without that optional dependency
retain direct repository reads. Cache lifetime/retry/timeout options can be set by
the embedding host; the standard deployment uses the defaults above.

ETS was selected over an external Redis dependency for this one local setting.
Unbounded memoization was rejected because it could retain a removed origin
indefinitely; `persistent_term` was avoided because updating it can trigger
garbage-collection work across processes. Polling supplies eventual consistency
without requiring distributed Erlang or a notification service. Immediate
cross-instance invalidation is not provided by this checkpoint.

## Deployment overrides and active calls

An explicit `TELEPHONY_HOST` retains precedence for telephony, including its optional
mount prefix. `VXPIPE_MCP_RESOURCE_URL` preserves an explicit resource identity;
embedded MCP hosts retain their configured admission lists. The issuer still
follows the Installation URL. Embedded hosts without a provider keep supplied URLs.

Accepted telephony legs retain their service, URL and credentials. New legs,
including subsequent transfers, use current settings. Keep the old address
reachable until existing legs end. Operators must update provider-dashboard
webhooks themselves; this change does not reconfigure remote services.

## Outbound MCP metadata foundation

Public, no-store `GET /oauth/client-metadata.json` describes this installation as
an **outbound** OAuth client:

- `client_id`: the saved HTTPS origin plus `/oauth/client-metadata.json`.
- `client_name`: `VxPipe`; `client_uri`: the saved origin.
- `redirect_uris`: the saved origin plus `/oauth/mcp/callback`.
- Public-client code/refresh grants, code response type, no client secret.

`Vxpipe.MCP.ClientMetadata.registration/1` returns equivalent DCR metadata without
assigning a client ID. Unconfigured and local HTTP installations return 503 rather
than publish an invalid CIMD identity. Metadata does not reflect the request Host.

The callback path is reserved for subsequent outbound OAuth work. This checkpoint
does not implement authorization-server discovery, registration requests, callback
processing, token storage/refresh, remote CIMD fetching or a Connect MCP flow.
The existing inbound authorization server remains DCR-based; publishing this
document does not add inbound CIMD support.

The [approved MCP profile](https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization)
requires HTTPS metadata-document client IDs and exact redirect matching. Changing
the origin changes the future outbound client identity/redirect; old grants must
not be relabeled. Inbound clients need fresh discovery after an issuer change and
fresh authorization after a default-resource change. Pending authorizations should
be restarted. Tokens remain bound to their original resource;
external clients' own registered redirects are never rewritten.

## Alternatives and implications

Request-derived origins were rejected because headers are not installation
authority. Startup-only caches were rejected because saves must apply without a
restart across nodes. Replacing all URLs was rejected because external redirects,
provider endpoints, signed artifact URLs and listener addresses have other owners.
Deployment overrides remain necessary for independent public endpoints.

Saving this setting does not provision DNS, certificates, proxies or listeners.
It does not revoke remote tokens or migrate remote registrations. Rolling back the
migration drops the saved setting and returns consumers to runtime configuration.

Verification covers atomic setup, revisions, authority, metadata, runtime
overrides, dynamic discovery/consent and retained telephony snapshots. See the
[implementation labnote](../labnotes/20261024-2034-installation-url-backend.md).
