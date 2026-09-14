# Initial call waiting

- Previous turn made progress: 7e7e8a4 fixed stale initial handoff preparation and retained prepared
  resources; all five root gates passed (1,306 tests). Revalidated HEAD and worktree; preserve the
  other agent's untracked visual labnote and the running development server.
- Initial caller waiting is still unimplemented. Unlike transfer readiness, room creation invokes
  PlanStartup.validate and Startup.start_entries synchronously. Both invoke model construction;
  initial attachment can mark startup ready without the complete resource inventory.
- Red native case added to the existing peer fixture: blocked reception model construction must
  still return a room, allow a native caller to connect and hear call_setup, reject held text,
  then independently wait for TTS readiness before its fixed greeting. It currently fails waiting
  500 ms for the room after the model constructor announces its blocked state. Evidence:
  vxpipe-initial-call-wait-red.log (one test, one failure).
- Implementation direction: separate static entry validation/minimal caller identity from provider
  initialization; prepare receiver/resources outside RoomAuthority using owning supervisors.
  Existing CallLifecycle remains the absolute timeout authority. Use existing wait players,
  input gates, opening playback and readiness inventory. No alternate public call definition or
  frontend state is needed. Opening priority/resume and phone paths remain part of this slice.

- Initial native flow is green: room admission returns while model construction is blocked;
  peer-decoded waiting audio precedes independent TTS readiness, held text is rejected, then the
  first greeting is emitted. Initial red and green logs: vxpipe-initial-call-wait-{red,green}.log.
- RTVI previously replied bot-ready from codec parsing alone. Its focused codec regression failed
  for that reason, then passed when compatible client-ready became a connection-owned command.
  Room readiness now releases the pending reply. Codec/native focused result: two tests pass in
  vxpipe-initial-rtvi-ready-green.log. An initial 100 ms native absence assertion did not expose
  the old immediate reply reliably; the codec red test supplies the deterministic boundary.
- Regression adaptations: existing embedded announcement tests now use the supervised connection
  adapter and silence call_setup explicitly to isolate opening playback. Simulated connected
  providers now acknowledge initialization. The first STT acknowledgement omitted sequence_id and
  was correctly rejected; fixed the fixture payload. Recording frames now use the fixture's
  advertised track. Assertions await call readiness rather than assuming attachment implies it.
- Complete readiness exposed a real missing adapter in Diagnostics.AgentRuntimeModelProvider.
  The default diagnostic model could answer requests but reported failed readiness because it
  omitted the optional callback. Added its local initialized-fixture readiness contract. Temporary
  probe logging used to isolate this was removed.
- Required conversational TTS failure during file announcement is now a startup failure. The
  previous test called this voice unrelated even though the plan required it for conversation.
  Updated the contract assertion, observed its timeout red, then added immediate failure handling.
- The 21 focused opening/lifecycle tests pass (vxpipe-initial-engine-focused.log). The native
  21-case file initially had one remaining failure: a silent-transfer assertion included queued
  initial phone-ring packets. The fixture now consumes that completed setup audio separately;
  its focused case passes. Full native and root verification are still pending current edits.
- Remaining before this checkpoint: root regressions, formatting/static checks, documentation and
  commit. Full initial-call acceptance still includes independent announcement preparation while
  the model is blocked, URL/nil/failure/phone coverage and freshness through release. Do not mark
  the initial slice complete based only on its successful delayed model/voice native flow.

- Umbrella regression work: the first root run had 73 engine, 15 Gateway and one persistence
  failure. Most older scenarios assumed that room creation or attachment meant conversation
  was ready. Their setup now waits for the project-owned readiness acknowledgement, with no
  production bypass. Pure invalid/disabled configuration still fails before room registration.
- Two old definitions pinned the previous schema; adding wait_sounds there was invalid. Updated
  those fixtures to the current schema before explicitly silencing setup waiting. Other fake
  output sinks do not acknowledge playback, so post-startup tests select nil for call_setup.
- The engine's subsequent 600-case run had one remaining 100 ms file-failure assertion timeout;
  expanded that asynchronous completion assertion to the existing one-second startup bound.
- All 17 targeted Gateway phone/human-audio checks now pass (vxpipe-initial-gateway-second.log).
  Inbound phone fixtures acknowledge selected TTS before injecting conversational STT input.
  The Telnyx media socket also implements existing clear/mark acknowledgement, matching Twilio.
- Native single-frame tests could inject a frame in the same 20 ms bucket as startup completion;
  the existing privacy gate correctly drops frames timestamped across that boundary. They now
  verify a quiet post-startup interval before injecting their isolated frame. No gate was relaxed.
- Strict Credo found RoomAuthority just over its 800-line boundary. Moved startup-result/reply
  handling into its existing StartupReadiness collaborator; no new generic orchestration layer.
- Root/static verification is in progress. This checkpoint does not complete the initial slice;
  keep the outstanding opening independence, cleanup, freshness and phone/configuration checks
  explicit instead of marking their acceptance complete.

- The next root run found two remaining entry races: an inventory-only fixture captured before
  asynchronous entry installation, and the caller-targeting opening test attached its receiver
  before that participant was committed. Both now await entry preparation explicitly.
- The file-opening failure was not merely a short timeout: the room correctly exited with
  opening_audio_unavailable, but the forwarding connection fixture could exit while completing
  STT binding and never forward its room DOWN. The test now owns a direct RoomAuthority monitor.
- That root run also saw the native initial-inventory case lose its caller connection during
  collection. Its isolated repeat and subsequent complete 21-case native run passed. Limited
  temporary result/reason tracing was removed; the exact intermittent connection-loss trigger
  remains unconfirmed, so do not claim that a specific runtime fix resolved it.
- Formatting, warnings-as-errors compilation and strict Credo pass. The current root run's
  600 engine tests pass. Remaining application results are pending.

- Final root attempt had all 600 engine tests green but another native caller disappeared before
  its first ICE PATCH. The common cause is now reproduced: the initial output graph can be
  captured before SDP selects its codec. Collector correctly classifies the changed resource
  signature as binding_changed; StartupProbe discarded that distinction and ended startup.
- Focused red test pauses the first resource observation, changes only its negotiated signature,
  and returns that new binding. It produced readiness_failed. StartupProbe now recaptures only
  binding_changed under the original absolute deadline; genuine failed readiness remains terminal.
  The focused test passes with the same connection instance. An earlier draft paused preparation
  too early and passed because prepare_graph already retries that earlier change; corrected the
  reproduction to the collection boundary. Logs: vxpipe-initial-negotiation-{red,green}.log.

- The complete 21-case native file passes after bounded negotiated-binding recapture with the
  last failing root seed (941444). Both early output and complete room collection share this
  correction. The final five-gate run is recorded separately as vxpipe-initial-final-gates-*.

- Final checkpoint verification passes all five root gates: format, warnings-as-errors compile,
  strict Credo, full umbrella tests and unused-lock check. Seed 571236 with concurrency four:
  1,308 tests, zero failures, 15 integration exclusions. Application counts: 37 + 91 + 601 + 81
  + 337 + 19 + 49 + 93. Evidence: vxpipe-initial-final-gates-results.json and matching gate logs.
- No UI changes or development-server restart were used. Preserve the other agent's vxpipe-docs
  and visual labnote work. This commit is a usable initial-startup checkpoint, not completed
  initial-opening/phone/multiple-listener acceptance or the whole milestone.
