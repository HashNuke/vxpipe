# Agent STS completion

## Starting point

- Date: 2026-09-22.
- The target milestone is `docs/milestones/agent-speech-to-speech.md`.
- Checkpoint A is recorded as implemented; checkpoints B–F remain open and the
  milestones index entry is unchecked.
- Existing worktree changes in `AGENTS.md`, `bin/teammate`,
  `labnotes/20260922-0745-teammate-cli-script.md`, and
  `test/bin/teammate_test.sh` predate this task and must be preserved.
- Required workflow: delegate implementation with `bin/teammate` from tmux
  session `vxpag`, review with the requested Astra medium reviewer, then send
  findings back to the teammate and repeat until no issues remain.

## Evidence and decisions

- The milestone explicitly requires Morse STS proof, a Google/Gemini 3.8 Live
  integration kept behind the hosted boundary, agent-owned STS lifecycle and
  output-STT mode, room authorization/interruption routing, focused tests,
  final root gates, and bounded concurrency evidence.
- The existing provider package direction is compatible with putting Morse STS
  under the MorseCode provider namespace, provided the public capability and
  ownership contracts remain those specified by the milestone.

## Progress log

- 2026-09-22: inspected the milestone, index, teammate script, and available
  notification CLI; created this labnote. Implementation delegation is next.
- 2026-09-22 (B–F implementation): milestone is authoritative. Working
  checkpoints B–F as a coherent sequence with red-green-refactor. Plan:
  B1 MorseCode provider namespace (`Vxpipe.Providers.MorseCode` manifest with
  `:stt`/`:tts`/`:sts`, credential-free local only); B2 real Morse STS
  conversation generation plus agent-owned `Capability.SpeechToSpeech` tree with
  room auth/playback routing; C interruption/tools/transfer/hold/teardown and
  turn-control modes; D agent-output STT mode; E Google Gemini 3.8 Live adapter
  behind credential boundary with fake-socket ordinary tests (manifest stays
  gated, no badge); F service/UI gating, docs, checklists, final gates.
  Preserving pre-existing worktree changes in `AGENTS.md`, `bin/teammate`,
  `labnotes/20260922-0745-teammate-cli-script.md`, `test/bin/teammate_test.sh`.
  No commit.

## Evidence and decisions (B–E implemented, F partial)

- B1 namespace (red→green): new `morse_code_test.exs` failed with
  `:unsupported_provider`; implemented `Vxpipe.Providers.MorseCode` manifest,
  `Registry` entry, and `Vxpipe.Providers.MorseCode.{STT,TTS,STS}Session`
  wrappers delegating to the native Morse sessions. `CapabilityCatalog` morse
  adapters resolve through the manifest. Providers suite + STS selection
  green.
- B2 conversation (red→green): new `morse_sts_conversation_test.exs` failed
  (no-op `push_audio`). Implemented real decode→`RECEIVED <text>`→encode
  flow through the admitted-output credit protocol. Fixed two real bugs
  found by tests: provider matched Channel pid instead of reference identity
  for output/credit messages; `Event` rejected `:external` endpointing
  evidence for `turn_ended` (contract repair in `event.ex`).
- B capability tree (red→green): new `capability/speech_to_speech_test.exs`
  (now 14 tests) drove `Capability.SpeechToSpeech` + `Tree` +
  `RoomCapabilitySupervisor.start/stop_speech_to_speech`: policy/source
  gating with real `Effective` predicates, real `OutputSink` protocol,
  egress-fenced agent transcripts, caller-source suppression with human STT,
  revocation/hold/teardown, redaction, tool forwarding, owner-death tree
  teardown, barge-in with next-turn recovery, zero-playback `:no_prefix`.
- C tools/turn-control (red→green): `sts_tool_test.exs` (TOOL trigger via
  text/audio, one result, unknown→stale, interrupt→`tool_cancelled`),
  `sts_turn_control_test.exs` (external holds turn until `:ended`, hybrid
  needs recognition plus boundary, provider auto-drives, transcript/turn
  independence). Capability forwards tool calls with agent attribution,
  retains ids until settled, never revives fenced speech.
- C correctness repairs from tests: late audio ack-and-discard (no stop);
  readiness race fixed with `vxpipe_sts_ready`; provider fence-terminal
  `:output_completed` so interruption releases the Channel slot
  (best-effort marker, zero-egress settlement); deferred fence completion
  until outstanding credit returns (prevents stuck slot when interrupting
  mid-stream); queued-turn admission (busy requeues instead of dropping);
  fence drains the queue through policy/held gates; fence settles
  already-completed generations. Same deferred pattern in the Google
  session. Guide documents the fence-terminal marker.
- D output STT (red→green): optional `STTProvider.finish_input/1` plus
  Morse implementation; capability second scope/session fed only by STS
  output audio; `speech_to_speech_output_stt_test.exs` (5: single agent
  transcript, policy denial, deterministic failure honesty, kill recovery,
  slow-consumer isolation with drop counting). Provider-transcript path
  stays green.
- PlanStartup: `SpeechToSpeechRuntime` resolution (`sts_activation_test.exs`
  2 tests), `agent_activation` nil for STS-only agents, catalog
  `:speech_to_speech`/`:output_speech_to_text` adapter entries.
- E Google (red→green): `STS` codec (6 tests) + `STSSession`/`STSSocket` +
  `TestGoogleSTSTransport` (10 tests: setup/voice/PCM, out-of-order,
  generation-vs-playback, pre-audio interruption, turn-control, tools,
  goAway/resumption/expiry, unsafe-handle fail-closed, fence-window
  sent-ahead mute). Manifest keeps no Google `:sts`; Console catalog test
  locks the badge off. Fixture wire shapes documented as assumptions;
  hosted byte compatibility explicitly not claimed.
- F gating: backend `provider_capabilities` includes Morse (no credential)
  and still excludes Google `:sts`; frontend `setupCatalog.test.ts`
  s2s-gate test green. Docs updated (integration guide, provider contract,
  provider packages, milestone B–F boxes).
- Focused suites green: call_engine speech+capability+call_spec+plan_startup+
  google (341 tests), providers (19), console endpoint (12), frontend
  setupCatalog (3). See verification section for root gates.

## Verification

- `mix format --check-formatted`, `mix compile --warnings-as-errors`,
  `mix credo --strict`, `mix deps.unlock --check-unused` from umbrella root
  (see commands below).
- No real credentials: all fixtures use `synthetic-*` keys; `STS.setup`
  test asserts the key never appears in setup payloads.
- Pre-existing worktree changes preserved (see `git status`).
- 2026-09-22 focused ready-flake fix: `speech_to_speech_output_stt_test.exs`
  `start_output_stt_capability/1` waited for `{:vxpipe_sts_ready, capability}`
  with the default 100 ms timeout while starting two sessions (STS + output
  STT) under async load; bumped to an explicit 5_000 ms to match
  `sts_concurrency_test.exs` and `complete_playback/1` in the same file.
  Not an implementation regression (provider emits `:ready` synchronously in
  `init`; isolated 6-test run was already green). Verified
  `speech_to_speech_output_stt_test.exs` + `sts_concurrency_test.exs` (6
  tests, seed 0, `PGHOST=/var/run/postgresql`) green; root format, compile,
  credo (exit 0; 4 pre-existing ModuleSize design notes on uncommitted B–E
  files), and deps-unused gates clean. Broader 38-test STS sweep still shows
  the same 100 ms pattern in `sts_tool_test.exs:77` — left untouched per
  fix-only scope, flagged as follow-up.
- 2026-09-22 follow-up ready-flake fix: confirmed `sts_tool_test.exs:77` is
  the same legitimate async startup timing issue. `Session.start/2` reserves
  through `ScopeControl` and supervises Channel/Input/Task.Supervisor/
  provider before the `:ready` event arrives, so the default 100 ms
  `assert_receive` in `start_session/0` flakes under the async sweep load.
  Test-owned fix only: both `:ready` receives in `start_session/0`
  (`sts_tool_test.exs:77,79`) now use an explicit 5_000 ms, matching
  `sts_concurrency_test.exs:81` and the prior output-STT fix. No
  implementation change. Verified `sts_tool_test.exs` (3 tests, seed 0,
  `PGHOST=/var/run/postgresql`) green; speech STS sweep
  (tool/turn-control/session/output/conformance/provider-contract/
  morse-conversation/concurrency: 37 tests, seed 0) green; extended STS sweep
  including capability speech-to-speech suites (56 tests, seed 0) green;
  isolated `sts_concurrency_test.exs` (1 test, seed 0) green; root format,
  warnings-as-errors compile, strict credo (exit 0; same 4 pre-existing
  design notes), and deps-unused checks clean. No Google hosted tests run.
  No commit.

## Remaining (final acceptance, requires user authorization/conditions)

- RoomAuthority-level publication (`EventPublisher`/`TranscriptRouter`),
  transfer/hold/teardown plumbing for STS calls, STS usage/history
  projections, call-spec/API example updates.
- Tagged Google hosted interoperability check (billable; needs explicit
  authorization + fixed budget), including interrupted-reply and resumed
  session turns.
- Bounded synthetic load (LLM+TTS vs Morse STS vs STS+STT), rendered
  desktop/mobile UI pass, independent implementation review, full umbrella
  `mix test`.
- Milestones index stays unchecked until those gates pass.
