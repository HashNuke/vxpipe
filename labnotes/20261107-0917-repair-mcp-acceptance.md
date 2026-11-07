# Tagged MCP acceptance corrections

All five root gates pass at the preceding checkpoint (4,991 tests, zero failures,
261 excluded, seed 774698). The additional pinned MCP conformance lane passes
three cases, actual connection-check HTTP passes four, and the remaining runtime
credential/privacy wire lane passes seven (ten non-integration cases excluded).
Together these cover all 14 tagged MCP cases without changing the dependency or
claiming official OAuth conformance from the transport harness.

A single combined Console command selected 18 local MCP/directory integration
files and produced 82 tests with two failures (seed 774698):

- `StaticMCPManagementTest` expects the proposal's credentials to reach an
  `initialize` request after the ordinary create operation returned 409 with a
  retained-ID reconnect proposal. The currently approved early duplicate guard
  precedes protocol work, so this expectation appears stale.
- `SavedMCPTransferTest` sees the source `assistant` participant still joined just
  after a completed `llm-function-call-stopped` event. Determine the exact event
  contract and transfer retirement ordering before changing the test or runtime.

Astra independently reproduced both on its first bounded command from Console:

```sh
mix test test/integration/static_mcp_management_test.exs \
  test/integration/saved_mcp_transfer_test.exs --only integration --seed 774698
```

That run produces seven tests and the same two failures. The review follows the
user's new requirement that a bug finding must include a reproduction. Source
analysis and minimal corrections were pending; neither an unexplained retry nor a
weakened lifecycle assertion is sufficient evidence of a fix.

Astra's source trace confirms that the tool-completed event precedes final source
participant teardown. An in-memory experiment monitored the actual source
participant supervisor before transfer and passed all five transfer cases without
weakening absence/presence or destination invocation assertions. That registry
lookup is private and will not be copied into Console. A second experiment uses
the existing archive writer/projection boundary and waits for the exact
`participant_left` fact, emitted after source teardown. The successful case passes.
That file run also observed an anonymous MCP stream in the untouched cold-revocation
case (five tests, one failure); its cause remained under investigation. At that
point neither the reviewer nor parent had changed production or test source.

Implemented the two reviewed test corrections. The static proposal now asserts
no new initialization, retaining the actual explicit reconnect's fresh-wire and
stable-identity checks. The successful transfer enables a Console-owned archive
writer that projects records through Calls and acknowledges only the exact source
participant's departure, bound to tenant/call/incarnation. Both original files now
pass all seven cases (seed 774698), including the unchanged cold cases. The separate
anonymous-stream observation remains open; a passing retry does not explain it.

A further fixture hypothesis is under independent reproduction: the controlled
RemoteMCPWireServer currently classifies every GET path as an MCP stream, including
root health probes. The browser fixture had observed unsolicited GET / traffic.
Do not attribute the earlier cold-case failure to that traffic without request-path
evidence; a route-classification defect can be established separately with an
explicit real HTTP request.

Astra separately proved the wire fixture's overbroad routing with real HTTP:
GET `/` and GET `/mcp` both returned SSE and emitted the same anonymous-stream
observation. A subsequent five-case path diagnostic passed, seeing only genuine
`/mcp` requests; it did not establish the earlier cold failure's request path.
Two owner-local tagged regressions now fail for the expected HTTP 200-versus-404
mismatch on root GET and off-endpoint RPC. Restrict only non-`/mcp` paths before
existing handlers; keep anonymous `/mcp` detection and all cold/warm negative
assertions intact. This repairs the demonstrated classification defect without
claiming the intermittent cold observation is explained.

The route-boundary regressions pass after the fixture correction (two tests, zero
failures). The full 18-file Console acceptance command now passes all 82 cases
(seed 774698), retaining the original cold/warm negative assertions. The earlier
anonymous request's path remains unknown; this passing run does not establish
its cause. The departure writer acknowledges the lifecycle through the public
archive/projection contract; it does not prove durable archive persistence.

GPT-6 Astra xhigh reviewed the exact final diff and red/green evidence with no
new reproduced bug or requested code change. All five root gates pass against the
final test changes: 4,991 tests, zero failures and 263 exclusions (seed 774698),
plus formatting, warnings-as-errors compilation, strict Credo and unused-dependency
checks. No production source, source-cutover or speech
state machine changed, so the Lean lane does not apply to this checkpoint.

A separate read-only Astra acceptance-gap audit reconciled two stale open boxes:
the machine-grant browser/node checkpoint already has complete method, lifecycle,
callback and rotation evidence; the tagged protocol/node execution gate now has
the 14 MCP cases, 82 Console cases and earlier seven independent-BEAM storage cases.
Closed these precise gates while retaining listed/recovery/outage and final release
acceptance. Corrected T6a's reference to listed machine acquisition: the approved
V1 directory contract explicitly excludes client-credentials grant extensions.
Custom machine acquisition/recovery remains in T6/T6b; no runtime scope changed.
