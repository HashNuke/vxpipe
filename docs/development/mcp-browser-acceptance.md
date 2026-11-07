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
saved-credential management, with its tool list inspected on mobile. The four
static startup modes now pass real create, wrong-credential rejection where
applicable and saved testing. Anonymous, bearer and custom-header disconnect also
pass. Basic failed replacement preserves the working record. Tool lists render on
mobile, but pointer selection of Tools can
dismiss a recentering management dialog; Basic tools were verified with keyboard
navigation and that pointer interaction remains an open UI fix. The complete
[integrations milestone](../../labnotes/milestones/integrations-directory-and-tenant-mcps.md)
also requires other authentication methods, listed/retained identity, independent
node callbacks, native override/restore, outage states and final release checks.

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

Own-client mode still requires explicitly provisioning a fixture client and is not
a ready-made browser scenario yet.

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
