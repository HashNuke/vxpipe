# Authenticated integrations browser acceptance

Use an isolated checkout and its setup-owned PostgreSQL databases for real Console
identity/session and integrations requests. The checkout starts at f85358fa, whose
production code matches the pending test-only renewal lifecycle checkpoint. Keep
the original Console/Storybook processes and user database unchanged.

Run bin/setup for this checkout before starting services. Use its assigned Console
port and a loopback HTTPS listener for CIMD and consent callbacks. Fresh installation
setup will create an acceptance-only Superadmin through the real UI, without
resetting any existing account. Controlled local directory/OAuth/MCP services may
supply synthetic external responses, but browser requests must reach the actual
Console routes and durable stores rather than a Storybook in-memory adapter.

Acceptance must cover desktop/mobile discovery recovery and issuer choice, consent
return, masked editing, listed/retained identity recovery, native override/restore,
and independent directory/connected-status outages. Cross-node callback evidence
must use shared durable attempts/sessions; the earlier renewal cases do not prove it.

Initial setup failed because ExMCP was compiled before its Plug dependency in a
fresh checkout. A focused setup-order correction is tracked separately in
[bootstrap labnotes](20261107-1110-fix-mcp-bootstrap.md). Setup now succeeds for both
environments, including assets and isolated database migrations.

The real Phoenix HTTPS endpoint now serves the actual compiled Console. Installation
setup, acceptance-only Superadmin creation, authentication, tenant creation and
Integrations navigation all succeeded through the UI with durable dev repositories.
No fake identity backend or Storybook adapter is installed. Credentials and local
TLS material remain only in ignored private files, never in this evidence.

Rendered Chrome inspection at 1280x900 confirms the empty Connected integrations
page and custom modal. Authentication offers only actual methods. CIMD has no
editable OAuth fields; DCR has only its optional masked initial registration token.
Custom headers has an editable X-API-Key row and Add/Remove, with no empty additional-
parameters disclosure. Bearer and Basic have optional header editors with no initial
rows; switching from Custom headers to Bearer clears the X-API-Key row. The DCR
modal also renders without clipping at 390x844. Local screenshot captures record
these states. No credential values were entered or photographed in this pass.

These observations establish real authenticated form presentation, not discovery,
registration, consent return, saved edits or outage/recovery acceptance. Those gates
remain open. A controlled local OAuth/MCP peer is needed to complete repeatable
browser flows without using public provider accounts.


The reusable peer now accepts the browser installation's configured resource,
issuer and Console origins while retaining existing fixture defaults. Two first-run
protocol cases failed on resource identity before this extension. The first green
run also exposed a test request supplying a nil client_secret for the public CIMD
client; omit the inactive key, as the production request builder already does. The
corrected two new cases plus eight existing OAuth cases pass.

An explicit one-use Allow/Deny wrapper keeps authorization parameters server-side
and checks the actual CIMD document through a configured metadata fetcher before
granting access. Four consent tests failed before its implementation; all 14
combined peer/consent/OAuth cases now pass. The manual dev launcher changes only
the remote-protocol ports, retaining real Console identity, persistence and encryption.
Independent review found that its output directory was not guaranteed to exist;
create that directory before starting peers or mutating application ports. Full
browser and TLS acceptance is still pending, including the actual CIMD fetch.


The first actual browser discovery returned resource_metadata_unavailable. Direct
inspection proved both fixture listeners were gone while Console remained running:
the linked script-owned supervisor retired when Mix finished evaluating the script.
Attach the named fixture DynamicSupervisor to the running Console supervisor so
its lifetime belongs to the server. This is an acceptance-launcher correction,
not a production discovery change. A first restart also caught a transient port
reservation check; the empty command-substitution result caused that process to
exit before the fixture started. After confirming the listener absent, reuse the
setup-assigned port explicitly and keep shell failures fatal.


After the launcher lifetime correction, the real UI's Retry discovery recovered
from unavailable metadata to OAuth settings discovered, selected CIMD and enabled
Connect. The unavailable state kept authentication unresolved rather than claiming
anonymous access. The remote protected-resource response retains the configured
HTTPS resource/issuer ports. Rendered desktop captures show both states.


The first Allow action reached the real CIMD TLS fetch, which correctly rejected
the self-signed leaf as a trust anchor. The public document itself is valid and
available. Replace the local fixture certificate with a leaf signed by an explicit
private test CA; configure only that CA for the fixture metadata fetcher, retaining
normal certificate/hostname verification. No production trust policy changes.


With the CA-signed fixture certificate, both curl and Req fetch the real public
CIMD document with normal peer/hostname verification. The browser's Allow action
now returns to the same tenant's Connected integrations page and shows Fixture
calendar connected. This traverses actual session/CSRF authorization, pending
attempt storage, TLS CIMD retrieval, code/PKCE exchange, encrypted grant storage
and real ExMCP initialization/tools discovery. The public inventory has exactly
one connected record at generation 1. Management loads the saved CIMD method,
keeps saved credentials undisplayed and shows list_events. Refresh tools disables
while pending and returns to the same tool list without a success message.


Denying a connected credential replacement returns to the same management modal
with cancellation feedback; the public identity remains one connected record at
generation 1 with the same namespace. Disconnect removes it from the connected
list. At 390x844, entering the same endpoint offers Review reconnect instead of
creating a record. Review loads its retained settings with a fixed URL and explicit
Reconnect action. Denied retained consent returns to that recovery modal; a fresh
generation-bound metadata read still reports the same ID/namespace as revoked at
generation 2. No record was silently restored or duplicated.

After integrating the helper changes into the main checkout, all 39 focused
consent, OAuth, renewal and independent-node cases pass. All five root gates pass:
format, warnings-as-errors compilation, strict Credo, 4,991 tests with zero failures
and 237 excluded (seed 594684), and unused-dependency verification.
Independent launcher re-review is clean after directory, supervisor-lifetime and
explicit CA corrections. Full milestone/browser acceptance remains open.


Allowing the retained reconnect on mobile restores exactly one connected record
with the original ID and namespace at generation 3. The callback returns to the
same tenant and connected category; the rendered mobile list has no clipping.
This closes the narrow custom-CIMD retained flow, not the listed/DCR/own-client,
partial discovery, multiple-issuer or separate-node callback gates.


Entering the now-connected CIMD endpoint again offers Manage existing connection
on mobile. It opens the same connection's management rather than starting consent
or creating a duplicate. Disconnect it before switching the controlled peer to the
DCR scenario; the retained record stays in the isolated acceptance database.


The runner's DCR startup mode advertises registration and client_secret_basic,
with CIMD disabled. Its public metadata is retrievable over CA-verified HTTPS.
The real URL preflight selects DCR and shows only the optional initial registration
token. A denied first consent returns to the custom draft with no connected record.
Retry and explicit Allow complete registration, code exchange, callback and MCP
discovery, producing exactly one connected DCR resource at generation 1. The peer
uses an unprotected registration endpoint in this scenario; protected-registration
UI acceptance remains separate.


DCR management loads the saved registration method and keeps credentials
undisplayed. Test connection completes with HTTP 200, and its discovered tool list
renders without clipping on mobile. The source in the main checkout exactly matches
the source used by the isolated browser runner. Independent source/documentation
review is clean; the final staged review includes the additional DCR captures.
