---
title: Speech and media runtime
description: Owned semantic sessions, bounded audio, turn evidence and safe interruption.
sidebar:
  order: 4
---

Speech integrations expose semantic behavior through
[`Speech`](../../../apps/vxpipe_call_engine/lib/vxpipe/call_engine/speech), not a
socket-shaped public API. A provider can use a persistent connection, bounded
request worker or local inference. The common runtime owns admission, policy,
credit, cancellation and publication.

## Ownership and startup

Every allocation belongs beneath its room's capability tree. Its handle identifies
the room incarnation, purpose, generation and control identity. Lifetime owner,
event consumer and temporary preparation lease are distinct roles.

Connection STT follows the connection; conversational TTS/STS follows the agent
activation; opening and private briefing allocations follow their operation.
Prepared resources are created in their final room scope. Adoption commits a
change of authority before delivery; it never moves a running supervisor tree.

Shared ancestors start lightweight children only. Credential resolution, network
startup, inference and synthesis run in owned, bounded workers. A slow allocation
must not serialize another room's startup. Registries hold handles, while caches
hold data; neither retains provider execution after its owner ends.

Sessions persist across ordinary turns where the adapter's contract supports it.
They do not create a new transport for each sentence. Provider-required per-request
HTTP behavior, such as the selected Google TTS path, stays explicit in the adapter.
Connection persistence never overrides a privacy reset or retirement requirement.

## Semantic contracts

| Kind | Common contract |
| --- | --- |
| STT | Bounded audio admission; cumulative transcript revisions; an explicit conversational endpoint authority. |
| TTS | Bounded complete-text requests; credited audio; submission, generation terminal and cancellation evidence. |
| STS | Bidirectional model session; independently admitted input/output; caller/agent turn evidence and semantic tool-result delivery. |

`configure/1` is pure and returns public descriptors. Models, audio formats,
readiness, endpointing, usage identity and supported operations are declared.
Private initialization owns credentials and I/O. Provider wire IDs stay private;
the room creates public turn/command identities.

## Input and caller turns

Human STT starts on the first nonempty transcript. `speech_to_text.vad: true`
adds allocation-owned Silero onset with transcript fallback; local silence does
not replace the recognizer's endpoint. Provider onset hints alone cannot bypass
the default. Empty transcripts do not create model input.

Conversational STT declares `provider_semantic`, `provider_gap`, `local_gap` or
an explicitly supported `inferred_gap`. A recognition segment is not necessarily
a conversational turn. The Scribe adapter's transcript-gap inference is a
heuristic and must remain identified as such. Final-only input publishes start,
text and end in order.

ElevenLabs Scribe v2 Realtime (`scribe_v2_realtime`) and Scribe v3 Live
(`scribe_v3_live`) share the same Scribe session, transport and transcript codec.
The socket validates any echoed model against the selected configuration. Both
use 16 kHz mono PCM and the existing manual/VAD commit modes. V3's additional
`turn_probability` metadata does not change endpoint authority: Vxpipe does not
request `turn_prediction` or interpret a partial's probability as a completed
turn. This keeps model selection independent of turn-policy changes. The
[ElevenLabs realtime reference](https://elevenlabs.io/docs/api-reference/speech-to-text/v-1-speech-to-text-realtime)
and [commit-strategy guide](https://elevenlabs.io/docs/eleven-api/guides/how-to/speech-to-text/realtime/transcripts-and-commit-strategies)
define the shared protocol and optional V3 behavior.

Human-STT and STS microphone paths have separate bounded queues, conversion
state and delivery credit. One consumer's overload cannot grow or stall the
other queue. Only authorized source frames feed STS, not the mixed room output.
Source connection, input epoch and permission intervals accompany evidence.

When STS owns caller transcripts, genuine onset and semantic end establish the
public turn; text alone cannot invent boundaries. Delayed finals retain their
original association. When human STT is selected, it owns that publication path.
Transcript source and the controller that triggers an STS response are separate
choices.

## Output credit and settlement

Generation, local playback and remote hearing are different facts. Audio delivery
uses bounded chunks and exact credit; unbounded mailbox enqueue is not successful
admission. The provider remains responsive to close/cancel while credit is held.

For STS, the consumer calls `Session.admit_output/2` after policy checks. The
returned output handle has a fresh engine reference even if the provider reuses
a turn ID. There is one credited output slot. Provider generation completion
does not release it: selected transcript evidence and sink settlement must also
finish. Played duration cannot exceed credited PCM duration.

Provider-transcript profiles declare whether an explicit transcript final or the
generation boundary settles text. Do not promote a partial merely because audio
drained. Agent-output STT requires a finite-input contract: finalization acceptance
is not terminal proof; the recognizer must emit ordered final segments and
`input_finished` before retirement. A conversational silence endpoint cannot
stand in for finite-stream completion.

Room publication matches the current capability/source and output association.
Scalar sequence watermarks reject retired owner messages without an unbounded
set of old IDs. They do not replace upstream event deduplication in the adapter.

## Interruption and privacy cutover

An authenticated typed `SendText` with `run_immediately: true` interrupts older
active/queued turns in the room's logical agent-output lane. False preserves
FIFO behavior. Gateway supplies participant/connection identity; the message
payload cannot impersonate another caller.

Spoken interruption follows the selected speech controller. Provider-controlled
duplex can overlap caller and agent audio without the room imposing ordinary
barge-in behavior. Protected openings keep their separate completion gate.

Source cutover closes admission, acknowledges transport hold, retires old input,
establishes a fresh origin/epoch, arms that exact epoch and reopens. Late frames
and acknowledgements cannot cross the boundary. These transitions have a
[Lean conformance lane](testing.md#formal-verification).

Obsolete conversational TTS output is cancelled with its original generation,
not restamped as current. A discarded speech segment does not enter spoken
history or cancel unrelated model/tool work. Opening/private-briefing failure
retains its own stricter lifecycle behavior.

## Reconnection and context

A resumable provider session needs explicit, safe continuity evidence. Retain
provider-issued handles privately and use them only at the adapter's validated
checkpoint. Do not add history replay to a valid native resume, or invent a new
utterance by resending a transcript after uncertain audio submission.

When an adapter supports reconstruction, it must rebuild only the permitted,
committed context and preserve tool/result relationships. Unsupported or ambiguous
restoration fails explicitly. Fresh tool-result continuation carries a fresh
response context through the common API; the wire encoding stays in the provider.

## Why these boundaries matter

Global speech pools couple unrelated call latency and lifetime. Socket-connected
flags omit provider readiness. Silence timers cannot prove playback or complete
recognition. Replaying stale media or history can leak private intervals or
repeat effects. The explicit owners, evidence and bounded credit avoid those
shortcuts while keeping provider protocols local.

Use [provider conformance and native media checks](testing.md) before claiming a
new integration works. A local decoded audio test does not establish remote hearing
or hosted capacity.
