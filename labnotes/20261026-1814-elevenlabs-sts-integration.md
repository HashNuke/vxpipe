# ElevenLabs STS integration

- Scope: register and configure standalone ElevenLabs Mini/Max outside the provider's reserved `realtime*` files. No docs or commits; no live tests or live credential file access.
- Contract: public models `eleven_realtime_v1_mini` (default) and `eleven_realtime_v1_max`, editable voice (default `brian`), provider-native turn detection only. No local VAD/Silero or separate STT runtime. Core session implementation owns native `semantic_vad` configuration and explicit response correlation. Exact model IDs were aligned with the concurrently added core configuration.
- Setup: `bin/setup` succeeded; existing local environment was preserved.
- Red: provider registry tests ran before implementation: 6 tests, 2 expected failures for missing ElevenLabs STS capability.
- Red: call-engine catalog/startup/configuration tests ran before implementation: 33 tests, 7 expected failures for missing registration/configuration and unavailable `RealtimeSession`.
- Added configured-service tests for both models, saved platform/tenant credentials and fallback, plus public catalog/voice and setup inventory tests.
- Red: Console configured-service/catalog tests: 24 tests, 4 expected failures. Frontend setup/onboarding tests: 14 tests, 2 expected failures.
- Registration and private startup now use the concurrently supplied `Realtime.new/1`, `RealtimeSession.configure/1` and `models/0`. Existing generic credential resolution and model catalogs need no additional provider branches.
- Green: registry tests: 6 tests, 0 failures. Call-engine model catalog, portable selections and STS startup/configuration: 54 tests, 0 failures with the core configuration/descriptor present.
- Scope decision: expose STS in service and model catalogs; leave canned sample capabilities at STT/TTS, as for Gemini. `providersFor` filters canned sample availability, so the setup test checks the installed STS recommendation directly rather than advertising an unsupported sample recipe.
- Green: Console configured-service/catalog tests: 24 tests, 0 failures. Frontend setup/onboarding/model-catalog tests: 16 tests, 0 failures. Frontend `npm run check` succeeded.
- Checks: root `mix compile --warnings-as-errors`, `mix credo --strict`, and `mix deps.unlock --check-unused` succeeded. Formatting passed for every Elixir file owned by this task. Root `mix format --check-formatted` reported the concurrently edited, reserved `realtime_api.ex`; it was not modified by this task.
- Browser: inspected the editor with headless Chrome through `agent-browser` at 1280x900 and 390x844. Selected ElevenLabs Mini and Max, verified default voice `brian`, and confirmed an edited voice `charlie` survives in participant JSON with `eleven_realtime_v1_max`. No browser errors were reported. Linux required Chrome's `--no-sandbox` startup flag. Screenshots remained temporary outside the repository.
- The first root `mix test` run ended in an `ExUnit.Server` shutdown during the call-engine suite, without a final suite result. A traced retry was started for diagnosis and stopped when the main agent requested limiting further checks until the session implementation exists. No complete umbrella pass is claimed.
- Initial integration ownership review: only the integration files listed below were edited; the concurrent provider `realtime*` implementation/tests and milestone work were left untouched during that checkpoint. `git diff --check` passed for the owned paths. Browser and Storybook processes started for inspection were closed.
- Acceptance boundary: the integration results verify registration, public configuration, catalog metadata, and private credential/prompt/tool startup preparation. The later room tests below additionally verify native session behavior against synthetic API/transport events. No live tests were run by this worker; subsequent live results reported by the main agent are recorded separately below.

## Compiled room regression checkpoint

- The main agent subsequently assigned this worker `realtime_room_test.exs` and dedicated room support only. Core provider modules, session tests, shared fake API/transport, and milestone documentation remained owned by the main agent.
- Added a compiled-room test using `TestElevenLabsRealtimeAPI` and `TestElevenLabsRealtimeTransport`, injected through the session's private API/wire options. The compiled provider selection, credentials, prompt and public options remain in use. Dedicated support implements the `ping` tool.
- Native input produces a tool-only ping roundtrip, then a spoken response. The test verifies that the tool-only response creates no phantom sink turn, that audio delivery waits for sink credit, and that public text/completion waits for playback. It checks native semantic turn detection and absence of local VAD/activity processes or separate STT configuration.
- Initial focused room result: 1 test, 0 failures (seed 300310). This was fake-transport evidence, not a live provider acceptance run.
- Superseded lifecycle extension: after admitted PCM and room hold/release, the next framed input carried a new response context and closed the old allocation before another append. Delayed native events were queued behind that new input. It passed on its first run because the main agent's context-pinning implementation was already present; no red result is claimed for that extension. The main agent owned the core red-green evidence and reported 18 scoped core tests green at that point.
- Historical focused result: `mix test test/vxpipe/providers/elevenlabs/realtime_room_test.exs`, from `apps/vxpipe_call_engine`, passed **2 tests, 0 failures**, 0.8 seconds, seed 445962 (2026-10-26 18:56 UTC). This was superseded after review found that old native caller evidence could arrive between release/regrant and new input.
- Replaced that extension with hold-time closure and policy-revoke closure tests. Each requires the old provider/allocation/wire/capability to terminate before release/regrant, then injects delayed native caller evidence with the retired provider/wire identities, without fresh PCM. Local VAD remains absent.
- Red before the shared boundary implementation: `mix test --no-compile test/vxpipe/providers/elevenlabs/realtime_room_test.exs` produced **3 tests, 2 expected failures**, 2.5 seconds, seed 495425 (2026-10-26 19:01 UTC). Both failed waiting for the old provider's `:DOWN` after hold or policy revoke; the original tool/audio test passed. The main agent subsequently reported **95 scoped tests green, including all 3 room tests**, after implementing the shared boundary profile.
- Added direct-policy API closure coverage and an unrelated snapshot-revision case. The direct API lacks interval proof and must close; a snapshot retaining intervals and participant presence must preserve the allocation, epoch and response origin and still publish native caller transcription. These additions passed on their first run against the already implemented boundary behavior; no separate red is claimed for them.
- Intermediate green: the focused room command passed **5 tests, 0 failures**, 0.6 seconds, seed 904407 (2026-10-26 19:05 UTC), after formatting the owned room test file.
- Further review required direct release with a new epoch to close without a preceding hold, repeated release of the same epoch to preserve lifecycle identity and continue input, and hold/direct-policy/snapshot cutover to interrupt buffered PCM in the independent sink before allocation closure. Added five focused regressions for those contracts without editing shared implementation.
- Fixture correction: the first sink-test attempt omitted the caller-final transcript and therefore never admitted output. Added that native final before asserting buffered output; only the subsequent interruption failures are counted as sink-boundary red evidence.
- Historical red before the release/sink fixes: **10 room tests with 5 expected failures**, 4.9 seconds, seed 925922 (2026-10-26 19:07 UTC). New-epoch release failed to close; same-epoch release changed the lifecycle revision; hold, direct policy and snapshot each omitted the sink interruption with buffered output present. The previous five tests remained green. The main agent inspected this red evidence before implementing the shared fixes.
- **Current focused acceptance: GREEN, 102 combined focused tests, including all 10 room tests**, reported by the main agent after fixing the shared release and sink boundaries. This worker did not rerun those checks or independently inspect their logs.
- Live evidence reported by the main agent: final Mini two-turn live check passed in 11.1 seconds; Max one-turn live check passed. These runs belong to the main agent and were not executed or independently verified by this worker.
- Final handoff: the main agent is running the final root gates sequentially and owns final review, the full suite and Lean verification. Those gates remain in progress; no final root-gate pass is claimed here. This worker is running no further Mix commands or making code changes. No live credential file access, live test runs, core edits or commits occurred during this worker's room regression work.

## Owned files

- `apps/vxpipe_providers/lib/vxpipe/providers/elevenlabs.ex`
- `apps/vxpipe_providers/test/vxpipe/providers/registry_test.exs`
- `apps/vxpipe_call_engine/lib/vxpipe/call_engine/capability_catalog.ex`
- `apps/vxpipe_call_engine/lib/vxpipe/call_engine/speech_to_speech_runtime.ex`
- `apps/vxpipe_call_engine/test/vxpipe/call_engine/model_catalog_test.exs`
- `apps/vxpipe_call_engine/test/vxpipe/call_engine/speech/model_catalog_test.exs`
- `apps/vxpipe_call_engine/test/vxpipe/call_engine/plan_startup/sts_activation_test.exs`
- `apps/vxpipe_call_engine/test/vxpipe/call_engine/plan_startup/sts_configuration_test.exs`
- `apps/vxpipe_call_engine/test/vxpipe/providers/elevenlabs/realtime_room_test.exs`
- `apps/vxpipe_call_engine/test/support/elevenlabs_realtime_room_ping.ex`
- `apps/vxpipe_console/assets/src/admin/fixtures/modelCatalog.json`
- `apps/vxpipe_console/assets/src/admin/onboardingFixtures.ts`
- `apps/vxpipe_console/assets/src/admin/onboardingFixtures.test.ts`
- `apps/vxpipe_console/assets/src/admin/setupCatalog.json`
- `apps/vxpipe_console/assets/src/admin/setupCatalog.test.ts`
- `apps/vxpipe_console/test/vxpipe/console/admin_provider_catalog_endpoint_test.exs`
- `apps/vxpipe_console/test/vxpipe/console/admin_services_endpoint_test.exs`
- `apps/vxpipe_console/test/vxpipe/console/elevenlabs_service_activation_test.exs`
- `config/config.exs`
- This labnotes file.
