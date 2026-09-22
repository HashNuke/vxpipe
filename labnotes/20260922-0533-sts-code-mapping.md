# STS code mapping (2026-09-22)

## Task
Review `docs/milestones/agent-speech-to-speech.md` against latest codebase; list
exact files + required changes per checkpoint; add suggestions to the milestone.

## Method
- 3 parallel explore subagents (call-spec path, speech contract/ownership, console/usage UI).
- Direct reads: `capability_catalog.ex`, `providers/google.ex`, `speech/event.ex`,
  `resolved_call_plan/capabilities.ex`, milestone tail.
- Added non-normative "Suggested code-change mapping" section before
  "Alternatives and implications" in the milestone doc.

## Findings
- Prerequisites complete per index (simpler-speech 9/9, provider packages, rime+google).
- Current code has 3 capability kinds only (`capabilities.ex`, resolved mirror);
  descriptor `kind` is `:stt | :tts` only; no `STSProvider`; registry has no `:sts`.
- Morse lives under `call_engine/provider/morse_code*/`, not `providers/`;
  Deepgram/Rime/Google sessions under `call_engine/.../providers/`;
  manifests under `vxpipe_providers`.
- Frontend already has `s2s` label/ready-gate scaffolding in `setupCatalog.ts`
  (`capabilityLabels.s2s`, `voiceSetupReady` ORs `s2s`) but catalog JSON lacks it;
  backend gates via `Registry.catalog()` in `admin_services_controller.ex`.
- Usage/inspection allowlists (`usage_observation_projection.ex capability/1`,
  `call_inspection_presenter.ex capability_name/1`) need S2S entries.

## Change
- `docs/milestones/agent-speech-to-speech.md` +130 lines (suggestions only).
- No runtime code touched; no tests run (doc-only change).

## Next
- Checkpoint A: closed CallSpec schema + `STSProvider` behaviour + conformance
  test, red-green, focused child tests.
