# Authenticated MCP browser acceptance

The manual peer in `test/browser/integrations.exs` supports repeatable Console
browser checks in an isolated development checkout. It keeps real identity,
sessions, CSRF, tenant authorization, encrypted PostgreSQL stores and the compiled
React application. It replaces only the remote MCP/OAuth protocol ports with the
controlled HTTP peer used by integration tests.

Status: custom CIMD discovery, explicit consent, callback, management and tool
refresh have been exercised through the authenticated browser. Denied replacement
preserves the connected record; mobile retained reconnect preserves its ID/namespace
through denied consent and later explicit approval. Custom unprotected DCR also
passes discovery, denied initial consent, draft recovery, successful retry and
saved-credential management, with its tool list inspected on mobile. Protected DCR
also passes missing-token rejection and explicit retained-ID Basic-to-DCR reconnect
through actual consent. All four own-client authentication methods and the three
confidential machine methods pass create, saved testing, mobile Tools and disconnect;
machine discovery selects client credentials and connects without a consent redirect.
See the [OAuth scenario evidence](../../labnotes/20261107-1247-configure-oauth-test-modes.md).
The four
static startup modes now pass real create, wrong-credential rejection where
applicable, saved testing and disconnect. Basic failed replacement preserves the
working record. The mobile pointer-tab dismissal exposed by this pass is fixed:
management keeps a stable frame, long Authentication content scrolls, and pointer
and keyboard tab selection retain the dialog on desktop and mobile. See the
[gesture and layout evidence](../../labnotes/20261107-1229-stabilize-mcp-dialog.md).
The complete
[integrations milestone](../../labnotes/milestones/integrations-directory-and-tenant-mcps.md)
also requires the remaining listed/retained recovery cases, browser URL/revision
races, outage states and final
release checks. Partial discovery now passes explicit retry with manual-method
preservation. Multiple-issuer discovery requires selection and recovers from an
unavailable issuer; both recovered flows pass actual consent and saved management.
Unsupported OAuth stays blocked with consistent submission feedback. See the
[discovery recovery evidence](../../labnotes/20261107-1304-verify-discovery-recovery.md).

Independent-node callbacks and subsequent grant renewal now pass a separate
six-case Console endpoint lane with real durable identity and signed cookies.
Those ConnTest checks do not replace rendered browser or TLS acceptance; see
[cross-node callback evidence](../../labnotes/20261107-0819-verify-oauth-node-callbacks.md).

Native platform inheritance, tenant override and restore also pass through the
real Console and encrypted stores under a fresh-process directory outage with no
cached catalog. The tenant returns to the same platform credential after restore,
and temporary credentials are removed afterward. This does not validate keys with
an external provider; see the [native evidence](../../labnotes/20261107-1320-verify-native-inheritance.md).

## Start an isolated session

Run `bin/setup` in a separate checkout. Use its assigned databases and ports; do
not repoint this peer at an existing user installation. Create the installation,
Superadmin and tenant through the real setup UI. Keep any acceptance credentials,
TLS keys and browser state under ignored `.vxpipe/browser/` with private file
permissions. Never commit or print them.

Provide a local CA and a server certificate signed by that CA. The certificate
must cover `localhost`, `auth.example.test`, `mcp.example.test` and `127.0.0.1`.
The fixture's CIMD fetch trusts the explicitly supplied CA and retains normal
certificate and hostname verification. A self-signed leaf is not a substitute
for this CA/leaf configuration.

With those files prepared, launch from the checkout root:

```sh
set -e
set -a
source .env
set +a
TASK_CONSOLE_PORT="$(bin/worktree-port console --check)"
export PORT="$TASK_CONSOLE_PORT"
export APP_HOST=localhost
export VXPIPE_DEV_TLS=phoenix
export VXPIPE_TAILSCALE_IP=127.0.0.1
export VXPIPE_DEV_TLS_CERTFILE="$PWD/.vxpipe/browser/localhost.crt"
export VXPIPE_DEV_TLS_KEYFILE="$PWD/.vxpipe/browser/localhost.key"
export VXPIPE_BROWSER_CA_CERTFILE="$PWD/.vxpipe/browser/ca.crt"
export VXPIPE_BROWSER_ACCEPTANCE=1
mix run --no-halt test/browser/integrations.exs
```

The launcher creates its output directory before starting peers. The named fixture
supervisor belongs to the running Console supervisor, so it survives evaluation
of the Mix script. Both peers listen on loopback; the TLS port is allocated by the
OS unless `MCP_BROWSER_PORT` is supplied. Public endpoint information is written to
`.vxpipe/browser/peer.json`. No credential material is written there.

Use a dedicated Chrome session with `*.example.test` resolved to `127.0.0.1`, and
open the Console at its assigned HTTPS localhost port. Configure the installation
URL to that same origin. Enter the resource URL from `peer.json` in Connect other
MCP. The default mode is CIMD; `MCP_BROWSER_MODE=dcr` advertises DCR instead.
Static modes are `none`, `bearer`, `headers` and `basic`. They expose an actual MCP
initialization/tool-list endpoint and no OAuth metadata, registration or token
endpoints. `none` is suggested only after the backend successfully initializes the
anonymous peer; other static modes leave discovery unresolved for manual selection.
Each startup generates fresh fixture credentials in ignored
`.vxpipe/browser/credentials.json` (mode 0600 inside a mode 0700 directory). Use
those values in the corresponding Console form without printing them or saving
them in screenshots. They change on restart, so saved connections need an explicit
credential replacement. Public `peer.json` contains no credentials.

`MCP_BROWSER_MODE=own_client` provisions an authorization-code client at startup.
Choose its token authentication with `MCP_BROWSER_CLIENT_AUTH_METHOD`: `none`,
`client_secret_basic` (default), `client_secret_post` or `private_key_jwt`.
`MCP_BROWSER_MODE=machine` provisions a client-credentials grant using the same
setting, except that public (`none`) clients are rejected. The private credentials
file supplies the client ID and, as applicable, secret or fresh RSA private key,
algorithm and key ID. Enter these in OAuth - Own client; machine discovery selects
the client-credentials grant without a consent redirect.

`MCP_BROWSER_MODE=protected_dcr` advertises DCR and requires the fresh
`initial_access_token` from the credentials file in Initial registration token.
Missing or incorrect tokens cannot register a client. Ordinary `dcr` remains
unprotected. These scenarios use the existing real registration, token and MCP
protocol boundaries; the peer credentials rotate on every startup.

For discovery recovery, `MCP_BROWSER_MODE=partial` fails the first authorization
metadata request and succeeds on a later retry. Do not probe the metadata before
opening the Console, because doing so consumes this one-time failure.
`multiple_issuers` advertises the working issuer and an unavailable issuer path;
choose the unavailable issuer to inspect the partial state, then select the working
issuer to recover. `unsupported` advertises only plain PKCE, so the Console must
show its unsupported-OAuth state and refuse managed OAuth authorization. These
three modes otherwise use the CIMD peer and write no client credentials.

The peer displays Allow/Deny consent and retains authorization parameters in
bounded, expiring server-side memory. Consent references are one-use. CIMD Allow
fetches the actual public Console document over TLS and checks its client/callback
identity before returning an authorization code. Deny returns cancellation without
minting a code. Authorization codes, PKCE, tokens and MCP requests use the existing
controlled protocol implementation.

## Evidence boundaries

Backend metadata and token adapters deliberately reroute validated public
destinations to the local HTTP peer; the MCP connection check uses real ExMCP over
loopback HTTP. Browser authorization and the peer's CIMD-document retrieval use
actual TLS. This exercises the browser-to-Console workflow and durable stores; it
does not establish third-party interoperability or replace destination-policy,
production TLS, conformance and separate-node tests.

Record screenshots without credentials, visible states and before/after public
connection identity. Keep the milestone's broader gates open until their specific
acceptance evidence exists. Stop only the owned Console/peer process and close the
dedicated browser session when finished; leave other checkouts and sessions alone.
