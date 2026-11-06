# Custom MCP OAuth forms and return recovery

The production Integrations dialog uses the existing discovery, connection and
OAuth endpoints. It does not implement OAuth protocol negotiation in the browser.
The server rediscovers metadata and validates every submitted credential and
override before sending it. Storybook substitutes in-memory responses and a
simulated handoff, with no provider navigation or real HTTP calls.

## Field ownership

CIMD requires only the MCP URL and method. DCR adds an optional masked initial
registration token. Their endpoints, callback, registration metadata, scopes and
request parameters remain backend-owned. Additional generic fields for these
methods would suggest unsupported override contracts and are deliberately absent.

Own-client forms expose only advertised grants, client authentication methods and
supported signing algorithms. Public clients never submit stale secrets or keys.
Client credentials has no callback, authorization URL or authorization-request
parameters. Browser grants show the exact backend-provided Installation URL
callback, with a copy action. They cannot proceed without a configured identity.
Endpoint/scopes overrides and literal provider-specific request values remain
subject to backend validation; managed state, PKCE and grant parameters are not
editable. Method, issuer and URL changes clear credential state. A private key
must be explicitly revealed to edit its multiline value; hide/show preserves
newlines without relying on nonstandard CSS masking.

Saved OAuth metadata supplies the actual registration method and nonsecret
grant/client-auth labels. Values are never loaded from saved credentials into
inputs. Test connection and Refresh tools use catalog-only refresh; replacement
is explicit. Browser reconnect keeps the saved endpoint, matching the existing
backend transaction contract. A changed URL explains that a new connection is
required before attempting an unsupported request.

## Consent return

Browser authorization submits the current tenant Integrations path and bounded
search/cursor context. Before navigation, an optional five-minute sessionStorage
record keeps the actor, tenant, attempt and connection identity, return location,
and a strict nonsecret form whitelist: endpoint, method, selected issuer,
client-auth choice and saved generation. Client IDs, credentials, private keys,
header/parameter values and authorization URLs are excluded. Query-bearing MCP
or issuer URLs are not persisted because query values can carry credentials.
Unavailable storage or an oversized record does not prevent authorization; it
only prevents automatic form recovery. The serialized record is bounded to 8 KiB.

A matching callback consumes the tab-local draft once. It never authorizes a
connection or completes an OAuth attempt: backend session, tenant, installation
and single-use state checks remain authoritative. Success feedback requires the
matching connection to be connected in current authorized inventory. Unknown,
expired or mismatched drafts produce neutral recovery guidance. Denial/failure
restores only the whitelist and requires credential reentry; changed saved
generations and lost write permission block restoration. Callback markers are
removed using history replacement. Cursor-expiry recovery preserves the original
attempt context while allowing the directory to restart from its first page.

Rejected alternatives include storing the whole form, trusting a callback query
as proof of connection, restoring secrets after consent, guessing Console identity,
and submitting unsupported saved-endpoint replacement. The callback draft is a
convenience bound to the current actor and browser tab, not a session credential.

## Verification and limits

Focused regressions start red for form contracts, discovery identity parsing,
saved OAuth management, multiline keys and production callback recovery. Return
tests cover current-inventory confirmation, actor mismatch, stale generations,
failed/denied consent, cursor expiry and percent-encoded queries. Desktop/mobile
Chrome inspection covers managed fields, own-client keys, grants and simulated
handoff. The fixture checks do not establish a real provider browser round trip.
Independent-node, authenticated Console browser and listed-template acceptance
remain tracked in the [milestone](../../labnotes/milestones/integrations-directory-and-tenant-mcps.md).
