# ElevenLabs turn contracts

## Starting evidence

The preceding goal turn is progress: f8dda5a5 implements, verifies and pushes
scoped ElevenLabs TTS with all root/Lean gates, 216 frontend checks, four rendered
forms and one selected live phrase. The worktree retains only the user's
unrelated documentation-content configuration change. Keep that untouched.

## Current primary sources

Scribe's [wire reference](https://elevenlabs.io/docs/api-reference/speech-to-text/v-1-speech-to-text-realtime)
acknowledges model, format and commit strategy. Partials replace previous text;
commits finalize a segment. The [commit guide](https://elevenlabs.io/docs/eleven-api/guides/how-to/speech-to-text/realtime/transcripts-and-commit-strategies)
documents automatic buffered commits even in manual mode. The wire has no
speech-start event or commit-cause field. None of those segment observations
alone supplies the room's required turn authority.

The current [agent wire specification](https://elevenlabs.io/docs/eleven-agents/api-reference/eleven-agents/websocket)
is richer than abbreviated examples: user/agent transcripts carry event IDs,
agent text also has a response ID, and audio has an optional `is_final` marker.
The [client events guide](https://elevenlabs.io/docs/eleven-agents/customization/events/client-events)
adds explicitly enabled `agent_response_complete`, including pending tool work.
These change the next implementation action: verify real response identity and
completion rather than inventing an audio-gap generation boundary.

The [agent creation schema](https://elevenlabs.io/docs/api-reference/agents/create)
supports prompt, tools, audio formats and client events. Provisioning ownership
affects the public contract; the user was asked whether to derive the hosted
agent from the Vxpipe call spec or use an existing ElevenLabs agent. Provider
wire work can proceed independently while that optional preference is pending.

## Planned checkpoint

- [x] Establish a closed provider-owned Scribe configuration/codec, preserving
  transcript-segment semantics and scoped private authentication.
- [x] Verify supervised base64-audio and explicit-commit framing locally.
- [x] Verify one bounded selected Scribe protocol stream with the reused public sample.
- [x] Record the separate turn-owner requirements before room/Console admission.
- [x] Verify repository gates and commit the protocol checkpoint.

This is preparation for the full requested conversational STT capability, not
a transcript-only substitute for its acceptance. Do not register STT in the
service/room catalog until a genuine boundary owner is integrated and proven.

## Red-green and live evidence

- Initial six local checks fail because the Scribe modules do not exist; the
  closed codec and supervised worker make all six pass.
- A subsequent privacy test fails on raw provider message delivery. The worker
  now decodes before notifying its owner, forwarding typed events or safe errors.
- Two selected live connections fail acknowledgement validation before any audio
  is sent. A diagnostic attempt does not identify which fields are absent; do
  not claim that observation. The official schema makes individual config fields
  optional. A local optional-field test fails, then passes after accepting absent
  fields while still rejecting present mismatches.
- One selected protocol stream then passes: 1 test, zero failures, 5.8 seconds,
  seed 576727. It reuses the 4.16-second public fixture plus one second of silence,
  sends 5.16 seconds of PCM, and retains the known final word `telescope`.
  No TTS generation, retry or unrelated live provider runs occur.
- After that passing call, the privacy delivery refactor changes raw forwarding
  to typed events. All seven local checks pass in 0.2 seconds, seed 99304,
  including loopback PCM/commit framing. The same codec and wire payloads are
  unchanged; the live call is not repeated. This distinction limits the live claim.

The closed configuration admits only Scribe v2 realtime, linear16/16 kHz and
optional lowercase ISO language codes. Private authentication stays in headers;
public options reject endpoint, commit-strategy and transport injection. Manual
commit finalizes a segment and does not close the socket or imply input drain.
The `Speech.Descriptor` admission contract and provider manifest are unchanged.

## Remaining contracts

The existing STT admission requires authoritative speech-start and endpointing.
Scribe's segment commits and replaceable partials do not provide that authority.
Before room/UI admission, specify and verify a genuine input-boundary owner,
server auto-commit accumulation, transcript completion ordering, cancellation,
close/drain, allocation supervision and usage. A local/external boundary owner
requires a reviewed contract amendment; no inferred event is labelled provider VAD.

The focused [input turn proposal](../docs/elevenlabs-turn-ownership.md) makes the
next work concrete: per-allocation genuine detector state, per-turn isolated Scribe
contexts, safe overlap bounds and transcript completion independent of endpoint
evidence. Silero's official ONNX wrapper uses 512 new/64 context samples at 16 kHz
and recurrent state; its MIT license and Ortex's Rust requirement are verified
from upstream sources. No dependency or model is installed. Detector deployment
feasibility and automatic/manual final-commit correlation remain unchecked design
gates. This is a proposal, not a descriptor amendment or implemented turn owner.

Agent STS remains separate. Its richer wire schema offers response identity and
completion evidence to verify. Call-spec-derived agent/tool provisioning versus
an existing agent remains a pending optional user preference; independent protocol
work can proceed. No conversational STS or remote resource cleanup is implemented.

## Repository verification

All five root completion gates pass: formatting, warnings-as-errors compilation,
strict Credo (1,160 source files, no issues), default tests and unused-dependency
check. The root seed-149103 run reports 2,936 tests, zero failures and 85 exclusions,
including 1,729 CallEngine, 522 Gateway and 194 Console tests. The two loopback/
callback checks pass in their explicitly selected integration lane; the one live
case is excluded from the default suite.

Forty-two relative documentation targets resolve; staged whitespace checks pass.
No speech state machine or source-cutover implementation changes in this
checkpoint, so the Lean lane is not repeated; the preceding TTS checkpoint's
passing Lean evidence remains scoped to that checkpoint. No UI is changed here.
The private credential file and unrelated documentation-content configuration
remain untouched. Commit includes protocol code/tests, fixed model, design
proposal and synchronized progress evidence; full milestone acceptance remains open.
