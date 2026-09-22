# Agent STS checkpoint A (2026-09-22)

## Scope
Selection + contract, local only. No room wiring, no badge, no hosted adapter.

## Red-green evidence (all green, seed 0)
- `test/vxpipe/call_engine/call_spec/sts_selection_test.exs` (5 tests): three
  agent modes, illegal STS+LLM/TTS combos, output-STT-without-STS rejection,
  turn_control provider/external/hybrid + invalid rejection, caller-STT
  coexistence without output-slot inheritance, unchanged text-model path.
  Red first: new keys rejected / struct missing fields.
- `test/vxpipe/call_engine/speech/sts_provider_contract_test.exs` (5 tests):
  behaviour callbacks, Morse `:sts` descriptor, fail-closed validate/adapter,
  manifest-gated `:sts` (`:unsupported_provider_capability`, no fallback),
  `:sts` activity/text-settlement vocabulary in `Event.supported?`.
- `test/vxpipe/call_engine/speech/sts_session_test.exs` (3 tests): owned-scope
  start/bind/ready/ack, bounded push_audio admission, facade rejection of bad
  audio, turn_control in descriptor settings, owner-loss teardown, close
  teardown. Red first: init stopped, channel input gate rejected `:sts`.
- `vxpipe_calls usage_projection_test.exs` (+1): `speech_to_speech` archive fact
  projects. Red first: unknown capability.
- `vxpipe_console call_inspection_presenter_test.exs` (+1): STS as "STS" plus
  explicit output STT as "Agent STT"; caller STT unchanged. Red first: omitted.

## Implementation
- `call_spec/capabilities.ex`, `resolved_call_plan/capabilities.ex`,
  `capability_selection.ex`: `:speech_to_speech`, `:output_speech_to_text`.
- `call_spec_compiler.ex`: agent kinds extended; exactly one response path
  (STS xor LLM; TTS forbidden with STS; output STT requires STS); human STS
  rejected; `model_inference` required only without STS.
- `capability_requirements.ex`: agent effective kinds extended (no cross-kind
  inheritance by construction).
- `capability_catalog.ex`: morse STS/output-STT validate+adapter;
  `turn_control` provider/external/hybrid option on STS; hosted STS adapters
  delegate to `Registry` (`:sts`) so all fail closed until E.
- `plan_startup.ex`: STS-only agent passes `supported_model`; new kinds in
  planned-selection validation and supported-configuration (fail closed until
  B wires runtime); `:sts` reason codes.
- `speech/sts_provider.ex` (new behaviour, 7 callbacks, arities without
  source_ref: scoped channel stamps identity), `descriptor.ex` (`:sts`),
  `event.ex` (`:sts` activity/text-settlement support), `channel.ex` (input
  path admits `:sts` through the existing bounded Input worker).
- `provider/morse_code_sts/session.ex` (new): pure configure incl.
  turn_control default "provider"; bind/ready/admit/close lifecycle;
  push_text/interrupt/tool_result honestly `:unsupported_operation` until B/C;
  redacted format_status.
- `providers.ex`: `:sts` capability type. No manifest entry yet (gated to E).
- `usage/observation.ex`, `usage_observation_projection.ex`,
  `call_inspection_presenter.ex`: `:speech_to_speech` + "STS"/"Agent STT".
- `docs/speech-integration-guide.md`: STS provider section + conformance cmds.

## Deviations / deferred
- Behaviour arities omit `source_ref` (milestone table has it): scoped channel
  already stamps source/agent identity; one stream per allocation. Recorded in
  guide.
- Hosted `output_speech_to_text` resolution (via `:stt` manifest) deferred to
  D with the agent-scoped allocation; fail closed now.
- `channel_failure drainable_stt_failure?` stays `:stt`-only until MorseSTS
  emits turn events in B.
- STS usage facts have schema support but no runtime emitter until B.

## Verification
- Focused: call_spec+speech dirs 197 tests ok; provider+plan_startup 15 ok;
  STS files 13 ok; usage 4 ok; presenter 8 ok; inline capabilities (old path) ok.
- Root: `mix format --check-formatted` (touched files) ok,
  `mix compile --warnings-as-errors` ok, `mix credo --strict` no issues.
- Full umbrella `mix test` deferred to final acceptance per milestone cadence.
