# Platform MCP session and token renewal

## Decision

Use a configurable access-token lifetime, defaulting to 3,600 seconds (60 minutes),
while retaining the existing 30-day authorization grant and refresh rotation.
`VXPIPE_MCP_ACCESS_TOKEN_TTL_SECONDS` accepts integers from 1 to 86,400. The limit
bounds operator configuration to one day; it is a product choice, not an OAuth
mandated maximum. Runtime configuration validates the value before startup. Both
Boruta's client policy and persisted access-token issuance consume the same value.
Existing access tokens keep their recorded expiration. Newly exchanged or
refreshed tokens are capped by the grant's remaining lifetime.

Changing the access-token lifetime reduces refresh frequency. It does not repair
session recovery or credential races, which require separate validation.

## Deployment recovery defect

The real Codex 0.169.0 app-server exposed a separate server-side defect. With a
lost session and the supported `2025-06-18` protocol header, ExMCP fell back to its
latest protocol version before checking session existence. It rejected the
request with 400 for a version mismatch rather than 404 for a missing session.
Codex's tool call then hung. A terminated session whose record still existed did
not expose this bug, which explains why the existing DELETE-session test passed.

The checksum-pinned `platform-session-recovery.patch` preserves missing-session
information through protocol validation. Supported headers now reach the 404
reinitialization path; genuinely unsupported headers still return 400. Existing
session version checks and authentication are unchanged. `bin/patch-ex-mcp`
applies this separately from the existing request-credential patch and refuses
unrecognized source changes. This follows the
[MCP session recovery contract](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports#session-management).

Regression tests first reproduced the incorrect 400, then passed with the patch.
All 47 platform MCP tests pass, including the unsupported-version negative case.
Patch installation, repeat application, historical request-credential upgrades,
and preservation of local source changes are checked by the shell test suite.

After deployment of this patch, the same running Codex process successfully called
`list_role_options` immediately before and after the container restart. It did not
require a client restart, reconnect command or browser login. A subsequent
accelerated access-token expiry also renewed successfully, issuing a 60-minute
token. Both temporary validation accounts were then archived and their browser
sessions and grants revoked; temporary client credentials were removed.

## Live validation, 2026-11-17

Tests used the public `vitrum.vxpipe.com` HTTPS endpoint, a temporary admin with a
cryptographically random password, real browser consent through agent-browser,
PKCE S256, and a Python MCP wire client. Only discovery, authentication and
read-only MCP operations were exercised. Each Python request closed its HTTP
connection; no continuously open socket or GET stream was required.

| Behavior | Evidence |
| --- | --- |
| Access lifetime before this change | Token responses returned `expires_in: 599`; database timestamps confirm approximately 600 seconds. |
| Grant lifetime | Database timestamps confirm approximately 2,592,000 seconds (30 days). This was inspected, not tested by waiting 30 days. |
| Expiry and refresh | Only a test token's database expiry was shortened to 60 seconds. Access returned 401 after expiry; refresh returned 200; the same MCP session then returned 200. No browser reauthorization. |
| Deployment session loss | An established session returned 404 after the explicitly approved container restart. Initialize and tools/list using the identical pre-restart access token succeeded, and refresh succeeded. |
| Refresh-token replay | First refresh returned 200. Reusing the old refresh token returned 400 `invalid_grant`; both successor access and refresh credentials then failed. |
| Concurrent refresh | Two requests using the same refresh token returned one 200 and one 400. The successful response's access token then returned 401. |
| Idle timeout | The deployed session-manager module defaults to ETS, 3,600 seconds idle and a 60-second cleanup cadence. An isolated instance of the deployed module rejected its own session after accelerated inactivity and cleanup. No hour-long public-endpoint wait was performed. |

Systemd owns the container lifecycle. Direct Docker restart was followed by a
supervisor restart, invalidating the first accelerated-expiry test's session.
The expiry test was repeated after stabilization and passed. Future operational
restarts should use `systemctl restart vxpipe.service`.

The Python validation account was archived, browser sessions and OAuth grants
revoked, credentials rejected over HTTP, and temporary secrets removed. These
experiments establish server behavior; they do not establish which event caused
any historical Codex reconnect prompt.

## Client implications

Clients need to distinguish expired OAuth access (`401`) from a missing MCP
session (`404`). Refresh can retain a live MCP session because its identity is
bound to the grant, not to a specific access token. After session loss, a new
initialize can use the existing OAuth credentials.

Rotating credentials must be persisted and refresh operations serialized when
multiple processes share them. A lost successful refresh response or competing
refresh can cause the next use of the old credential to revoke the grant. This
is an observed availability consequence of reuse detection, not proof of a
security defect or of a race in a particular Codex build.

Actual Codex-client verification and deployed 60-minute configuration are tracked
in the [implementation labnotes](../../labnotes/20261117-1227-configure-mcp-token-lifetime.md).

The actual CLI/app-server passed reactive refresh after expiry, reuse of saved
credentials by a fresh client process, and concurrent refresh from two processes
sharing one saved login. Follow-up calls succeeded and the grant stayed active.
These results differ from raw concurrent Python refresh requests: the tested
Codex build enables OAuth refresh coordination. No refresh-replay policy was
weakened, and no Railway configuration was changed.

## Alternatives and literature

- Retaining the hardcoded ten-minute policy prevents operational tuning. Both MCP
  and OAuth recommend short-lived access tokens, but neither specifies ten
  minutes. Refresh should avoid making normal token expiry an interactive login.
  See [MCP authorization](https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization#token-theft)
  and [RFC 9700 section 4.14](https://www.rfc-editor.org/rfc/rfc9700.html#section-4.14).
- Increasing token lifetime alone does not fix refresh replay or missing-session
  recovery. Sixty minutes is a chosen operational default, not a universal
  recommendation. For comparison, Microsoft documents default access lifetimes
  of [60–90 minutes](https://learn.microsoft.com/en-us/entra/identity-platform/configurable-token-lifetimes).
- Removing refresh rotation is outside this change. Reuse detection is deliberate
  security behavior in [RFC 9700 section 4.14.2](https://www.rfc-editor.org/rfc/rfc9700.html#section-4.14.2).
  A bounded overlap policy is a possible separate design: Auth0 documents
  [rotation overlap](https://auth0.com/docs/secure/tokens/refresh-tokens/configure-refresh-token-rotation)
  for concurrency and retries, with security tradeoffs. Vxpipe currently stores
  credential digests only, so returning an earlier successor would need an
  explicit storage and threat-model decision.
- Durable MCP-session storage or a newer stateless protocol is a separate
  transport decision. Neither is necessary for restoring access with a new
  initialize and an existing grant.
