# Diagnostic failure control traces

## Gap and scope

Earlier configured failure cases proved exact STT provider PCM, no extra commits,
matching final transcript/response and bounded diagnostic teardown. They did not
assert every public call-control event. Enabled the existing SpeechConnection audit
copy in the five failure families and added an exact full public-event oracle.
No runtime code or control policy changed.

For each ordinary text-response turn the oracle requires, in order: participant
turn start, partial transcript, final transcript, participant turn completion,
matching response text, and agent turn completion. It compares every event field
except generated event ID, absolute sequence and wall timestamp; identities are
checked against the actual planned human/agent and the input turn/command. Event
IDs must be nonempty strings and unique, sequences positive integers and strictly
increasing, and nonempty turn/command identities
unique across turns. Extra, missing, reordered, mismatched or differently shaped
events fail. The expected transcript content, provider turn index, modality,
endpointing, speaker mode, text-only output and completed outcome stay explicit.

The same oracle and scripted inputs apply with collection off and on. Each test
now waits for agent completion before the next scripted turn, avoiding accidental
scheduler interleavings in a sequential workload. RoomAuthority sends public events
directly to the connection. The same authority's DOWN follows its preceding event
signals; SpeechConnection forwards its audited copies before its close message.
Waiting for that close therefore closes the event set before assertions.

This proves the complete observable connection-event trace for these deterministic
text-response calls, alongside existing byte/commit checks. It is not a trace of
private VM messages or a count of model-provider requests, and does not measure
latency/overhead. Tool, transfer, interruption and acknowledged-audio behavior have
separate acceptance; this matrix does not exercise every feature with every fault.

## Failure matrix

- Observer crash/hang: collection off/on (4 cases).
- Diagnostic storage error/blocked: local Silero off/on × collection off/on (8).
- Missing benchmark model: local Silero off/on × collection off/on (4).
- Full count/byte queues: two packet sizes × both VAD and collection modes (8).
- Idle diagnostic writer crash: both VAD and collection modes, with three turns (4).

Together these 28 cases validate 60 canonical turns and 360 public control events.
All prior provider-byte, inference-mode, failure, coverage and resource assertions
remain. Diagnostic capture/setup and room shutdown are included in each case.

## Verification

Initial crash/hang selection: 4/4 pass, seed 569939, 15.5 seconds.
Initial full failure matrix: 28/28 pass, seed 404817, 43.9 seconds.
Root format, warnings-as-errors compile, strict Credo and unused-lock checks pass.
Independent Astra xhigh review reproduced a gap in the initial oracle: one entire
turn with nil command/correlation IDs passed because equality and uniqueness alone
accepted the shared nil value. Root reproduced the same expected failure using
the extracted helper with valid-trace and missing-event controls (3 cases, one
failure). The helper now requires nonempty string event/command/correlation IDs
and positive integer sequences. Re-extracting the corrected helper passes all
three controls, seed 214297. This strengthens the test oracle; no runtime fault was
inferred. Final failure matrix passes 28/28, seed 892146, 44.9 seconds.
Independent Astra xhigh review is clean after the correction; its extracted-helper
controls pass 3/3, seed 855367. Final root static checks also pass.
C’s deterministic failure-parity gate is complete at the public connection-event
and provider PCM/commit boundary described above.

No full suite, live provider test, Telnyx change or deployment was performed.
Broader resource/load and acoustic accuracy gates remain open.
