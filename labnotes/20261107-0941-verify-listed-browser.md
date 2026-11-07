# Verify listed MCP and outage browser workflows

Reuse the existing isolated checkout, setup-owned databases/ports, trusted local
CA, real Console authentication/CSRF and MCP/OAuth peer. The current production
UI matches the main checkout; intervening main commits change tests and evidence.

Now that the user recovered both external repositories, use the actual directory
publisher/API with controlled local definitions for listed browser acceptance.
This avoids another synthetic directory implementation. A local TLS proxy will
keep the configured HTTPS-origin and certificate verification boundaries. The
existing cache and listing resolver remain in use; explicit supervised cache
restart supplies the cold-cache outage case. Local-status failure will disable
the configured MCP repository port inside this isolated dev process, retaining
real identity/tenant persistence. Record these deliberate fixture boundaries.

Started the existing bearer MCP peer through IEx so bounded fixture configuration
changes can be made locally without adding application endpoints or production
code. No browser acceptance result is claimed yet.

The bearer listing now passes real authenticated create with a locked endpoint and
authentication recipe, independently optional Setup link, literal plain-text notes,
and a single initially empty masked token field. Desktop/mobile screenshots were
inspected. Its Tools tab exposes the actual `list_events` tool; a first driver wait
incorrectly looked for the word `fixture` and was corrected after inspecting the
actual tool name.

With the directory TLS proxy returning actual HTTP 503, saved tool refresh succeeds.
Reloading the browser still shows the valid cached directory row and saved status;
the proxy receives only an image request, no additional catalog request. An initial
counter incorrectly included images and was corrected to count `/v1/` requests.
After explicitly restarting the owned production cache, AI browsing shows the
unavailable-directory notice and all 11 installed AI fallbacks while the saved MCP
remains available through Connected. Both outage viewports were inspected.

During this cold outage, failed listed secret replacement preserves the working
record exactly; successful replacement preserves ID, namespace and accepted
snapshot while incrementing generation. Neither replacement requests the directory.
Disconnect succeeds. Ordinary custom creation for the same endpoint offers Review
reconnect; the resulting form loads the accepted listed configuration with a fresh
empty token. Cancel leaves the record disconnected. A later explicit reconnect
with fresh input preserves ID, namespace and snapshot and advances generation
through revocation/reconnect. Public before/after JSON and rendered evidence are
kept under the ignored listed-directory artifact folder.

Outage rendering exposed a separate committed build defect: native logo imports
use relative URLs and resolve to HTML at nested tenant routes. Astra independently
reproduced image decode failure versus the working `/assets/` URL. Main now has a
red/green project-build regression and shared public-path correction under review.
Apply that same configuration to this checkout, rebuild and restart the owned
Console/peer with its existing private fixture credential before completing visual
acceptance. The earlier fallback screenshots are not proof of successful native
logo rendering.

After rebuilding/restarting with the reviewed asset correction, all ten native
images decode at `/assets/` on both viewports, with MorseCode's intended placeholder
and no horizontal overflow. Both screenshots were inspected.

For the independent local-status outage, restored the real directory proxy to
HTTP 200 and restarted the cache. Temporarily removed only the isolated Console's
configured MCP repository port. Inventory returns typed HTTP 503
`connection_status_unavailable`; desktop/mobile show Retry connections and no
unsafe Connect controls. Actual directory HTTP 200 and Calendar navigation prove
that catalog availability is independent. Restoring the port and clicking Retry
clears the error. The controlled catalog contains only Calendar, so its AI request
correctly returns category 404; a driver wait for installed fallback cards was
inapplicable and was corrected to the actual Calendar page.

The rate-limit boundary also uses actual directory HTTP: a cold-cache `/categories`
request receives HTTP 429 with Retry-After 60. Clicking Retry directory and requesting
a distinct AI page through the authenticated inventory leave the upstream `/v1/`
request count unchanged (15 before/after). Inventory remains HTTP 200 with
`directory_error=rate_limited`, installed fallback services and the saved MCP record.
Cache limits and the rest of cooldown timing remain covered by automated contracts;
this pass proves real HTTP cooldown suppression, without replacing the clock.

The controlled definition was then synchronized through the actual recovered Go
publisher with changed display name/setup guidance, and the cache restarted. The
catalog card shows the new name while Manage shows the original accepted name,
plain-text guidance and fixed recipe. The entire public saved record is byte-value
equivalent to its post-reconnect snapshot (generation 4, snapshot revision 1).
Synchronizing `availability=retired` preserves that same record and successful real
Tools refresh. Public API artifacts independently confirm the revised catalog and
retired availability. No saved configuration is silently rewritten.

Astra independently reviewed public record equality, six rendered screenshots,
proxy implementation/logs and the production/test boundaries. No reproduced defect
was found. This browser evidence is scoped to bearer; catalog edits change name,
guidance and availability, not endpoint/authentication recipes. Local-status failure
is loss of the configured repository port, not a PostgreSQL network disruption.
Directory TLS is real; outbound MCP continues using the declared controlled routing.
The credential scan covers 13 captured public/log files, not all possible runtime
output. Automated request-log redaction contracts cover the other boundary.

Composite outage evidence includes Console `integrations_directory/cache_test.exs`
(cooldown, eviction and bounds), `mcp_connections_endpoint_test.exs` (discovery/create
request-log filtering), and the already-passing tagged disconnect/revocation/runtime
lanes recorded in saved MCP acceptance. Preserve the count receipt from the actual
HTTP 429 check, and keep the broader listed-authentication/release gates open.

Advancing the peer briefly encountered a shutdown/listener timing issue: starting
before the previous IEx exit caused an empty port, so the attempted launcher exited.
After confirming the old session terminal and no listener, use the setup-assigned
port without the probe's transient closed-socket bind check; Bandit still enforces
exclusive actual listening. No databases or assigned ports were changed.

Listed Basic now passes actual authenticated creation and Tools (`list_events`).
Its form has a fixed URL and HTTP Basic recipe, only initially empty username/password
fields, and an independently optional Documentation link with noopener/noreferrer;
there is no Setup link. Desktop/mobile screenshots were inspected with a visible
footer and no overflow. The public persisted snapshot has Basic authentication,
the directory identity and one discovered tool. Private fixture credentials are
kept only in ignored local evidence files.

Listed API-key creation and Tools now pass too. The desktop/mobile form shows only
one initially empty password input labelled with the fixed `x-api-key` header;
there are no editable endpoint, authentication or header-name controls and no
optional setup block when absent. Both screenshots were inspected. The persisted
snapshot keeps `api_key` plus its fixed header while the saved outer method is
`headers`, with one real discovered tool.

Listed anonymous creation and Tools pass with no input fields, selectors or setup
metadata. Desktop/mobile rendered forms show the fixed endpoint and No
authentication recipe; both screenshots were inspected. The saved snapshot keeps
`none` and one real discovered tool. All four listed static recipes now have actual
authenticated creation plus Tools evidence; full replacement/reconnect/outage
behavior in this pass remains specifically demonstrated with bearer.

Listed CIMD discovery and consent now run through the actual authenticated flow.
Denying access returns a fixed-recipe recovery form with a clear cancellation notice;
the public inventory proves no CIMD record was created. Both recovery viewports
were inspected. A body-element screenshot of the earlier mobile setup clipped the
fixed modal after page scrolling; it was replaced with a viewport screenshot, and
viewport dialog bounds/overflow were checked directly.

An early driver attempted the cache fault before the pending Connect/navigation
command completed; that attempt showed a connection error and did not reach consent.
No product defect is inferred from this deliberately mistimed fault. Future dependent
steps wait for the prior command to finish and scripts stop on failed commands.
On the successful attempt, first confirmed the real provider consent page, then
forced directory HTTP 503 and restarted the cache before allowing access. Callback
persisted the original CIMD recipe/identity with one real tool during the cold outage;
Connected and saved Tools remain available. The earlier failed attempt is not
counted as successful callback acceptance.

CIMD denied replacement preserves the entire public inventory exactly; approved
replacement advances only generation while retaining ID/namespace/snapshot during
the cold outage. Disconnect and ordinary custom endpoint proposal require explicit
Review reconnect. Cancel keeps the record disconnected. The locked retained form
was inspected at both viewports. An explicit reconnect restores the original record
at generation 4. A second disconnect/reconnect pass genuinely denied provider
consent, verified the record stayed disconnected, then explicitly approved and
restored the same identity/snapshot at generation 6; both denied-recovery viewports
were inspected.

Fast reconnect exposes actual HTTP 429 `mcp_connection_busy`, not bad credentials.
The old form blamed credentials; its new red/green feedback correction is tracked
separately. The earlier screenshot labelled reconnect-denied actually captured the
busy error and was renamed to reconnect-start-error. The later denied-consent
screenshots and public missing-record receipt are the real denial evidence. The
updated actual busy UI was verified at both sizes, then explicit retry reached
consent. Do not count the earlier timeout as denial or successful reconnection.

Listed DCR now passes authenticated creation, actual consent and Tools; both setup
viewports show the fixed recipe and optional initially empty registration token.
Replacement during a cold directory outage preserves ID/namespace/snapshot and
advances generation to 2. The form explicitly offers saved-registration sign-in,
and actual peer registration count stays 1. After disconnect, ordinary endpoint
proposal requires Review reconnect; the locked retained form offers a fresh empty
registration token and no saved-registration reuse. Explicit consent reconnects the
same record at generation 4, and peer registration count becomes exactly 2.
This distinguishes compatible saved replacement from fresh registration after
revocation using actual protocol counters, not inferred UI text alone.

Astra independently reviewed the four listed static recipes, CIMD denial/recovery
receipts, public identity equality across generations, DCR registration counters
and both viewports. No new defect was found. The independent-outage composite gate
can close with the automated boundary links and count receipt. Reusable startup
outage controls remain a separate open task: ignored local proxy/IEx overrides
prove these observations but do not provide a committed repeatable launcher.

Before the listed own-client pass, both owned non-PTY directory processes were
confirmed stopped, explaining the missing live catalog after the Console restart.
Restarted the actual Go API and TLS proxy under owned PTY sessions, checked healthy
responses and cleared the isolated cache before proceeding. Their termination
source is unknown; do not mistake a dead fixture for a product discovery defect.

Listed preregistered-client creation and Tools pass using the controlled Basic
client. Initial Client authentication is unselected; submission requires an explicit
choice. Only Client ID, the selected method's secret and the exact read-only
installation callback are shown, with no editable endpoint/grant/recipe. Both
viewports were inspected before filling private values. The saved snapshot retains
`preregistered` and one real tool. Broader retained recovery is still in progress.

Listed own-client retained recovery also passes. Disconnect plus an ordinary custom
endpoint proposal requires Review reconnect and a fresh explicit client-authentication
choice. The retained form starts with empty Client ID/secret; denying actual provider
consent during a cold directory outage returns a cancellation notice and clears both
fields. The public inventory confirms the record remains disconnected. After entering
fresh credentials and explicitly approving consent, the same record returns at
generation 3; its public fields, namespace and accepted listing snapshot match
generation 1 exactly. Both retained and denied-recovery viewports were inspected.
The acceptance driver briefly used an invalid CLI locator command before entering
credentials; corrected to the supported `find label` command. No product failure
is inferred from that driver error.

Custom machine retained recovery now passes with `client_secret_basic`. Actual
create and explicit reconnect each make one token request plus MCP initialization
and tool listing; peer counters show two token/initialize/tool-list operations and
no authorization endpoint request. Disconnect plus the ordinary custom proposal
requires Review reconnect. Cancel leaves it disconnected; a subsequent review
clears both Client ID and secret. The settled reconnect form was inspected on
desktop/mobile, with fixed URL and client-credentials grant. Explicit reconnect
with fresh values restores the same public record/namespace at generation 3 during
the directory outage. Earlier screenshots without `-ready` captured pending
discovery, not the completed form; the `-reconnect-ready` screenshots are the
settled evidence. Two driver waits expected nonexistent success/endpoint text;
public receipts and actual rendered state established the completed operations.

Astra independently approved the own-client public equality and six rendered
viewports. This listed pass covers Basic client authentication; the earlier custom
pass covers the broader authentication-method matrix. Initial blank listed-client
authentication was observed before selection; setup screenshots show Basic already
selected and the earlier validation notice. The explicit initial-blank assertion
is also in `ListedMcpOAuth.test.tsx:46`.

The review mapped existing T6a/T6b contract evidence: changed version/revision and
retirement in `integrations_directory/listing_test.exs:59`; changed probe recipes
in Calls `mcp_connections_test.exs:156`; private OAuth overrides in Console
`mcp_listed_oauth_preparation_test.exs:136`; snapshot rejection/immutability in
Persistence `mcp/connection_store_test.exs:193`; fixed optional-content forms in
`ListedMcpDialog.test.tsx:12`. Retained stale/cross-tenant and storage failures are
covered by Calls `mcp_retained_read_test.exs:55,88`, Console
`mcp_listed_oauth_endpoint_test.exs:177`, Persistence
`mcp/connection_store_test.exs:154` and `OAuthReturn.test.tsx:102,127`.

The existing-call-spec reference contract remains open: stable ID/namespace alone
is not the complete composition proof. Add a focused existing call specification ->
disconnect -> reconnect -> fresh preparation check; the saved runtime case at
`saved_mcp_runtime_test.exs:177` currently stops after invalidating prepared state
on replacement. This is an acceptance evidence gap, not a reproduced product bug.
Reusable startup outage controls and external release/workflow approval remain
separate outstanding tasks.

Astra independently verified the machine public receipts/counters and completed
reconnect-ready desktop/mobile forms plus mobile Tools, finding no new bug. It
approved closing the two T6a identity/form-contract acceptance tasks using the
combined listed static/CIMD/DCR/preregistered browser pass, the mapped automated
facade/storage/UI contracts and green verification. This does not claim every
client-authentication permutation was repeated as listed. Machine remains custom
T6/T6b evidence, consistent with listed V1 authorization-code-only recipes.

All five root gates now pass after the asset/busy/monitor changes: 4,992 umbrella
tests, zero failures, 263 excluded (seed 774698). All 1,065 frontend tests, TypeScript
and ESLint pass. This checkpoint changes only documentation; relative links and
`git diff --check` pass. Final review/release gates remain unchecked.
