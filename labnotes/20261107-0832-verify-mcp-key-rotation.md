# MCP key rotation across nodes

Follow the open operational acceptance task in the integrations milestone. The
cross-node callback checkpoint is committed separately as 58fe7a67. Its root suite
is still running; focused callback/renewal acceptance and static checks pass.

Astra's source review identified an important test boundary: the renewal coordinator
captures its repository/keyring context before HTTP. A new-primary claim already
rewrites the envelope under the new key, while an in-flight old-primary operation
can recreate an old-key envelope after another node runs re-encryption. Updating
configuration alone does not change the captured context. This is expected behavior
under the existing all-writers-transition requirement, not a production defect.

Write real HTTP cases for both delegated and machine renewal before adding fixture
context-switch/read operations. Start with old-primary writers that know both
decrypt keys; hold a redeemed token response, rotate from the other node, verify
unchanged claim/payload and exclusive redemption, release the old writer, then
drain/transition writers and repeat the batch. Only afterward remove the old key
on both nodes and prove reads plus a subsequent renewal. No fake dynamic keyring
or manually completed production renewal is used.

The initial cases fail for the missing fixture context-switch operation. This is
a test-harness baseline, not a reproduced product failure. Extend the existing
independent-node fixture and reuse its explicit HTTP release/completion signals.

Both real-HTTP cases pass (seed 888502). Re-encryption preserves the entire resolved
payload including the live claim; a second node cannot redeem again. Releasing the
captured old-primary writer does recreate an old-key envelope, which the new-only
reader cannot decrypt. After completion acknowledgement and writer transition,
a final batch rotates that one row. Both peers then read with only the new key and
a subsequent renewal advances the grant once more. Public connection metadata
stays unchanged throughout. Clarified drain/final-batch and ambiguity-fence handling
in the existing operator and MCP runbooks; no new runtime behavior is required.

The earlier root run (seed 774698) reached an existing Telnyx max-duration startup
failure (`media_harness_failed`) after all prior children passed. It is still running;
the focused same-seed harness rerun and full root validation remain pending. No
telephony source changed. Record this verification barrier in the milestone.

All 16 Telnyx harness tests pass unchanged with the original seed 774698. The
umbrella run is still live and must finish before the final serial rerun. Do not
infer the intermittent startup failure's cause from this narrower passing rerun.

Astra found that the installation-wide re-encryption batch used the ordinary
shared test database. That could touch unrelated committed records or fail on
their unknown keys. Added an isolated-database precondition (two expected failures)
and an opt-in disposable database in the existing node fixture. A separate test
Repo migrates/seeds that database; both BEAMs use their own one-connection Repo
against it, and supervised teardown precedes dropping the database. Existing
runtime cases retain their current database fixture.

Also switch A's configured keyring while its token response is held. Completion
still writes with the old captured context, directly proving why configuration
replacement alone does not drain an operation. Both strengthened isolated cases
pass (seed 806548). A combined run launched while another shared-database fixture was active
observed two extra records in three existing zero-count assertions; that contaminated
run is not green evidence. Run the combined lane serially after the isolation fix.

Astra's isolation/context re-review is clean. Correct the milestone wording to
reflect that both nodes read with only the new key while the subsequent renewal
runs on A; this test does not claim a second subsequent renewal on B. The runbook
clarification is independently reviewed and no production defect/change is claimed.

The initial umbrella run has now finished: 4,991 tests, one failure, 261 excluded
(seed 774698). The sole failure is the previously recorded Telnyx startup case;
the unchanged focused rerun passes all 16 tests. The combined OAuth lane is now
rerunning without concurrent shared-database fixtures, followed by the full
same-seed root rerun. Format, warnings-as-errors compile, strict Credo and the
unused-dependency check pass after the isolated fixture changes.

The serial combined lane passes all 27 tests (seed 589235):

```shell
mix test test/integration/mcp_key_rotation_nodes_test.exs test/integration/mcp_callback_nodes_test.exs test/integration/outbound_mcp_oauth_test.exs test/integration/mcp_runtime_nodes_test.exs test/integration/mcp_renewal_nodes_test.exs --include integration
```

Finally strengthen the new-key-only phase to renew on A and then B, with both peers
reading each result. Exact token totals advance to two and three, revisions advance
to three and four, and delegated refresh tokens rotate while machine grants remain
refresh-token-free. Both focused cases pass again (seed 701522). Astra's final loop
review is clean and confirms that the evidence now establishes reads and subsequent
renewal on both nodes. The full same-seed root rerun is the remaining checkpoint gate.
