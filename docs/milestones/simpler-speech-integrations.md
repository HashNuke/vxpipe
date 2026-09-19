# Simpler speech integrations

Status: proposed; research and local specification review complete on 2026-09-19.
Implementation: **0 of 8 checkpoints complete**. The user requested this research/plan and
the Cartesia, AssemblyAI, Rime, ElevenLabs and Gemini comparison. No implementation is claimed.

Prerequisites: the implemented speech path in [Call-Spec-driven calls](call-spec-driven-call.md),
[Local Morse providers](morse-code-audio-providers.md),
[Opening audio](opening-audio-and-call-lifecycle.md),
[Live mixing/media policy](live-mixing-and-media-policy.md),
[Usage observations](usage-and-billing-observations.md), and
[Tenant credentials/platform configuration](tenant-provider-credentials-and-platform-configuration.md).
Retain the implemented readiness/preparation contracts linked below; the remaining live-carrier
acceptance in other milestones is not a prerequisite for changing the speech boundary.

Design sources:
[semantic contract](../speech-provider-contract.md),
[provider comparison](../speech-provider-comparison.md),
[architecture](../architecture.md),
[inline selections](../inline-provider-selections.md),
[current platform/tenant credential inheritance](../platform-and-tenant-services.md),
[readiness resources](../readiness-resource-contract.md),
[typed interruption](../typed-turn-interruption.md),
[spoken barge-in](../spoken-barge-in.md),
[opening contract](../opening-audio-contract.md),
[transport privacy](../speech-transport-privacy.md), and
[resolved egress-buffer issue](../issues/tts-egress-buffer.md).

## Runnable outcome

A developer writes one documented provider-session interface for STT or TTS, uses shared
event/audio delivery helpers, and registers it in the closed catalog. The developer does not
implement a second public transport interface, manufacture JSON for local processing, or read
the room state machine to determine when an utterance is finished.

Both existing Morse and Deepgram selections run through that boundary. A direct-PCM Morse
room still recognizes input, invokes the existing local model fixture, synthesizes a response,
plays it fully and survives an interrupted response followed by another turn. Hosted speech,
opening audio and private transfer speech retain their existing externally observable contracts.

The comparison informs conformance tests; it does not add five hosted integrations. Gemini
Live and batch transcription remain separate future contracts. Dedicated request-based TTS
is demonstrated using a synthetic provider with no persistent connection or started event.

## Contract and scope

The [design](../speech-provider-contract.md#proposed-author-facing-interface) proposes four
required STT functions and five TTS functions: configuration, supervised startup, audio input
or speak/cancel, and close. Configuration returns a descriptor instead of several metadata
callbacks. Providers emit typed semantic results through a shared bounded channel.

Existing approved contracts remain authoritative: room-owned attribution and turn admission,
privacy-interval enforcement, fresh readiness, scoped credentials, bounded buffers, locally
confirmed playback, usage provenance, independent opening TTS and explicit provider failure.
The new public interface and internal module names are proposed by this milestone.

Keep scope in `vxpipe_call_engine`; do not extract another application or add a dependency
unless implementation demonstrates a separate need and records it. No Call Spec schema or
public provider-name migration is intended. No automatic reconnect, request replay, speech
fallback, new VAD, new codec/resampler, browser protocol, provider account or model is added.
Incremental TTS text input and manually finalized STT need their own authorized consumers.

## Delivery strategy

Implement the checkpoints below in order. Each has an executable vertical outcome, a small
set of file changes, a red test and an exit gate. The standalone provider slices deliberately
prove real audio before altering room orchestration. Existing paths remain usable during them.

Temporary bridges exist only while one built-in provider still uses the old boundary. Remove
the STT bridge in checkpoint C and the TTS bridge in F. Do not expose bridge selection in Call
Specs or keep two long-term configuration APIs. Preserve user changes in the worktree.

For each checkpoint: run the smallest owning-child test red for the stated project behavior,
implement it green, then refactor; update relevant docs and labnotes. Run the broader relevant
suite and all five root gates before treating that checkpoint as usable. A checkpoint is a
candidate coherent commit only when the user authorizes commits; this plan authorizes none.

Paths in the task lists are relative to `apps/vxpipe_call_engine/` unless stated otherwise.
`lib/vxpipe/call_engine/` is abbreviated `lib/` below. Proposed files are explicitly described
as new; naming may be refined without changing the contracts or checkpoint acceptance.

| Checkpoint | Runnable slice | Candidate commit subject |
| --- | --- | --- |
| A | Independent PCM fixture becomes typed STT events through a native Morse session. | Introduce semantic STT sessions with Morse decoding |
| B | A normal room uses native Morse STT while hosted STT remains usable. | Route room speech input through semantic sessions |
| C | Deepgram STT uses the same interface with its wire protocol kept private. | Migrate Deepgram speech recognition to sessions |
| D | A native Morse TTS session emits real PCM, cancels and accepts a replacement. | Introduce semantic TTS sessions with Morse synthesis |
| E | A normal room and independent opening use semantic TTS and real sink playback. | Route speech output through semantic sessions |
| F | Deepgram TTS uses speak/cancel and preserves long-output and interruption behavior. | Migrate Deepgram synthesis to semantic operations |
| G | A developer runs the guide and shared tests against contrasting provider shapes. | Add speech provider conformance examples |
| H | Every existing speech consumer uses the final configuration and contract. | Complete speech session migration and remove legacy contracts |

## Checkpoint A — Native Morse STT session

Outcome: feed an independently generated PCM phrase into the new session facade and receive
ready/start/transcript/end events without a socket or JSON translation. Existing room speech
continues using its current path until B.

- [ ] **A1 — Red contract test.** Add `test/vxpipe/call_engine/speech/stt_session_test.exs`:
  start under `start_supervised!`, inject the existing independent Morse fixture in odd-sized
  chunks, and expect one ordered final transcript. Confirm failure because the new API is absent.
- [ ] **A2 — Minimal public data/API.** Add new `lib/speech/stt_provider.ex`, `descriptor.ex`,
  `event.ex` and `session.ex` with pure configuration, typed metadata, explicit readiness and
  bounded audio admission. Implement only what this real provider and safety checks require.
- [ ] **A3 — Native provider.** Add `lib/provider/morse_code_stt/session.ex` around the existing
  Morse Config/Decoder; publish semantic events directly. Retain old callers until B and avoid
  duplicating the decoder or creating fake hosted request IDs.
- [ ] **A4 — Owned lifecycle.** Extend `lib/application.ex` with explicitly named supervision
  for session children/workers; bind owner loss to teardown, use temporary children, and fence
  early/late events by session generation. Keep connect and command waits bounded.
- [ ] **A5 — Failure and example.** Cover malformed/oversized input, duplicate envelopes,
  teardown during startup, safe errors and no audio/text/secret inspection. Add a short runnable
  standalone example to `apps/vxpipe_call_engine/README.md` with truthful format limitations.
- [ ] **Exit A.** Independent expected text is observed through the public session API; owner
  death produces monitored teardown; existing Morse codec/transport/room tests and root gates pass.

## Checkpoint B — Room STT and policy integration

Outcome: the ordinary Morse audio room uses the new STT session while Deepgram remains available
through one private migration bridge. Denying transcription demand prevents speech processing.

- [ ] **B1 — Red room test.** Extend `provider/morse_code/room_round_trip_test.exs` to select the
  native session with no transport registration, assert attributed text, and finish the response.
- [ ] **B2 — Resolve the session.** Update `lib/capability_catalog.ex`, STT branches in
  `plan_startup.ex`, `speech_to_text_runtime.ex` and owning startup/supervisor calls. Use the
  descriptor and existing credential source; add a private legacy-STT bridge only for Deepgram.
- [ ] **B3 — Preserve policy allocation.** Change `lib/capability/speech_to_text.ex` and its
  `state.ex`, `transport_connector.ex`, `policy_preparation.ex` and private-allocation integration
  to bind session events instead of wire messages. Keep prepared sessions isolated until adoption.
- [ ] **B4 — Red privacy races, then implement.** Test no-demand startup, revoke/relax, a delayed
  old transcript, immediate ready during connection, cancelled preparation and unrelated policy
  changes. Retain exact interval attribution and fresh readiness for replacement sessions.
- [ ] **B5 — Usage/config/docs.** Preserve STT accepted-audio/final-text counting, provider IDs
  and payload-free telemetry. Update the Morse entry in root `config/dev.exs` and the room
  example. Keep hosted configuration working through the bridge.
- [ ] **Exit B.** Native Morse STT completes the real room loop; media-policy, readiness,
  barge-in, usage and redaction tests pass alongside the existing hosted adapter tests.

## Checkpoint C — Native Deepgram STT

Outcome: the same room capability accepts Deepgram recognition events through a native semantic
session. A tagged local wire server proves framing/authentication; live acceptance is separate.

- [ ] **C1 — Red wire boundary.** Extend the tagged `test/integration/speech_socket_privacy_test.exs`
  and STT capability fixtures to drive the semantic API, including a Connected frame coalesced
  with the upgrade, ordered turns and an upstream duplicate.
- [ ] **C2 — Move protocol ownership.** Add `lib/provider/deepgram/flux/session.ex`; retain or
  extract the existing bounded parser from `flux.ex`. Reuse `socket.ex`/`socket_connection.ex`
  internally. Translate to typed events and reject stale upstream sequence IDs before emission.
- [ ] **C3 — Close/failure/readiness.** Prove provider acknowledgement is required, bad/stalled
  upgrades fail safely, owner loss closes allocation, privacy cancellation drops late results,
  and no reconnect occurs. Preserve supported linear16/Opus framing and existing timeouts.
- [ ] **C4 — Remove STT bridge.** Update Deepgram selection/config and test fixtures; remove the
  migration bridge and old STT transport requirements from engine startup. Private wire helpers
  may remain. Update the STT authoring example and usage/telemetry mapping.
- [ ] **Exit C.** Local wire, STT room/policy and credential boundary tests pass. Run the existing
  tagged live Flux/RTVI lane when its inputs are available; record missing credentials/audio or
  endpoint mismatches as hosted acceptance blockers, without claiming local fixtures prove parity.

## Checkpoint D — Native Morse TTS session

Outcome: a standalone `speak` request produces independently checked PCM; cancellation while
delivery is backpressured remains responsive and a replacement request finishes cleanly.

- [ ] **D1 — Red streaming test.** Add `test/vxpipe/call_engine/speech/tts_session_test.exs` for
  native Morse speak, acknowledged bounded audio and one terminal completion. Assert sample
  runs with the existing independent fixture/decoder, not solely an encoder/decoder round trip.
- [ ] **D2 — TTS contract/output helper.** Add `lib/speech/tts_provider.ex`, `output.ex` and typed
  TTS request/event support. Define admission versus `input_submitted`; reuse A's descriptor,
  identity, bounded event delivery and supervision rather than another generic runtime.
- [ ] **D3 — Native provider.** Add `lib/provider/morse_code_tts/session.ex` using the existing
  incremental Encoder. Remove Speak/Flush/Interrupt JSON from this native path; retain the old
  room entry temporarily until E. Preserve sample pacing, output format and size limits.
- [ ] **D4 — Red cancellation races, then implement.** Hold audio credit, cancel before first
  audio and mid-output, race done/cancel, then synthesize again. Prove bounded memory, no stale
  audio, idempotent cancellation, one terminal result and prompt owner/producer teardown.
- [ ] **D5 — Standalone demo.** Document one text-to-PCM/WAV example and its format/sample
  assumptions. Keep generated audio artifacts outside version control and retain safe volume.
- [ ] **Exit D.** A long phrase drains completely with one chunk in flight, the independently
  checked replacement is clean, and current room TTS remains usable with all relevant gates green.

## Checkpoint E — Room TTS, playback and independent opening

Outcome: the real Morse audio round trip uses both new interfaces; independent opening TTS
works for an initial human receiver and remains gated on actual output playback.

- [ ] **E1 — Red playback test.** Extend `text_to_speech_turn_test.exs` and
  `opening_audio_room_test.exs`: select native Morse without a transport, withhold sink finish,
  and prove generation completion does not finish the turn or release opening input.
- [ ] **E2 — Resolve TTS sessions.** Update TTS branches of `plan_startup.ex`,
  `text_to_speech_runtime.ex`, `capability_catalog.ex` and capability-supervisor/startup callers.
  Compose descriptor metadata with existing selection and credential-scoped cache identity.
  Keep one private legacy-TTS bridge for Deepgram until F.
- [ ] **E3 — Simplify capability orchestration.** Change `lib/capability/text_to_speech.ex` to
  call speak/cancel and handle request-scoped audio/terminal events. Keep its bounded queue,
  sink task and draining states; put provider speech IDs and wire offset translation in the
  bridge or native provider. The shared playback ledger retains actual sink progress, including
  interruption after generation finishes. Preserve listener-first interruption and the normal
  unavailable path.
- [ ] **E4 — Preserve accounting and cache.** Red-test rejected admission, admitted-but-unsent
  failure, submitted-text failure, discarded generated audio, duplicate terminal settlement,
  cancellation during sink drain followed by correct next-request playback offsets,
  warm cache credential checks and independent opening/agent voices. Update capability Usage
  and `usage/text_to_speech_attempt.ex` only where event projection changes.
- [ ] **E5 — Consumer/config coverage.** Route private briefing, transfer preparation and source
  restoration through the same startup boundary. Update Morse host config/docs. Keep their
  existing authorization and private-output tests; do not rebuild these workflows.
- [ ] **Exit E.** Two full room turns, interrupted replacement, cold/warm independent openings
  and human-entry opening gates pass. Recording privacy and usage remain unchanged; hosted TTS
  still works through its private bridge.

## Checkpoint F — Native Deepgram TTS

Outcome: hosted TTS implements semantic speak/cancel, and the capability has no knowledge of
Deepgram speak/flush commands, speech IDs or cumulative interruption offsets.

- [ ] **F1 — Red hosted mapping test.** Drive a native session through controlled protocol
  frames and tagged local wire tests. Cover accepted Speak followed by failed Flush, first
  audio without changing the engine API, and completion only after all audio is delivered.
- [ ] **F2 — Provider ownership.** Add `lib/provider/deepgram/flux_text_to_speech/session.ex`;
  reuse validated configuration/parsing and the private Mint socket implementation. Own wire
  speech correlation, flush, cumulative offsets and safe interruption/drain boundaries here.
- [ ] **F3 — Red isolation tests, then implement.** Test cancel before speech start, zero-played
  cancellation, late old audio, cancellation with an outstanding sink write, failed terminal
  isolation and provider disconnect. Keep one authoritative request mapping and bounded waits.
- [ ] **F4 — Remove TTS bridge.** Update catalog/host settings, integration fixtures and the
  tagged live TTS test to call semantic operations. Delete the bridge; retain useful internal
  socket/parser helpers. Verify credential/header/payload redaction in both success and failure.
- [ ] **Exit F.** Local wire tests, queued turns and long-response gateway egress tests pass.
  Run existing tagged live TTS and RTVI tests when available; record the actual endpoint/model
  and safe result. Missing live evidence leaves hosted acceptance open, not silently checked off.

## Checkpoint G — Authoring guide and contrasting contract profiles

Outcome: a developer follows the guide to implement and run a provider using the public
behaviour/helpers, without depending on Call Engine private messages or any real new account.

- [ ] **G1 — Shared conformance harness.** Extract project-owned assertions from A/D into
  `test/support/speech_provider_contract.ex` (or cohesive separate STT/TTS files). Expose setup
  hooks and observable assertions, not assumptions about provider internals or OTP behavior.
- [ ] **G2 — Request TTS profile.** Add a test-only provider whose owned worker returns streamed
  audio without connected/started wire messages; test bounded whole-response adaptation too.
  Prove cancellation/owner death terminate the worker and late completion cannot revive output.
- [ ] **G3 — Context and batch profiles.** Add controlled scenarios for context-tagged cancel
  and multiple/coalesced synthesis-batch boundaries. Prove a flush count or first batch `done`
  cannot finish the engine request. These model Cartesia/ElevenLabs/Rime distinctions, without
  purporting to be those providers' protocol implementations.
- [ ] **G4 — Segmented STT profile.** Test revised partials, committed segments, optional eager/
  resume and actual end-of-turn separately. Reject a manual-finalize/no-endpointing descriptor
  at conversational admission. Include a provider with no upstream sequence numbers and prove
  local envelope ordering without inventing upstream deduplication evidence.
- [ ] **G5 — Guide and runnable example.** Add `docs/speech-integration-guide.md` with a complete
  minimal provider, descriptor, private credential flow, registration location, event/error
  table, bounded delivery example and exact conformance commands. Exercise the example as code
  in test support. Update the Call Engine README and link the comparison's supported/deferred modes.
- [ ] **Exit G.** Both native providers and the independent structural profiles pass the shared
  checks; the guide requires neither a public transport module nor raw message tuples. Helpers
  do not assume WebSockets, vendor speech-start events or equal provider feature sets.

## Checkpoint H — Final configuration and all-consumer acceptance

Outcome: source and embedded configurations run only the final contract, existing call specs
still load, and all remaining references are deliberate private wire implementations.

- [ ] **H1 — Finish config migration.** Remove obsolete public provider/transport settings and
  callback behaviours from `plan_startup.ex`, runtime structs, root `config/dev.exs`, test
  support and embedded examples. Keep host limits and closed catalog validation explicit.
  Obsolete settings fail clearly; do not silently ignore them or introduce persisted bridges.
- [ ] **H2 — Verify activation boundaries.** Run focused credential tests in Engine, Calls and
  Persistence for tenant override/platform inheritance, fresh lookup on new activation, retained
  snapshots in running sessions, opening cache scope, private briefing and source restoration.
  Stored Call Specs/plans keep their current schema and contain no private session data.
- [ ] **H3 — End-to-end acceptance.** Run the deterministic direct-PCM room demo, existing
  native WebRTC/egress regression tests and existing hosted STT/TTS lanes. Exercise typed and
  spoken interruption followed by another usable turn. Carrier-specific new live calls are not
  required for an unchanged transport boundary; affected carrier media regression tests remain.
- [ ] **H4 — Documentation and rendered check.** Update architecture, development, interruption,
  readiness, inline-selection and privacy docs to describe the implemented boundary. Inspect
  the existing sample call using `agent-browser`/Chrome for connected, speaking, interrupted and
  replacement states. Record any unavailable browser/provider check explicitly; source review
  cannot establish rendered or audible behavior.
- [ ] **H5 — Final audit/gates.** Search for legacy callbacks/tuples outside provider-private
  modules, inspect status/diffs, run all common root gates, and record actual results and unresolved
  external checks. No new hosted provider or new format may appear merely because it was compared.
- [ ] **Exit H.** Complete the evidence ledger, all required acceptance lanes and author guide;
  mark the milestone/index complete together only then. Packaging and retention holds remain.

## Verification map and commands

Existing tests to retain/extend, not a claim that they ran during this planning task:

| Contract | Existing Engine tests under `test/vxpipe/call_engine/` unless noted |
| --- | --- |
| Independent Morse audio | `provider/morse_code/{codec,local_transport,room_round_trip}_test.exs` |
| STT readiness, ordering, privacy | `capability/speech_to_text_test.exs`, `capability/speech_to_text_redaction_test.exs`, `speech_to_text_media_policy_room_test.exs`, `media_policy/speech_to_text_demand_test.exs` |
| TTS queue, credit, interruption, usage | `capability/text_to_speech_test.exs`, `text_to_speech_turn_test.exs`, `text_to_speech_runtime_test.exs`, `usage/text_to_speech_attempt_test.exs`, `spoken_barge_in_test.exs` |
| STT usage and readiness resources | `usage/speech_to_text_session_test.exs`, `readiness/provider_test.exs`, `media/connection_readiness_test.exs` |
| Opening/recording gate | `opening_audio_room_test.exs`, `opening_audio/asset_pipeline_test.exs`, `recording/egress_policy_readiness_test.exs` |
| Wire authentication and bounds | Engine `test/integration/speech_socket_privacy_test.exs`; synthetic local credentials only |
| Hosted interoperability | Engine `test/integration/deepgram_flux_text_to_speech_test.exs`; Gateway `test/integration/{rtvi_deepgram_flux,rtvi_deepgram_flux_text_to_speech,deepgram_flux_opus}_test.exs` |
| Credential selection/cache isolation | Persistence `test/vxpipe/persistence/{provider_credential_runtime,tenant_opening_audio,scoped_provider_credentials}_test.exs`, plus owning Engine/Calls credential tests |

From `apps/vxpipe_call_engine`, run the smallest affected file while iterating, for example:

```shell
mix test test/vxpipe/call_engine/provider/morse_code/room_round_trip_test.exs
mix test --include integration test/integration/speech_socket_privacy_test.exs
```

The second command uses local network fixtures and remains tagged/excluded from the default
suite. Run live files explicitly and individually from their owning child only when required
credentials/fixture audio are available. Do not enable every external integration test by
accident, print secrets, or substitute a local server for claimed hosted acceptance.

From the umbrella root at each completed code checkpoint:

```shell
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix test
mix deps.unlock --check-unused
```

Use monitors and acknowledgements for race tests, no sleep/liveness polling. Preserve the
existing limits unless a focused red test and documented decision require changing one.

## Evidence ledger

| Checkpoint | Implementation | Red/green and root evidence | External/manual evidence |
| --- | --- | --- | --- |
| A | Not started | Pending | Standalone PCM proof pending |
| B | Not started | Pending | Real room loop pending |
| C | Not started | Pending | Local wire and hosted STT pending |
| D | Not started | Pending | PCM playback/replacement pending |
| E | Not started | Pending | Room/opening proof pending |
| F | Not started | Pending | Local wire and hosted TTS pending |
| G | Not started | Pending | Independent guide exercise pending |
| H | Not started | Pending | Browser/hosted final acceptance pending |

## Specification review

Local review on 2026-09-19 checked the proposed API against current source and the requested
provider documentation. It is separate from implementation and is not an independent-agent
approval. The review corrected four risks: segment finality was too easily confused with turn
end; synthesis batches with request completion; admission with provider submission for usage;
and local cancellation with upstream cancellation certainty. The design now states each boundary.

Dependency review: all direct prerequisite milestones precede this entry in the index. A/D are
standalone real-audio slices; B/E integrate them; C/F remove their temporary bridges; G tests
contrasting shapes; H removes legacy authoring configuration and verifies existing consumers.
The conservative index position is before delivery and retention; no runtime dependency on
the onboarding UI is introduced and existing packaging authorization holds are unchanged.

Research and planning verification are recorded in the
[labnote](../../labnotes/20260919-1534-simplify-speech-integrations.md). No implementation task
or acceptance checkbox is checked by writing/reviewing this specification.
