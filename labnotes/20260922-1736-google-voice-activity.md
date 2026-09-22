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
