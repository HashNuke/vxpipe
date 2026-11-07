# OAuth callbacks across Console nodes

The existing independent-node lane proves durable attempt races and runtime
renewal, but does not start OAuth through one Console node and complete the callback
through another. Add that missing acceptance using real persisted identity/session
and installation state, encrypted attempts and actual local OAuth/MCP HTTP.

Use a newly created disposable PostgreSQL database, migrated before setup, so the
test never resets the checkout's existing installation or users. Both independently
supervised BEAMs must have distinct OS and PostgreSQL backend identities. Session
cookies and the database are shared; node-local OAuth transaction state is not.
The test transport routes validated public fixture destinations to loopback and
does not establish external TLS or rendered browser acceptance.

Write acceptance cases before fixture support. Production behavior is already
implemented; a fixture boot failure is not evidence of a production defect.
GPT6 Astra xhigh source review is running in parallel with adversarial scope.

The first fixture execution failed because the existing database-node helper owns
a one-connection pool, while Ecto's migration lock needs two connections. Migrations
now run without that lock only in the newly created database, before the second
peer boots or any setup occurs. This fixture has exactly one migrator. Both peers
retain one connection so their asserted backend identities are stable.

The initial four cases pass: CIMD and DCR each start on node A and finish on B,
rejecting another login session before the valid callback and replay afterward.
Remote logout and installation URL changes reject callbacks without token exchange
or an attempt claim. A fifth passing case stops the initiating BEAM before consent
completion; the surviving node finishes from shared durable state alone.

Astra confirmed cookie recycling creates a fresh Conn, so node B cannot inherit
node A's assigns or authenticated session. It requested exact 401/session_required
assertions instead of allowing arbitrary redirects, and noted the initial cases
used only a Superadmin. Tightened that assertion and added an ordinary role with
tenant-assigned service read/write grants. Removing write on the other node revokes
the old session; a fresh login still cannot start OAuth. The new focused case passes
and observes no additional registration or token exchange after permission loss.

No production code changes were needed. This lane uses the real Endpoint pipeline
through ConnTest, not a listening Console HTTP server; it does not establish browser
redirect/cookie handling or external TLS/CIMD retrieval. Revocation and installation
changes here precede redemption, not a held mid-callback protocol operation.

Source review also found old documentation describing independent-node races and
production UI callback recovery as pending. Reconciled those descriptions while
retaining full browser/release gates and the newly tracked cross-node key-rotation
acceptance task. No runtime/security defect was confirmed in the reviewed OAuth
implementation. Astra's six-case source re-review is clean.

From the Console child, the combined command passes 25 tests with zero failures
(seed 725982):

```shell
mix test test/integration/mcp_callback_nodes_test.exs test/integration/outbound_mcp_oauth_test.exs test/integration/mcp_runtime_nodes_test.exs test/integration/mcp_renewal_nodes_test.exs --include integration
```

Root format, warnings-as-errors compilation and strict Credo pass. The default
umbrella test run and unused-dependency check remain pending. No UI or speech/source
state-machine implementation changed, so this checkpoint needs neither rendered
inspection nor Lean rerun; broader milestone browser gates remain open.

Astra's completion audit found that separate callback and seeded-renewal lanes
did not prove renewal of the callback-created grant. Reopened the composite T5
checkbox and added that composition to both CIMD/DCR cases. Node A now refreshes
the connection created by callback on B; B observes both tokens rotated, revision
2, unchanged connection metadata, a cleared claim and exactly one extra token
request. The fixture wires the real grant repository and refresh coordinator.
The first test run lacked that fixture operation; after adding it, the strengthened
combined command above passes all 25 tests (seed 593520). No production change.
Astra's final source audit confirms this closes the composition gap and supports
the T5 checkbox, retaining the documented operational/browser limitations.
