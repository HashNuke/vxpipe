# Cross-node renewal lifecycle

Extend the existing independent-BEAM acceptance fixture for the remaining machine
grant and caller/runner lifecycle gates. The previous checkpoint committed the
delegated token/transport cases and SSE correction; this checkpoint initially adds
acceptance of existing production behavior, not a production implementation change.

Write the new tests first, then add fixture support for saved client-credentials
metadata and lifecycle observation. Both grant types now exercise token rotation
and revocation on real ExMCP POST, resumed GET and explicit DELETE. Machine grants
start without a refresh token and must still omit it after both rotations, although
the fixture token endpoint returns one.

Four lifecycle cases combine delegated/machine grants with caller cancellation or
registered renewal-runner restart. They hold a real token response after redemption,
observe caller/worker retirement through process monitors, release the late response,
then verify that a second BEAM cannot redeem again. The persisted grant stays
unchanged except for its durable claim and requires reconnect at the claim deadline.
A fresh unrelated grant must renew on the original node, including after restart.
Fixture observation uses Task.Supervisor children and Supervisor.which_children,
without asserting private runner state or sleeping for ordering.

The HTTP fixture announces completion after its response handling attempt, including
closed-client failures. This signal plus worker termination bounds the late-response
check; it does not claim physical token-socket cancellation. All eleven combined
node cases pass on the first complete fixture run. No production behavior change
or artificial failing baseline was necessary. Independent review, the broader
OAuth boundary lane and root gates are pending.

The broader 25-case OAuth/node run exposed three stale machine-grant assertions:
they expected a token-only runtime projection, although the committed transport
contract also projects saved MCP headers privately for request authentication.
The three failures showed only the expected header field. Keep exact-map equality
and add the original submitted headers, preserving the exclusion of registration,
private-key and refresh secrets. Independent source review confirms the Calls
projection and MCPTransportCredentials contract; no runtime change is needed.

Adversarial fixture review found that the unconditional response-finished signal
could also describe the held-response timeout. Add a correlated release signal
inside the explicit release branch, and require it before completion in all four
lifecycle cases. The strengthened tests failed four times for the missing release
signal before the fixture correction. This closes a false-positive path without
changing production cancellation or retry behavior. The corrected combined lane
passes all 25 tests with zero failures. Both independent source re-reviews are
clean. Documentation review keeps browser/callback acceptance open and confirms
the completed machine/caller/runner scope; root gates are pending.

Format, warnings-as-errors compilation and strict Credo pass. The first umbrella
run (seed 94648) hit an existing Twilio media-harness startup failure in the
disconnected-startup case, before the isolated browser checkout setup began.
All 14 tests in that file pass on an unchanged same-seed focused rerun. No telephony
source or test changes were made. The unchanged same-seed umbrella rerun passes
4,987 tests with zero failures and 235 excluded; the unused-dependency check also
passes. All five root gates are green. Browser/callback and release acceptance
remain separate open tasks.

Remove the unrelated STT test-maintenance entry from the MCP completion checklist
after the user questioned its relevance. Its separate commit and labnote retain
the historical evidence; it is not an MCP implementation task.
