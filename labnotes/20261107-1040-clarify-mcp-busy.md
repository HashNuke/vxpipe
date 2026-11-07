# Clarify busy MCP connection feedback

Actual authenticated listed CIMD retained reconnect returned HTTP 429
`mcp_connection_busy` after successful discovery and retained-record lookup. The
production dialog displayed “Could not connect. Check the credentials and retry.”
The saved public path/status/code trace and rendered screenshot reproduce the
misleading feedback. No failed authentication or credential change occurred.

Add a focused component regression for that real HTTP boundary: show busy/retry
guidance, retain the draft and credential inputs, keep explicit retry available,
and do not report success. The test fails with the old credential-blaming message
(one failure/four passes) before adding the HTTP 429 branch. No automatic retry or
connection-limiter behavior changes are proposed. Verify the corrected rendered
message against an actual busy response and run relevant frontend/root gates.

The five-case component group is now green. The existing preflight runner enforces
a 500 ms tenant request interval in addition to its active-operation cap, explaining
why fast scripted discovery/reconnect sequences can legitimately receive this busy
response. The correction changes only feedback; it does not weaken those bounds.
Full frontend tests, TypeScript and lint are running. The ongoing root rerun tests
the archive monitor correction and unchanged backend; no backend behavior changes
for this UI message.

Astra independently reproduced the old component failure in a temporary copy
(one failure/four passes) and verified the corrected five-case group. The corrected
built Console was exercised against another actual HTTP 429; both desktop/mobile
screenshots show busy/retry guidance with fixed retained setup and an available
Reconnect action. The saved status trace confirms `mcp_connection_busy`, and a
later explicit retry reaches provider consent. No response was fabricated.

The full frontend run reaches 1,065 tests with one failure: the preexisting retained
conflict case counts all POST requests and observes two instead of one. Investigate
that test's background discovery accounting before changing its assertion. TypeScript
and lint have not run yet because the sequential command stopped on this failure.

The frontend failure is now independently isolated to request accounting, with
explicit discovery acknowledgement producing two deterministic failures. It is
tracked in [reconnect mutation accounting](20261107-1044-count-reconnect-mutations.md)
and does not require a change to production reconnect behavior.

Final frontend verification passes all 1,065 tests across 139 files, TypeScript
and ESLint. Independent review/red-green proof and relevant rendered acceptance
are complete. The separately tracked full backend root gate remains pending.
