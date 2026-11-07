# MCP runtime across nodes

Run the production Calls renewal coordinator, configured credential resolver and
ExMCP client in independent BEAM processes, sharing committed PostgreSQL records.
Reuse the isolated database-node fixture; start only the MCP and HTTP applications
needed by the runtime. Controlled OAuth and MCP HTTP services provide token-response
and SSE barriers, with synthetic saved delegated grants and client credentials.

The first fixture run exposed two setup mistakes: ConnectionKey.new requires
scope: :tenant plus tenant_id, and a per-test supervised Repo stopped before the
committed tenant cleanup callbacks. Corrected the key and moved Repo ownership to
setup_all. The three token tests reached their intended outcomes even in that run;
their failures were cleanup failures. The second run passes four cases, including
revocation after token redemption, cross-node duplicate fencing, unrelated tenant
progress and abrupt claimant death. Removed all ten original failed-run tenants
using the fixture name and exact first-run creation window, with an expected-count
guard. Subsequent per-test cleanup now succeeds while the setup_all Repo is alive.

The real-client stream case found an implementation issue: SSEClient announces
clean EOF and schedules reconnect, while HTTP.receive_message reports EOF as a
fatal connection close. ExMCP.Client then discards its transport even though the
same SSE process resumes with the newly rotated credential. A focused real-SSE
test reproduces the incorrect connection_closed result before receiving resumed
events. After the fix it receives the event, and the actual client can execute a
second tool without reinitialization. Terminal SSE death must still unblock the receiver;
only clean stream resumption may retain the existing client/session. Do not retry
or replay any tool request, and keep credential rejection before submission.

The DELETE assertion also exposed a separate fixture assumption: Connections.close
retires the local owner, whereas explicit ExMCP.Client.disconnect owns graceful
remote session deletion. The fixture now invokes that public client operation
before observing local retirement. It rotates again immediately before disconnect
to prove DELETE resolves current credentials rather than the preceding POST token.

The two focused EOF/terminal-death regressions and the full provider file pass
(12 tests); all seven patch preparation/upgrade tests pass. The checksum-pinned
upgrade now targets the immediately preceding reviewed patch, preserving the exact
dependency revision and rejecting unrecognized older or modified source states.
The final five-case cross-node rerun passes, including a second successful tool
POST after resumption and monitoring the original SSE, owner and client at cleanup.
Independent Console review found a fixture barrier race: the notification preceded
reading the hold flag, so enabling the next tenant's request could release the
first held response. Snapshot the hold flag before notifying. The five cases pass
after that fix, and independent source re-review is clean.

Independent transport review found two further receive signals: matching reconnect
notifications accumulated, and a resumed GET returning 405 left the receiver
waiting. Two added tests failed for those exact reasons (14 tests, two failures).
Consume matching connection notices and return the existing unsupported-stream
result on 405. All 14 provider tests and seven patch preparation tests now pass.
The full MCP lane passes all 184 tests, including the pinned reference/conformance
fixtures. Independent transport re-review is clean. A 405 leaves an owned dormant
listener while POST results use their existing path; explicit disconnect owns
cleanup. The direct 405 regression proves the receiver result, not a new
actual-client POST/cleanup acceptance scenario.

Scope: these five cases prove delegated renewal and transport across independent
nodes. Machine renewal, caller cancellation, renewal-runner restart and authenticated
browser/callback acceptance stay open. Do not use these cases to close the complete
cross-node grant workflow. No UI source or speech state machine changed here.

Independent documentation review accepts completing the narrow T7 transport
revocation gate using the committed web/phone/transfer cases plus these actual-client
independent-node cases. It leaves the broader T5 grant and T7/T8 release gates open.
Corrected stale per-admission and MCP-lane pending text and named the remaining
caller cancellation and renewal-runner restart checks explicitly. The new subtask
split records existing requirements and preserves dependency order.

All five root checks pass: format, compile with warnings as errors, strict Credo,
full test suite and unused-dependency check. The umbrella suite passes 4,987 tests
with zero failures and 229 excluded (seed 108915). The tagged MCP lane passes 184
tests, the Console cross-node lane five and patch preparation seven. Local Markdown
links and diff whitespace checks pass. No UI source or speech/source-cutover state
machine changed, so rendered inspection and a new Lean run do not apply to this
checkpoint. Both independent exact-index adversarial reviews are clean.
