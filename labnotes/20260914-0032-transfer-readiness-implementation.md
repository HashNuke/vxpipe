# Transfer readiness implementation

## Scope and design review

The user authorized implementation of the complete transfer-readiness/wait-sounds milestone,
including the renamed `transfer_joining` slot. Work begins from a clean tree. Preserve the full
milestone: schema/assets, private independent playback, resource readiness, startup waiting,
coordinated agent/human handoffs, failure handling, web/phone verification and all root gates.
No runtime acceptance is claimed by the first checkpoint alone.

Read the milestone/index, prerequisite specifications, approved transfer/acceptance/privacy
contracts, current independent opening-audio contract and incremental policy contract. Reviewed
ownership: pure definition compilation selects sources; call preparation fetches/normalizes assets
before admission; live authority owns neither network preparation nor media pacing. URL values,
explicit silence and omission remain distinct. Readiness and the cue remain required with silence.

## Definition and asset checkpoint

- Five schema regressions failed on missing fields/old schema before implementation. The current
  schema is `20260914.01`; `20260913.01` remains accepted with its original closed fields and
  schema identity. Its newly prepared calls resolve omitted waits to the approved defaults.
- All 53 compiler tests pass. JSON/Elixir parity, destination defaults, per-slot/whole-object nil,
  exact URL selection, safe inspection, malformed fields and compatibility are covered.
- Five asset tests first failed because preparation was absent. Shared sources now load once per
  preparation, use the bounded existing fetch/address/cache path, and normalize mono/stereo PCM16
  to 48 kHz mono. URL cache entries have a 60-second preparation freshness window; older entries
  are fetched again, while already prepared calls retain immutable bytes. Opening assets keep
  their existing mono-only profile and cache behavior.
- The real bundled WAVs revealed malformed RIFF sizes: ChucK included the eight-byte RIFF header.
  Corrected only those four-byte size fields in the engine copies, preserving all samples and
  authoring originals. Remote WAV decoding remains strict. Generated a 250 ms, 1 kHz connection
  cue at -6 dBFS with 5 ms edge ramps. The 11 asset/opening-pipeline tests pass.
- Calls preparation now pins normalized assets/digests before creating a call/token; web and
  telephony share that factory. Embedded startup prepares an unprepared plan before creating a
  room. Prepared manifests deduplicate bytes by content digest and exclude contents from inspect.
- Admission regressions reproduced an unsafe URL being admitted and missing prepared assets.
  All 12 admission tests now pass. The memory repository returns `:error` for absent calls;
  corrected the fixture expectation after the intended asset rejection passed.
- The PostgreSQL reconstruction regression failed on missing prepared assets and now passes:
  source selection, normalized bytes, cue, and the complete plan/digest survive retrieval.
- Formatting, warnings-as-errors compilation and strict Credo pass. The final umbrella run passes 1,025 tests with zero failures and 15 existing integration exclusions.

- Full-suite verification initially exposed the opening tests' tiny 256/1,024-byte asset caches,
  which could not store the newly required default loops. Increased only those fixture caches to
  4 MiB while retaining their existing download/duration limits. All 14 opening room tests pass.
- A legacy serialized plan regression reproduced missing wait fields at runtime preparation.
  Explicit hydration at the engine preparation boundary supplies the new defaults without mutating
  original serialized history, identities, participants or schema. Already prepared manifests are
  returned unchanged. All six wait-schema tests pass.

Final first-checkpoint gates: `mix format --check-formatted`, `mix compile --warnings-as-errors`,
`mix credo --strict`, `mix test` (1,025 tests, zero failures), and
`mix deps.unlock --check-unused` all pass. No UI behavior changed in this checkpoint; rendered
browser/live-provider acceptance remains part of the following runtime work. The development
sample selects the new schema and omitted-slot defaults with `wait_sounds: %{}`.

## Playback primitive checkpoint

- Four initial player regressions failed because no player existed. A supervised player now owns
  one participant/episode cursor. It sends at most one PCM frame per output and waits for actual
  completion on every sink before advancing. Asynchronous OTP request IDs keep the player
  responsive while output calls are pending; generation/correlation checks reject stale completion.
- Pause and stop drain the outstanding frame before acknowledging, with no codec restart and no
  queued loop tail. Resume uses that listener's own cursor. The cursor wraps within a frame rather
  than padding every loop boundary. A five-second frame deadline and output/owner monitors bound
  failed playback; the enclosing attempt deadline remains the room controller's responsibility.
- Five focused player tests pass: shared ten-second audio at seven/three seconds, independent
  resume, no premature advance, gapless sample wrapping, finite cue completion, sink failure
  isolation, and multiple output sinks following one participant cursor.
- Private PCM initially entered both native WebRTC and common phone recording handoffs. The two
  red boundary tests now pass after adding an explicit private audio scope, pinned for the whole
  output turn and excluded from recording acceptance. Conversation output retains its existing
  recording behavior. The player always emits private frames. Thirteen focused Gateway native
  output tests pass.
- This primitive is exposed through the owning RoomCapabilitySupervisor. It is not yet attached
  to startup/transfer orchestration. The shared recipient output arbiter, initial output-before-
  capability startup, readiness descriptors/adapters, coordinated transfer release, restoration,
  telemetry and browser/phone acceptance still require implementation.

### Next integration decisions

Existing WebRTC uses separate direct-output and room-mix encoders; phone uses separate direct and
room-output pipelines too. They must converge before encoding. A shared recipient output owner
must serialize private frames and permitted mixed frames on the same native output timeline,
relay correlated completion, prioritize private phases, and clear/drain old room generations.
Retain upstream RoomAudioEgress subscription/policy checks while replacing its second encoder
with delivery into that shared output. Do not implement this by starting another codec per wait.
The common phone output's existing interrupt currently replaces its pipeline; wait transitions
must use ordered drain/clear that retains the codec. Native phone sinks currently acknowledge
socket submission; provider marks still need explicit integration for the milestone's cue proof.

All five root gates pass for the playback primitive checkpoint: formatting, warnings-as-errors
compilation, strict Credo, 1,032 umbrella tests with zero failures, and unused-dependency checks.
Runtime integration and rendered/provider acceptance remain pending.

## Ordered native-output clear checkpoint

- The shared-output integration needs to stop queued audio without replacing a codec. Added a
  separate `OutputSink.clear/1` boundary; ordinary TTS interruption keeps its existing contract.
- Both native output regressions first failed on the missing clear message. WebRTC now discards
  queued packets and acknowledges clear only after its already-sent packet's paced boundary,
  preserving encoder, SSRC and RTP sequence/timestamps. Common phone output discards queued PCM,
  drains its one in-flight encoded frame, sends the provider clear action, then acknowledges.
  Its pipeline PID and delivered sequence clock survive; dropped queued frames do not create
  a timestamp gap before the next output.
- New writes are rejected while clear is pending. Pending producer calls receive interruption
  errors, and a cleared turn never emits a false complete-playback callback. Fifteen focused
  native output tests pass, including unchanged recording and ordinary interruption behavior.
- The operation is a transport primitive, not proof of remote phone speaker playback. Provider
  mark integration, shared recipient arbitration, lifecycle gates and all runtime acceptance
  remain part of the active goal.
Native clear checkpoint root verification: formatting, warnings-as-errors compilation, strict
Credo, 1,034 umbrella tests with zero failures (15 integration tests excluded), and unused
dependency checks all passed. Shared output integration and provider playback marks remain pending.

## Shared recipient output checkpoint

- Added Gateway-owned arbitration before native encoding. Production WebRTC setup, human
  promotion and both phone setup/promotion paths now hand room mixer frames to the same native
  output used by direct/private playback. `SharedOutputPipeline` owns subscription binding and
  completion translation; it has no encoder or pacing clock. The native output survives a room
  binding replacement and private/room source changes.
- Private output waits for the single admitted room frame. During private playback, room frames
  are discarded rather than queued for later replay. A held output accepts only private frames
  from its current generation; release requires drained output and the exact generation. These
  boundaries are ready for engine lifecycle integration; no call/transfer phase uses hold yet.
- Mixed frames have a distinct internal audio scope to avoid recording the already recorded room
  mix again through the direct speech recording handoff. Private recording exclusion is retained.
- Eight focused regressions cover one RTP timeline through room/private/room delivery, production
  room routing, generation fencing, drain-before-release, binding replacement, binding during a
  clear, preserving pending private playback across a room replacement, invalid frames and a dead
  direct producer. Tests first reproduced missing arbitration and then the replacement/invalid
  frame/producer-death races; all pass after the corresponding fixes.
- Existing human WebRTC transfer and Telnyx/Twilio media-session tests pass through the new path.
  Provider playback marks, wait/cue lifecycle integration, common readiness, and rendered/provider
  acceptance remain pending. Native local completion is not claimed as remote phone playout.
- Full-root verification initially hit the existing transcript-router fixture's 100 ms policy
  timeout. Its five focused tests passed unchanged. The complete root recheck then passed all
  five gates: formatting, warnings-as-errors compilation, strict Credo, 1,042 tests with zero
  failures (15 excluded integrations), and unused-dependency checks.

## Phone playback marks and finite cue drain

- Primary provider contracts checked: [Twilio WebSocket messages](https://www.twilio.com/docs/voice/media-streams/websocket-messages)
  and [Telnyx media streaming](https://developers.telnyx.com/docs/voice/programmable-voice/media-streaming).
  Both return pending marks on clear as well as ordinary completion. Therefore clear cancels the
  previous pending request before emitting a fresh marker after the clear command. Only that exact
  new marker may acknowledge the clear. Duplicate/stale marks are ignored and foreign streams
  fail socket validation. Marker names are opaque random values; payloads and participant data
  are not embedded in them.
- Gateway sockets retain at most one pending playback-control request. Playback feedback stays
  at the Gateway media boundary; the engine telephony event adapter retains its existing event
  contract and ignores transport marks after validation.
- Added explicit final `OutputSink.drain/1`. Native phone output waits for the exact mapped
  socket acknowledgement, rejects new writes meanwhile, and fails closed after a bounded missing
  acknowledgement. Clear supersedes an outstanding drain without accepting its late callback.
  WebRTC requires its last paced packet to finish. Arbiter release remains closed during drain.
- Finite cue players now drain all sinks after the last locally completed frame before reporting
  completion. Looping waits still pace one frame at a time without imposing one network round-trip
  per 20 ms audio frame. Players carry the held output generation into their private frames.
- Focused socket checks first failed on missing commands; native tests first failed on missing
  drain support; arbiter tests first failed on missing forwarding; the cue test first failed on
  the missing held generation. Forty Gateway output/socket/decoder checks and six engine player
  checks pass. Full-root results follow separately. These are deterministic protocol checks;
  audible provider and rendered browser acceptance remain pending.
- The first root run exposed an old Twilio session fixture that discarded playback-control
  commands. Updated that simulated socket to process clear/mark ordering and acknowledge the
  generated marker; its real PCMU ingress/egress and interruption test now passes. The next root
  run hit a separate 100 ms room-mixer policy fixture timeout; that fixture-only fix has its own
  checkpoint labnote and commit.
- Review found a potential synchronous cycle: a phone socket could wait for a call event whose
  processing awaited a playback mark on that socket. Both provider sockets now submit call events
  asynchronously, preserving the originating socket identity and event ordering. Outstanding
  events are bounded to 128; saturated media is discarded, control saturation fails closed, and
  each request retains the existing five-second deadline. Playback marks stay immediately
  serviceable. Two regressions first reproduced blocked event dispatch, then passed with the
  actual leg deliberately suspended while the socket processed a playback acknowledgement.

### Next integration findings

The playback-marks checkpoint passes all five root gates: formatting, warnings-as-errors
compilation, strict Credo, 1,053 umbrella tests with zero failures (15 excluded integrations),
and unused-dependency checks. Existing complete phone-transfer harnesses now explicitly await
the asynchronous start-event acknowledgement before inspecting their media sessions.

- Inspection found native phone output relying on Membrane.Realtimer for local pacing. Its installed
  implementation sends timestamps that are behind wall time immediately. Because the retained
  output sequence excludes idle gaps, restarting a loop after idle can enqueue audio faster than
  playback until the stream catches up. The following checkpoint adds a native pacing
  boundary that prevents this burst while retaining the codec/timeline. Provider final marks
  prove drain but are not a substitute for bounded local pacing.
- `Startup.start_entries/3` still performs entry activation and TTS/opening preparation in the
  room startup path; `StartupReadiness` still keys completion to caller attachment/STT. The next
  orchestration work must expose early caller output, prepare resources asynchronously and build
  the complete candidate resource set before using the new holds, players and drain barrier.

## Phone pacing across idle gaps

- Native output now retains the in-flight frame until its local 20 ms pacing boundary before
  admitting the next frame. After a real idle gap the next boundary starts from the current time;
  small encoding delays use the remaining time to the existing boundary, avoiding accumulated
  per-frame drift. Codec processes and the delivered sequence clock are preserved.
- The controlled-clock regression first failed because no paced acknowledgement was scheduled.
  It now covers normal completion, a 20-second idle gap, stale timer rejection and a four-millisecond
  encoding delay absorbed by the next boundary. Existing native output and full phone call checks
  also pass: 16 focused tests with zero failures.
- All five root gates pass: formatting, warnings-as-errors compilation, strict Credo, 1,054
  umbrella tests with zero failures (15 integrations excluded), and unused-dependency checks.
  Initial wait orchestration, common readiness and coordinated transfer release remain pending.
