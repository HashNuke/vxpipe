# Transcript start planning

## Scope and decisions

The user requested a plan for transcript-based human speech start by default,
with optional local VAD for any STT model, and automatic ElevenLabs Scribe VAD
commits. This checkpoint changes planning and documentation only. The earlier
uncommitted skipped measurement and its labnote are preserved.

Created the durable [decision](../docs/stt-speech-start-detection.md) and
[implementation milestone](milestones/transcript-start-and-optional-vad.md), and
linked them from the docs README and milestone index. The new milestone stays
unchecked. Its direct prerequisites already pass historical acceptance; their
status is unchanged. The completed editor entry moves before the new slice and
before packaging/retention, preserving filenames and the existing holds.

## Source inspection and rationale

- CapabilitySelection currently validates a closed set of common fields, while
  CapabilityCatalog normalizes provider-specific option allowlists. Proposed
  `speech_to_text.vad` therefore belongs beside provider/model, not in upstream
  options. The setting must survive identities, readiness, inheritance and UI
  provider changes.
- Deepgram forwards native turn-start; Google forwards activity_start; Cartesia
  supplies semantic/eager/resume behavior. Default transcript start must apply
  to these adapters too, rather than being a Scribe-only special case.
- Scribe STTSession currently requires manual mode, prepares local Silero and
  assembles bounded acoustic turns with separate recognition connections. Its
  wire layer already supports automatic VAD strategy, but changing the default
  alone cannot replace ownership, turn correlation or endpoint semantics.
- Portable Scribe options currently expose language only; commit strategy is
  resolved internally. Keep raw manual protocol helpers for experiments without
  making them an automatic conversational fallback.
- Semantic events require Session.ack and one channel producer. Plan an internal
  allocation-owned coordinator consuming an inner recognizer and optional local
  activity runtime, then publishing canonical events on its outer channel. Do
  not inject a second producer or add detector state to RoomAuthority.
- Silero consumes 16 kHz mono PCM. Deepgram's recommended model metadata uses
  48 kHz and allows Opus selections. The plan explicitly includes normalized
  permitted PCM branching, existing engine resampling, decoder ownership and
  sample-clock/cutover checks; no dependency from Engine to Gateway is proposed.
- Agent output STT has finite-input/drain responsibilities and native STS has
  separate activity authority. The human-input option must not affect either.

## Specification review

Reviewed contracts and direct dependency order separately from implementation.
The four explicit checkpoint-A gates are forced-commit endpoint evidence,
old pinned snapshot compatibility, acoustic/provider turn correlation including
semantic resumes, and normalized VAD input across formats. These gates are open;
no implementation acceptance or hosted capability guarantee is inferred.

Rejected always-on local VAD, a provider-specific toggle, native provider onset
as the default, and using local silence as a new endpoint authority. The user
requested speech-start control; recognizer endpointing stays separate. Transcript
fallback protects brief speech and synthetic Morse input when VAD misses onset.

## Verification

Validate new Markdown references and JSON examples, milestone checkbox state,
index totals and prerequisite ordering, then check whitespace/diffs. No runtime,
frontend or hosted changes are part of this planning checkpoint, so no new live
requests or runtime acceptance suite is required. Production docs describing
existing adapter behavior remain authoritative until the new milestone passes.
