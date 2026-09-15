# Remove carrier scope

## Decision and evidence

The final credential audit found dormant application-wide carrier constructors, activation/dial
scope checks and cross-tenant route lookup. Remove those accepting clauses and narrow the port
types; keep tenant routing, independent MCP application scopes and normal application defaults.
No schema migration or new authentication mechanism is required.

The Gateway constructor test failed first (6 tests, 1 expected failure), then the focused
constructor/media/activation/outgoing group passed 38 tests. Calls route rejection failed first
because it reached a repository instead of rejecting scope (7 tests, 1 expected failure); the
focused definition/admission group now passes 13 tests. The related Persistence group passes 10.
Existing tenant routing and exact conflict assertions are preserved. Media negative tests use
intentionally invalid structs because the constructor now rejects application scope.

Independent GPT 6 Astra xhigh review found no blocker. Format, warnings-as-errors compilation,
strict Credo and unused-lock checks pass for the integrated final changes. The last full carrier
checkpoint at b90845e passes 1,615 tests with zero failures and 39 exclusions; final root verification
will also cover this deletion. Database alias work is tracked separately in the platform labnote.

Final integrated verification at `58d7b34` passes all five root gates: 1,622 tests, zero failures,
39 excluded (seed 235296). All seven credential/configuration checkpoints are complete; see the
[final platform evidence](20260916-0509-finish-platform-configuration.md#final-acceptance-and-closure).
