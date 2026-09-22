# Google voice activity codec

Scoped codec-only task after `afd721c1`. Added milestone breakdown/design review
before tests or implementation. Parent owns controller activity-end semantics and
streaming admission; no STSSession or shared runtime edits are authorized.

Official SDK reference documents top-level `LiveServerMessage.voiceActivity`,
with `voiceActivityType` and optional string `audioOffset`, separately from the
allowlisted `voiceActivityDetectionSignal`. SDK `src/live.ts` passes Gemini JSON
directly to LiveServerMessage; only Vertex uses a response converter. Verify the
default API version before treating that as selected-transport evidence.

Sources checked 2026-09-22:

- https://googleapis.github.io/js-genai/release_docs/classes/types.LiveServerMessage.html
- https://googleapis.github.io/js-genai/release_docs/interfaces/types.VoiceActivity.html
- https://googleapis.github.io/js-genai/release_docs/enums/types.VoiceActivityType.html
- https://github.com/googleapis/js-genai/blob/main/src/live.ts

## Conflicting raw-wire evidence — implementation not accepted

Pinned JS SDK revision: `5c4fc4e8c0aad4dab85e63e238aaf81b1295575d`
(release 2.24.0). `_api_client.ts` defaults Gemini to v1beta. `live.ts`
lines 54–62 passes Gemini JSON through without the generated MLDev converter.
However, `converters/_live_converters.ts` lines 2654–2673 explicitly maps raw
`voiceActivity.type` to SDK `voiceActivityType`. Its server-message converter
invokes that mapping, but the inspected Gemini receive path bypasses it.
The Python generated converter likewise reads `type`, while the public v1beta
`generative_service.proto` inspected here has no VoiceActivity definition.
These sources do not safely establish which key the selected raw endpoint emits.

- https://github.com/googleapis/js-genai/blob/5c4fc4e8c0aad4dab85e63e238aaf81b1295575d/src/live.ts
- https://github.com/googleapis/js-genai/blob/5c4fc4e8c0aad4dab85e63e238aaf81b1295575d/src/converters/_live_converters.ts
- https://github.com/googleapis/js-genai/blob/5c4fc4e8c0aad4dab85e63e238aaf81b1295575d/src/_api_client.ts
- https://github.com/googleapis/python-genai/blob/main/google/genai/_live_converters.py
- https://github.com/googleapis/googleapis/blob/master/google/ai/generativelanguage/v1beta/generative_service.proto

Before finding the converter conflict, provisional tests against the SDK-shaped
`voiceActivityType` produced 17 tests / 4 expected failures: SDK-shaped start
ignored, malformed known field ignored, invented server-content boundaries
accepted, and mixed-content activity missing. The provisional decoder and fixture
migration then passed 42 Google codec/session/output tests. That green result is
NOT wire verification and the implementation remains uncommitted pending parent
direction. No dual-key fallback was introduced to conceal the ambiguity.

Exact commands from the owning Call Engine child, with `ERL_FLAGS='+S 2:2'`
and `MIX_BUILD_PATH` pointing to this isolated checkout's `_build`:

```sh
mix test test/vxpipe/providers/google/sts_test.exs --seed 0
mix test test/vxpipe/providers/google/sts_test.exs \
  test/vxpipe/providers/google/sts_session_test.exs \
  test/vxpipe/providers/google/sts_output_test.exs --seed 0
```

Proposal: obtain an authoritative raw v1beta schema/example or upstream SDK
clarification before selecting `type` versus `voiceActivityType`. No hosted call
is authorized. All milestone wire/controller subtasks remain unchecked. Parent
review fixes take priority; no commands remain live.

## Follow-up: actual Python receive path resolves recommended raw profile

Read-only follow-up pinned Python SDK to
`938dd7385caa68e1d9fff2ef2507fdbf1cd7eaab`. Unlike the JS bypass, its actual
Gemini receive path calls the generated MLDev converter:

1. [`live.py` lines 549–580](https://github.com/googleapis/python-genai/blob/938dd7385caa68e1d9fff2ef2507fdbf1cd7eaab/google/genai/live.py#L549)
   receives raw WebSocket bytes, parses JSON, and calls
   `_LiveServerMessage_from_mldev(response)` for non-Vertex sessions.
2. [`_live_converters.py` lines 1355–1362](https://github.com/googleapis/python-genai/blob/938dd7385caa68e1d9fff2ef2507fdbf1cd7eaab/google/genai/_live_converters.py#L1355)
   maps top-level `voiceActivity` through `_VoiceActivity_from_mldev`.
3. [Lines 2026–2037](https://github.com/googleapis/python-genai/blob/938dd7385caa68e1d9fff2ef2507fdbf1cd7eaab/google/genai/_live_converters.py#L2026)
   read raw `type` into SDK `voice_activity_type`; `audioOffset` maps to
   `audio_offset`. There is no raw `voiceActivityType` alternative in this path.
4. [`_api_client.py` line 840](https://github.com/googleapis/python-genai/blob/938dd7385caa68e1d9fff2ef2507fdbf1cd7eaab/google/genai/_api_client.py#L840)
   selects Gemini v1beta by default; [`live.py` lines 970–996](https://github.com/googleapis/python-genai/blob/938dd7385caa68e1d9fff2ef2507fdbf1cd7eaab/google/genai/live.py#L970)
   uses that version in the same GenerativeService.BidiGenerateContent endpoint.

This establishes a concrete official raw-transport mapping, not merely an unused
converter. Recommendation: choose only `{"voiceActivity":{"type":"ACTIVITY_START"}}`
and corresponding `ACTIVITY_END`/`TYPE_UNSPECIFIED`, with optional string
`audioOffset`. SDK-facing `voiceActivityType` is not evidence of a second wire
version. No documentation found in this bounded pass supports accepting both.
Treat the JS receive/converter inconsistency as an SDK issue/inference, not a
reason for a dual-key fallback or a claim about hosted observations.

The [official v1beta Live reference](https://ai.google.dev/api/live?hl=en#BidiGenerateContentServerContent)
deprecates `serverContent.speechState` in favor of VoiceActivity. It documents
`activityStart`/`activityEnd` as client realtime-input messages, not server-content
booleans. Do not add either deprecated or invented server fallback. Optional
offset remains metadata, not evidence of playback or turn settlement semantics.

Bounded fixture audit: pinned Python `tests/live/test_live_response.py`,
`tests/live/test_live.py`, `tests/live_api/test_live_session.py`, JS
`test/unit/live_test.ts`, and the JS recorded
`live_ML_Dev_handle_activity_start_and_end.websocket.log` were searched. Found
Python mocked receive coverage for the distinct allowlisted detection signal;
the JS recording contains client activityStart/End, not raw voiceActivity proof.
No matching raw voiceActivity fixture was found in that inspected set. The
recommendation rests on the actual Python receive/converter chain, not a claim
of captured wire or exhaustive upstream test coverage.

No compile/tests, hosted calls or upstream messages ran in this research pass.
Provisional local code and fixture changes remain untouched and unstaged; the
prior 42-test green uses the wrong proposed SDK-shaped key and is not acceptance
of the recommended raw profile. Implementation needs a newly authorized red
probe using `type`, including rejection of SDK-only fields and malformed values.

## Approved raw codec checkpoint

Parent approved the single raw `voiceActivity.type` profile. Before changing the
provisional decoder, add raw start/end and SDK-only-key rejection tests and run
them red. Then migrate the existing Google fixtures to raw `type`, preserve
strict enum/optional string validation, and remove invented server-content
activity interpretation. No STSSession runtime/controller changes. The earlier
42-test SDK-shaped green remains explicitly non-acceptance evidence.

- New raw-key red: `mix test test/vxpipe/providers/google/sts_test.exs --seed 0`
  completed exit 2, 18 tests / 4 failures before modifying the provisional
  decoder. Raw start ignored, SDK-only key accepted, malformed raw type ignored,
  and raw activity absent from mixed-content events were the expected failures.
- Implemented raw `type` mapping and explicit SDK-alias rejection (including
  aliases coexisting with valid raw fields). Optional raw audioOffset is a bounded
  UTF-8 string, not parsed as a controller timestamp. Unknown unrelated fields
  retain existing decoder tolerance; invented server activity fields no longer
  synthesize events. Client activity encoders are untouched.
- Migrated Google codec/session fixtures to raw `type`. The focused three-file
  command recorded above passes 43 tests / 0 failures (seed 0). Regression
  matrices cover missing/default type, both boundaries, optional offset,
  malformed enum/container/offset, oversized offset, SDK-only aliases and no
  deprecated speechState or allowlisted-signal fallback. No STSSession runtime,
  controller or shared event changes; no hosted or broad gates executed.
