# ElevenLabs hosted agent protocol

## Starting evidence

The preceding goal turn is progress: `45d125cc` adds and pushes the bounded
Scribe codec/socket, one selected transcription observation and all five root
gates. Conversational STT and agent STS remain open. The unrelated documentation
content configuration remains the only user change; preserve it. AI gateways
stay separate and deferred.

## Wire contract and implementation

The full [agent wire schema](https://elevenlabs.io/docs/eleven-agents/api-reference/eleven-agents/websocket)
requires transcript event IDs and agent response IDs. Audio has an optional final
marker and character alignment. Explicit whole-response completion is distinct
from audio completion and interruption. Client tool calls retain their provider
call ID, arguments and response expectation. Queue waiting is not readiness.

`AgentProtocol` decodes bounded JSON, text and aligned PCM into typed native
events. It does not invent room turns, interpret event-ID relationships, publish
history, infer response completion from gaps or execute provider-selected tools.
Optional audio alignment forwards only its three recognized timing fields.
Outbound initiation, PCM, pong, tool result, user message and contextual update
have distinct documented frames; the latter two have different response semantics.

`AgentSocket` reuses the shared supervised deferred speech transport and delivers
only typed events or safe failures to its owner. The owner replies to protocol
pings immediately; sending synchronously from the socket callback would call the same
GenServer and is avoided. Runtime allocation/session integration is still pending.

`AgentAPI` is a bounded provisioning/verification operation: authenticate once,
create one agent, obtain a private signed connection and explicitly check deletion
after the consumer finishes or fails. No retry or redirect is enabled. Its request
struct and signed `AgentConnection` hide secrets in inspection; only the direct
official secure WebSocket destination is admitted. Invalid resource paths are
rejected. Cleanup failure cannot produce a successful result. This is not a
runtime remote-resource owner: VM termination or an ambiguous create response
still requires a separate ownership/reconciliation contract.

## Red-green evidence

- Nine codec tests initially fail because `AgentProtocol` is absent, then pass.
- Three socket tests initially fail because `AgentSocket` is absent, then pass,
  including one selected loopback framing case.
- Four API tests initially fail because `AgentAPI` is absent, then pass. Follow-up
  checks cover consumer failure, unsafe destinations and explicit deletion failure.
- A safe signing-status check fails before the implementation preserves status
  and stage without response text.
- An alignment privacy check fails on an extra private field, then passes after
  the codec forwards only recognized timing fields.
- Validation/status diagnostic tests fail before safe fixed hints are added.
  A first implementation incorrectly calls nonexistent `JSON.encode/1`; the
  focused suite catches it. `JSON.encode!/1` with a safe rescue replaces that call.
- Semantic and lowercase diagnostic checks fail before their fixed hint handling.
  Hints are recognized field names or fixed diagnostic words, not provider messages,
  values, signed URLs or an authoritative interpretation of the rejection.

## Selected hosted evidence and failures

All commands select `live_elevenlabs` and an individual case in its hosted-agent
protocol file. No passing Scribe, standalone TTS or other-provider evidence is
repeated. The runner alone loads private credentials; that file is not inspected.
Root commands require the workstation's PostgreSQL socket setting; one invocation
without it fails before provider access. Commands sharing the test build run
sequentially after a concrete concurrent protocol-consolidation failure. The
overlapping root run was explicitly stopped and is not completion evidence.

Creation initially fails before speech. Safe HTTP 422 diagnostics mention
`max_duration_seconds`; changing its server cap from 30 to 60 reaches HTTP 400.
Removing custom retention settings does not resolve that rejection. Controlled
section validation identifies the hosted `eleven_flash_v2_5` model selection as
the rejecting field; format, backend and ASR configuration are accepted. Existing
standalone Flash 2.5 TTS evidence remains valid; hosted acceptance is separate.

Fixed Gemini 3.5 Flash Lite appears in the agent catalog. The public synthesis
catalog lists five reviewed models with numeric cost factor 1.0; this does not
prove equal billed prices or hosted compatibility. `eleven_v4_turbo` with George
passes all eight definition-prefix checks in 24.6 seconds, seed 130910. Each
successful creation/signing operation requires its own HTTP 204 deletion.
The permanent configuration probe now validates one complete definition rather
than repeating the diagnostic prefix matrix.

The first hosted speech attempt fails on an unclassified native event. A safe
known-kind diagnostic identifies a rejected ping in the second attempt. Local
red tests then correct two assumptions: ping IDs are opaque signed integers,
and optional `ping_ms` is a latency estimate rather than a mandatory delay.
Its precise failing live field was not captured and is not inferred. A third
attempt survives the ping but times out without enough stage observations.

A native `client_error` red test fails before numeric-only decoding is added.
Private error names/messages remain excluded. After enabling this event, safe
byte counts show that a fourth attempt receives a 28-byte user transcript,
26-byte response and 61,440 bytes of PCM but no whole-response completion
within its 15-second deadline (seed 528938). It deletes its agent despite
the outer assertion failing. Audio receipt is not falsely counted as completion.

Read-only model metadata lists reasoning efforts minimal/low/medium/high for the
selected backend, with no supported `none` value. The definition uses `minimal`
and a 128-token response cap instead of the initial 32-token/default-reasoning
configuration. A saved-agent read confirms that this setting and the requested
completion event survive provisioning (one metadata test passes, 4.0 seconds,
seed 794987). This operation opens no speech connection.

The final selected conversation passes one test in 10.1 seconds, seed 455275.
It reuses the public 4.16-second sample with up to five seconds of paced silence,
keeps total input below ten seconds, and stops input once explicit completion
arrives. It disables speculative generation and backup LLMs, sets idle/initial
wait to 30 seconds, requests one short response and uses 16 kHz PCM. The known
final word `telescope` and expected response text match. Output is 56,320 bytes;
audio and completion event IDs both match the response event. The optional final
audio marker is false, so that marker is not made a completion prerequisite.
The passing provider call is not repeated.

Continuing silence and changing the idle-turn configuration coincide with the
passing completion observation; the experiment does not isolate their causal
effects. Do not claim a universal provider requirement from this single case.
No audible device, tool execution, room publication or played-prefix history
settlement is verified. Voice recording is disabled; neither zero retention nor
deletion of hosted conversation records is claimed. Remote agent cleanup is
explicitly checked, with runtime crash/ambiguous-create recovery still pending.

## Current local verification

The final codec, provisioning and socket suite passes 24 tests, zero failures,
including the selected loopback transport case (seed 907074). New tests also
cover model-catalog privacy, safe native-kind classification and numeric-only
provider errors. All five root gates pass: formatting, warnings-as-errors
compilation, strict Credo, default tests and unused-dependency checks. The root
seed-149103 run reports 2,959 tests, zero failures and 89 exclusions, including
1,752 CallEngine, 522 Gateway and 194 Console checks. The staged documentation
links resolve and both worktree/cached whitespace checks pass. The central
provider architecture now explicitly points AI gateways to their separate
deferred routing milestone without adding a runtime registry entry.
No speech/source state machine changes in this preparation checkpoint require
repeating Lean. Runtime STS implementation will require its own Lean acceptance.

## Remaining milestone scope

- [x] Verify the selected hosted configuration and native response identity/completion.
- [ ] Establish call-spec-derived agent/tool provisioning, reuse and explicit cleanup.
- [ ] Implement owned STS session readiness, input turns, credited output, interruption,
  transcript/history settlement, delegated tools, policy, usage and cancellation.
- [ ] Prove compiled room startup, scoped publication and supported Console metadata.
- [ ] Complete the separate Scribe input-boundary design and conversational STT.
- [ ] Pass root/Lean and rendered acceptance for the completed capability.

These are preparation components, not a narrower replacement for the requested
room-capable conversational STS integration. The milestone and active goal remain open.
