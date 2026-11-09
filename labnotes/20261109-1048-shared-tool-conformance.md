# Shared tool conformance

Start from pushed 7c921951 (14/20). C1's compiled-room contract and C4 acceptance
remain. Extend the existing model/MCP/connection fixtures into one small compiled-
room driver; exercise identical business cases for LLM and ordinary/duplex Morse,
with only model input and rejection observation translated at the transport edge.

Initial six receptionist cases exposed a preexisting LLM continuation race:
ContinueAgent attempted JSON encoding of the internal PlatformResult wrapper.
A deterministic boundary regression reproduced both hangup and committed-transfer
variants (three tests, two failures). Project only PlatformResult.result in the
continuation; room authority still owns effects. The focused regression plus six
receptionist cases then passed (nine tests) with no JSON encoder error.

Added same-path tests for remote failure, uncertain outcome, unselected requests
and capacity recovery. LLM denies an unselected response with AgentTurnFailed and
reports saturation to its model as a rejected tool result; STS reports a bounded
native ToolCallFailed. The fixture normalizes those existing transport mechanisms
without changing business policy or claiming identical wire messages. Twenty-seven
cases passed before strengthening actual conversation, duplicate identity and
single-response multi-call acceptance per Astra's review.

The compiled duplex fixture intentionally uses its existing real-time Morse clock;
call specs reject its test-only manual clock. Playback must be consumed and its
transcript observed for continued-conversation acceptance, not merely accept text.
The first five-second observation budget was too short for queued encoded replies;
a bounded longer fixture budget is being verified. No production clock bypass.

The shared suite passes 31 cases (961776): all three paths and both modes,
controlled denied/failed/unknown outcomes, capacity recovery, repeated identities,
and one LLM response containing two calls with capacity for only one. Continued
conversation now requires the exact reply transcript; nonblocking also proves an
unrelated reply while the MCP worker remains gated. The receptionist chain uses
its required lookup/update/conversation/hangup steps; an unnecessary additional
variable-read speech response was removed. Variable reading retains its existing
focused tests. A room acknowledgement after registry consumption prevents the
fixture from racing the capability's final release.

Review correctly identified that the first native replay used the old sequence,
so it only proved watermark rejection. An assertion that the room sequence must
advance reproduced that weakness (three tests, two failures). The replay now
retains the same private call reference and source scope at a fresh sequence;
all three duplicate cases pass and still assert one start, remote submission and
completion. No production change was needed for that review finding.

Bounded warm local fixture observations from the 31-case pass:

| Path / mode | Startup ms | Room control while MCP pending ms | Release to consumed ms |
| --- | ---: | ---: | ---: |
| LLM / blocking | 18.585 | 0.173 | 6.173 |
| LLM / nonblocking | 11.912 | 0.003 | 5.875 |
| Morse / blocking | 13.878 | 0.037 | 7.192 |
| Morse / nonblocking | 22.551 | 0.235 | 6.151 |
| Duplex Morse / blocking | 16.115 | 0.175 | 21.221 |
| Duplex Morse / nonblocking | 14.925 | 0.194 | 28.974 |

The control call has a 250 ms bound. Result timing includes the test's five-ms
consumption polling interval and owner acknowledgement, not only execution.
Each case monitors its owned registry, MCP session and room DOWN. These are
synthetic local observations, not vendor latency percentiles or a production
capacity claim. The existing IntegrationOwner/source-budget, compiled native MCP
transfer and LLM MCP live-call fixtures cover original startup deadline,
source/destination overlap, rollback and cleanup. `bin/test-shared-tools` selects
those default-lane tests with the common suite and semantic adapter regressions;
external integration/live tags remain explicitly excluded.

The full default conformance command passes: 419 tests, zero failures, eight
excluded (554394). Root format, warnings-as-errors compile, strict Credo and
unused-dependency checks passed immediately before it. The final full umbrella
and Lean run is now active. Current implementation accounting is 19/20, C1–C3
complete and C4 4/5; final acceptance is deliberately left unchecked.

The first final umbrella run (369338) caught a startup regression introduced by
native usage wiring: Tree.tool_usage accepted keywords but the existing capability
usage contract also accepts maps. The existing GPTLive fake-socket voice/backend
usage test independently reproduced the CaseClauseError. Reuse Usage.normalize_context
with the existing frame identity, then project call_id and the tree-owned activation;
do not trust a supplied activation. The complete fake-socket, ordinary/duplex
capability and usage tests pass (145 tests, zero failures). Add the fake-socket
boundary to the shared conformance entry point. The failed umbrella run was
stopped early; a fresh full run will supply final evidence after the correction.

Expanded `bin/test-shared-tools` now passes 446 tests, zero failures and eight
excluded (903191), including the map usage-context boundary. The 145-test
capability/usage regression pass used seed 125396. Root format, warnings-as-errors
compile, strict Credo and unused-dependency checks pass on the corrected source.
Astra's final source/test/documentation review has no actionable findings. The
fresh full umbrella and Lean command is running; this checkpoint remains 19/20.

The conformance checkpoint is committed and pushed as `c172cd30`. Final root
acceptance now passes on that implementation: 5,213 tests, zero failures and
376 excluded (112460). All five root gates pass. `bin/verify-lean` passes its
nine-job build, generated-oracle drift check and Elixir replay (one test, zero
failures; 290521). The milestone and index are synchronized to 20/20 tasks and
4/4 checkpoints; current integration docs point to the completed acceptance.
The original research's now-delivered dispatch notes are reconciled. Historical
checkpoint evidence is explicitly separated from current status. Deployment and
vendor live acceptance remain outside this milestone.

Final GPT-6 Astra xhigh documentation/evidence review is approved with no
actionable findings. Local Markdown targets and the exact 20-complete/zero-open
implementation count are verified; this final checkpoint changes documentation only.
