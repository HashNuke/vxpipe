# Human Web Transfers

## Checkpoint: compile a bounded human destination

- Added a red compiler test for a catalog human using the exact web
  `receive`/`transfer` connection intent, an optional fixed notice, and a required private briefing
  reason. The focused test initially failed at the unsupported `transfer_notice` field.
- Schema `20260911.02` now keeps entry and transfer admissions distinct, pins the notice in the
  resolved plan, and permits only agent destinations or web humans with transfer admission.
- Human destinations always require the transfer tool's bounded `reason`; no address, unrestricted
  variables, or conversation history enters model-visible tool arguments.
- Rejected using ordinary `start_call` admission for a transfer destination because it would erase
  the admission boundary needed by the pending private lane.
- Verification: the focused compiler test passes with 12 tests, and the complete Call Engine suite
  passes with 333 tests, 0 failures, 1 excluded.
- The first umbrella pass exposed one unrelated timing-sensitive model-inference timeout assertion;
  its focused rerun passed. The clean full rerun passed formatting, warnings-as-errors compilation,
  all application suites (MCP 37/3 excluded, Agent Runtime 58/2, Call Engine 333/1, Calls 37,
  Persistence 25, Gateway 87/4, Console 57), strict Credo (4,509 modules/functions), and unused
  dependency-lock checks.

## Refactor: participant-neutral room transfer ownership

- Mechanically renamed the room coordinator and its cohesive support namespace from
  `RoomAuthority.AgentTransfer` to `RoomAuthority.ParticipantTransfer`, including its state fields,
  internal messages, and room-supervised worker references.
- The transfer tool and the existing agent-to-agent test remain named for their actual contracts;
  no behavior, public wire format, timeout, or lifecycle rule changed in this refactor.
- Focused verification: all 11 agent-transfer room tests pass after the rename.
- Full verification passes formatting, warnings-as-errors compilation, every umbrella suite with
  the same counts as the prior checkpoint, strict Credo, and unused dependency-lock checks.

## Checkpoint: private web-human room lane

- Added the first end-to-end room test before the runtime behavior. It initially failed to compile
  because `ConnectionAttachment` had no admission or transfer-attempt contract. After that boundary
  existed, the next red run exposed an invalid attempt to project agent transfer history for a human
  destination; human briefing preparation now starts with no implicit conversation history.
- A pending human transfer receives a generated attempt ID. Its provisional connection is bound to
  the catalog destination and is disabled for speech input, room publication, room subscription,
  transcript projection, and participant/Variables authority.
- A dedicated destination TTS capability uses the retained source-agent runtime. It speaks only the
  required bounded reason and optional fixed notice to the destination output sink. The caller sink
  receives no briefing audio.
- `ParticipantTransferControl` records early acceptance and usable-media readiness only for the
  exact actor, participant, connection process, incarnation, and current attempt. The handoff waits
  for both controls and output-sink playback completion. Stale, forged, foreign-process, and
  duplicate controls reject.
- Participant admission applies the existing media-policy commit barrier before the destination
  connection is promoted to ordinary mix-minus media. On success the source agent subtree and its
  speech capability stop, while the room and Call Variables process remain. Dropping the pending
  destination fails and cleans only that attempt; the source remains active.
- Kept the concerns split between the participant-neutral coordinator, human-lane state machine,
  briefing builder, human committer, shared completion projection, connection lifecycle, and typed
  control command rather than adding all callbacks to `RoomAuthority`.
- Focused verification: the three human-transfer room tests pass. The complete Call Engine suite
  passes 336 tests with 0 failures and 1 excluded integration test. Warnings-as-errors compilation
  and strict Credo also pass before the umbrella completion run.
- The first full umbrella test run encountered the existing Console telemetry-isolation race: its
  fixed drop-count assertion observed unrelated concurrent umbrella telemetry. That exact test
  passed alone, and a clean full rerun passed MCP 37/3 excluded, Agent Runtime 58/2, Call Engine
  336/1, Calls 37, Persistence 25, Gateway 87/4, and Console 57.

## Checkpoint: authenticated WebRTC transfer handoff

- Added a red admission test for the catalog destination of a running call. Ordinary call
  admission initially joined it immediately; the gateway now returns a provisional
  `pending_transfer` session bound to the existing room incarnation without changing the call
  start clock or participant presence.
- Added a separate bounded `vxpipe` WebRTC data-channel codec. RTVI continues unchanged on the
  `chat` channel. The sideband carries only preparation, exact-attempt acceptance, activation, and
  a generic rejection; it never serializes the private reason, Variables, history, or internal
  authorization data.
- Added a real two-peer WebRTC test before the adapter behavior. It initially received no
  preparation control, then exposed two deeper ordering problems: policy replacement acknowledged
  before the replacement Membrane pipeline was usable, and an ordinary human caller had no room
  output while the agent's direct TTS path was active.
- `RoomAudioIngress` and `RoomAudioEgress` now expose a readiness barrier backed by their Membrane
  pipeline playing notifications. A replacement-policy call does not acknowledge until the new
  pipeline is ready. Human transfer promotion waits for both main-media pipelines and is sent only
  after the source participant exits, preventing `transfer.active` from racing the final
  presence-driven policy transition.
- Ordinary human connections now retain policy-authorized mix-minus output even while an agent
  owns direct TTS. This keeps human room audio available through handoff without introducing a
  second bridge or tying output authority to STT configuration.
- Kept transfer framing/control and main-media startup in cohesive `Sideband` and WebRTC modules;
  the existing connection process only owns transport callbacks and delegates the transfer
  transition instead of absorbing another independent callback implementation.
- The full transport test requests transfer through the caller's real RTVI channel, verifies that
  destination microphone and speaker are isolated before acceptance, rejects a forged attempt,
  delivers the private briefing only to the destination, then proves caller-to-destination and
  destination-to-caller Opus audio after activation.
- Verification: all 336 Call Engine tests pass with 0 failures and 1 excluded integration test;
  all 94 Gateway tests pass with 0 failures and 4 excluded integration tests. `mix format
  --check-formatted`, `git diff --check`, `mix compile --warnings-as-errors`, `mix credo --strict`,
  and `mix deps.unlock --check-unused` also pass at this checkpoint. The umbrella `mix test` first
  stopped before execution because the shell had no PostgreSQL SCRAM password. A disposable local
  PostgreSQL instance on the reserved test port supplied `VXPIPE_TEST_DATABASE_URL`; the complete
  umbrella suite then passed (MCP 37/3 excluded, Agent Runtime 58/2, Call Engine 336/1, Calls 37,
  Persistence 25, Gateway 94/4, and Console 57), and that test instance was stopped afterward
  without touching the existing project test database container.

## Checkpoint: sample transfer admission

- Added the red Console contract for issuing a token to the configured transfer destination of the
  latest prepared sample call. The first run rejected the new sample option and had no transfer
  API, as expected.
- The supervised sample process now resolves and retains the published destination route while
  keeping its API key private. After caller preparation it can issue a fresh, participant-scoped
  join token for that same call through the existing Calls workflow. Before any sample call is
  prepared it returns `call_not_prepared`; an omitted destination keeps this feature disabled. A
  focused follow-up caught transfer preparation rerunning tenant/definition provisioning; ready
  sample state now reuses its pinned published routes and the test proves provisioning occurs once.
- Added same-origin `POST /sample/transfers`. It returns only the public call/participant locator
  and expiring join token, sends no CORS allowance, and shares the existing admission presenter
  with caller preparation.
- A new gateway red test showed that claiming a transfer-only token against a merely prepared call
  reached the room-start path. Admission now rejects that destination before starting a room;
  transfer-only participants can receive provisional sessions only after the caller has started
  the pinned call.
- The development definition now includes a catalog `human-support` web destination, allows the
  reception agent to select it with a bounded reason, and configures it as the sample transfer
  destination. A no-start development check parses all four configured participants successfully.
- Focused verification: all four sample-process tests, ten Console endpoint tests, and three
  gateway admission-adapter tests pass.
- Completion verification passes formatting, warnings-as-errors compilation, strict Credo,
  unused dependency-lock checks, and the full umbrella suite (MCP 37/3 excluded, Agent Runtime
  58/2, Call Engine 336/1, Calls 37, Persistence 25, Gateway 95/4, and Console 59). The disposable
  test database was stopped again after the run.
