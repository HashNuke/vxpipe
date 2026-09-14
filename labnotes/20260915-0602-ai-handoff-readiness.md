# AI handoff readiness

This checkpoint continues the AI delivery slice after human web acceptance in
`6624c96`. The remaining AI requirements are independently exercised tool/MCP
readiness, wait configurations, ordered greeting, privacy and resource retention.
No UI change is needed.

## Boundary review

The existing activation graph initializes scoped MCP connections before the model
session. Local descriptors are compiled synchronously, and the invocation registry
and its supervisor must answer readiness before the runtime is usable. There is no
separate asynchronous local-tool startup operation. The native fixture pauses the
real registry readiness reply; it does not invoke a tool to warm it or invent a
new production readiness mechanism.

The native matrix uses default, URL, per-slot nil and whole-object nil waits. It
keeps caller STT and full-mix/individual recording enabled, delays actual scoped MCP
initialization, then delays the local registry reply while voice becomes ready.
It checks held microphone/text exclusion, no readiness-time tool invocation,
retained media/room actors, cue-before-greeting audio and a usable destination MCP
binding after release. Existing model/voice and recovery cases remain in place.

## Verification and detours

Review of the first run caught a fixture ordering issue: connecting with automatic call-ready waiting before acknowledging the
controlled caller STT creates a circular test wait. The fixture now connects the
peer first, acknowledges STT, then waits for call readiness. This changes no runtime
behavior. The original run finished with a fixture compiler rejection: host tools must use
their static name as the local key. Replaced the invented alias with
`test_agent_tool`; no schema change is warranted. The first run never reached the
reviewed STT ordering issue. Evidence: `vxpipe-ai-tools-first.log`, one failure.

The second URL run reached post-release history verification: readiness, retained
resources, recording/STT exclusion and cue/greeting order passed. Its assertion
incorrectly compared a request ID with message content; the shared RTVI helper uses
a separate content argument. The new cases now pass explicit distinct transfer,
held and post-transfer texts, so history exclusion is substantive. Evidence:
`vxpipe-ai-tools-second.log`, one fixture assertion failure. Added a delayed
source acknowledgement and checked that it cannot speak or enter spoken history.

## Focused acceptance evidence

- Native matrix: `mix test test/vxpipe/gateway/http/human_transfer_webrtc_test.exs
  --name-pattern 'AI handoff gates MCP and local tools'` from Gateway passed four
  cases, zero failures, 62 excluded (`vxpipe-ai-tools-matrix.log`). After that
  run, strengthened completion observation to reject a second completion while
  awaiting greeting end, replayed client-ready, included a real private sentinel in
  MCP configuration and explicitly compared the retained tool/MCP resource tokens.
  The full umbrella run verifies these final assertions.
- Owning engine checks: agent transfer room, activation supervisor and MCP owner
  test files passed 22 cases (`vxpipe-ai-engine-focused.log`). They cover
  generation-fenced operational readiness, actual host/remote bindings, failure,
  total deadline, restoration, scoped history/Variables and fresh re-entry without
  repeated first-message playback.
- No production behavior changed in this checkpoint: existing handoff coordination
  satisfied the newly exercised contracts. The failed initial runs were fixture
  construction/assertion errors, not runtime red tests. No new dependency,
  deadline, protocol, configuration field or UI was needed.

## AI slice acceptance audit

- Destination readiness: existing native model initialization and voice delays plus
  the new independent scoped MCP initialization and local registry reply delay.
  Local descriptors use the ordinary compiler and static host-tool name. MCP is
  initialized without discovery or dummy invocation during handoff; the pinned
  catalog is already supplied by call preparation. A real remote tools/call starts
  only after caller conversation resumes.
- Privacy: held microphone input reaches neither retained caller STT nor recordings;
  held text is rejected. A delayed source acknowledgement cannot request speech or
  enter spoken history. Destination model requests/greeting remain suppressed.
  Wait/cue output stays private and subsequent real caller audio reaches STT and
  recording. Model history retains admitted caller content and the delivered
  greeting, excluding the distinct held texts, URL and private MCP sentinel.
- Release: real received Opus audio distinguishes the configured 250 Hz wait,
  1000 Hz cue and 1500 Hz greeting. Nil silences only waiting; the cue still precedes
  conversation. Default waiting is decodable. Completion and greeting occur once;
  subsequent client-ready does not repeat either. The source retires after handoff.
- Resource reuse: caller connection/output/input/ingress, STT transport, room
  service identities and prepared local/MCP tool resource tokens remain installed.
  Destination voice is not redialed. Existing model/voice failure cases recover
  spoken source conversation over the retained caller peer.
- Configuration/privacy acceptance is native with controlled provider and URL-fetch
  boundaries. Existing live URL retrieval and rendered AI-transfer evidence remain
  in earlier checkpoint logs; no claim of live MCP interoperability or physical
  phone audibility comes from this native matrix.

## Final verification and delivery

All five root gates passed on the final test changes:

- `mix format --check-formatted`
- `mix compile --warnings-as-errors`
- `mix credo --strict`
- `mix test --max-cases 4 --seed 235296`
- `mix deps.unlock --check-unused`

The eight child suites total 1,415 tests, zero failures and 16 integration exclusions.
Gateway has 401 cases, including the final four AI cases and the existing native
model/voice, recovery and Morse cases. Structured results are in
`vxpipe-ai-handoff-results.json`; per-gate logs use `vxpipe-ai-handoff-*.log` in the
local temporary directory. The result aggregation initially expected nine child
summaries; inspection corrected that reporting assumption to the actual eight.
Every gate itself exited zero, and the corrected aggregation confirms the totals.

AI handoff is accepted. Fourteen checkpoint tasks remain: phone parity six,
changing/multiple listeners six and final audit two. The milestone remains open.
The next delivery slice is phone parity. No development server was restarted, and
another agent's documentation-site/visual-labnote changes are preserved.
