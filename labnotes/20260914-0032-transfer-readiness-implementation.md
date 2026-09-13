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

## Required-resource barrier

- Added explicit resource descriptors and ordered reports with room incarnation, attempt, request,
  instance/session generation, configuration signature and relevant policy interval. Separate
  binding keys preserve multiple connections belonging to one participant. Missing required
  resources remain preparing; missing adapters fail. Neither can satisfy readiness.
- Reconciliation preserves exact unchanged ready bindings and returns only the preparation/removal
  diff. New attempts and remove/re-add cycles invalidate old request references. Failed generations
  cannot be revived by delayed ready reports; monotonically ordered reports prevent an old ready
  message from erasing a later preparing report.
- Nine focused barrier tests pass after first failing for the missing barrier, missing ordered
  report field and collapsed connection bindings. The barrier is pure state; prospective inventory,
  asynchronous collection/monitoring and lifecycle use remain pending.
- Decision and local design review are recorded in `docs/readiness-resource-contract.md`, including
  rejected PID-only/global-revision approaches and the boundary between binding changes and process
  replacement. This is separate from claiming runtime milestone acceptance.

## Speech-provider readiness adapters

- STT and TTS now expose bounded initialization evidence using the common resource descriptor.
  STT remembers a provider's normalized connected signal and invalidates its generation/evidence
  when that session is closed or replaced. Unrelated policy revisions retain the exact descriptor.
  Stale callbacks from the replaced transport cannot restore readiness.
- Providers explicitly choose connection acknowledgement or validated initialization. Deepgram STT
  and TTS and local Morse STT use their connection signal; local Morse TTS is usable when initialized.
  Missing/unsupported readiness contracts fail closed. No probe utterance or tool invocation is sent.
- New focused tests first failed on missing STT/TTS readiness APIs and missing provider contracts.
  The combined barrier, speech-capability and local-provider lane passes 37 tests with zero failures.
  Provider readiness does not establish ingress/output-route readiness; these must be separate
  required bindings in the complete prospective set. Model/tools, room-service adapters, collection,
  initial waiting and coordinated transfer release are still pending. Root gate results follow.

The combined checkpoint passes all five root gates: formatting, warnings-as-errors compilation,
strict Credo, 1,067 umbrella tests with zero failures (15 integrations excluded), and unused
dependency checks. The private playback checkpoint can now be checked off: its independent player,
shared native output, clear/drain, cue, generation fencing and idle pacing boundaries are implemented
and verified. The separate initial/transfer lifecycle and rendered/provider acceptance gates remain
unchecked; the milestone and index are still incomplete.

## Core room-service readiness

- Added owning-boundary readiness for the room mixer, transcript router, Variables, live inspection
  and archive subscriber. Mixer/router require an installed policy and report only their relevant
  intervals; applying a new relevant interval preserves their initialized process generation.
  Ordinary variable updates also retain the initialized configuration and generation.
- The observation port must be open. Archive requires an open local handoff and bound producer;
  its pending remote write can remain asynchronous. Closed local handoffs report failed while
  still-running processes drain, rather than being mistaken for usable interfaces.
- Five new checks first failed on missing readiness APIs. The five owning test files now pass
  40 tests with zero failures, covering unrelated/relevant policy changes, variable privacy and
  updates, closed observation ports, and storage-independent archive readiness.
- Extended the resource contract with these boundaries. Recording writer readiness, the complete
  prospective inventory, model/tools and lifecycle orchestration remain outstanding.
- Combined room-service/collector verification passes all five root gates: formatting,
  warnings-as-errors compilation, strict Credo, 1,083 umbrella tests with zero failures
  (15 integration tests excluded), and unused-dependency checks. The collector is recorded in the
  next checkpoint; no startup/transfer barrier or browser/provider acceptance is claimed here.

## Asynchronous readiness collection

- Added a collector owned by RoomCapabilitySupervisor and a named task supervisor for bounded
  adapter observations. Its task batch keeps calls out of the room authority, limits concurrency,
  and periodically retries preparing resources. Ready instances retain their evidence on unchanged
  reconciliation; an explicit refresh rechecks evidence without restarting capabilities.
- Every result is fenced to the current batch and exact expected resource. Changed returned
  configuration/policy/generation fails the old binding and requires owner reconciliation. Monitored
  resource loss revokes readiness. Missing adapters and explicit failed reports fail closed.
- One absolute deadline applies through reconciliation. A controlled-clock regression reproduced
  a late ready result being accepted before the timer message; results and snapshot calls now check
  the clock directly. A timed-out observation also initially poisoned the resource generation;
  this now remains preparing and can recover on another bounded observation without replacement.
- Owner loss and cancellation stop outstanding batch/probe tasks while leaving the observed
  resources running. Focused checks monitor those task exits and use acknowledgement-controlled
  adapters; no sleeps or PID-liveness assertions were added.
- Eleven collector checks pass, including actual STT/mixer evidence, relevant policy changes,
  independent delayed resources, automatic polling, concurrency bounds, resource death, stale
  results, deadline races and cleanup. Together with the barrier/provider/core-room checks the
  focused lane passes 61 tests. All five root gates pass with 1,083 tests and zero failures
  (15 integrations excluded). This is collection infrastructure; RoomAuthority does not use it yet.
- Next integration evidence: MCP Connections.open already requires the exact ready protocol revision;
  IntegrationOwner completes scoped binding/lease setup before returning. The agent session validates
  its configuration and context but has no initialization query yet. Add model/tool and recording/
  media adapters, then derive the full prospective inventory and connect startup/transfer phases.

## Agent model, tool and MCP readiness

- Added neutral initialization evidence to Agent Runtime without depending on Call Engine. It pins
  installed configuration/context and a session generation, hides raw context/provider configuration,
  reports busy sessions as preparing, and retains evidence after cancellation or ordinary history
  updates. Providers opt into a local nonblocking readiness contract; missing contracts fail closed.
  ReqLLM acknowledges its resolved stateless configuration without generation or network probes.
- Coordinator readiness combines admission state with session, invocation registry, request
  supervisor and selected MCP evidence. Dependency calls run outside the coordinator receive loop.
  Tool queues expose their own resource; saturation closes readiness until completion consumption
  without replacing the registry. Composite signatures pin dependency generations, and existing
  one-for-all activation supervision propagates dependency loss to the monitored model resource.
- MCP ownership now reports only after binding validation, scoped credential leases and connection
  initialization. Production Connections.open already verifies ready protocol negotiation. A gated
  initialization fixture proves the owner cannot acknowledge early; no tool invocation is used.
  Existing client-loss/revocation checks also verify readiness disappears with the owner. Scope is
  supplied explicitly by activation graphs; legacy unscoped direct callers receive no scoped evidence.
- Red evidence: four model/session assertions failed on absent readiness APIs; the MCP lane failed
  on unsupported participant scope/missing readiness; activation collection failed on the missing
  coordinator API. Green: nine focused model/session/provider tests, eleven activation/MCP tests,
  then fifty engine activation/coordinator/invocation/collector checks passed. Root gates follow.
- Extended the resource decision document. This checkpoint does not connect RoomAuthority to the
  collector or claim lifecycle acceptance. Recording/media adapters and the prospective inventory
  remain prerequisites for initial waiting and coordinated transfer release.
- All five root gates pass: formatting, warnings-as-errors compilation, strict Credo, 1,089 umbrella
  tests with zero failures (15 integrations excluded), and unused-dependency checks. The milestone
  records this partial readiness progress and retains its unchecked lifecycle/acceptance gates.

## Recording resources and mixer subscriptions

- Added binding-specific readiness queries for processes that own multiple resources. Mixer queues
  acknowledge their exact token/generation and relevant interval without consuming audio; the
  collector can now distinguish multiple subscriptions on one mixer. The first subscription test
  failed on the missing API, then exposed an incorrect fixture assumption that mix-minus would
  deliver a source's own isolated audio. Correcting the expected recipient count preserved routing.
- Artifact writers report their initialized open local handoff, without waiting for remote storage.
  A paused storage-open fixture first failed on the missing readiness API and now proves local
  readiness before remote completion, then failure after handoff closure. Existing saturation/gap
  pipeline checks also retain ready generation/configuration with a pending remote write.
- Added explicit preparation of the complete demanded individual-track set under an installed
  recording interval. It validates membership, selected targets and permission; opens only missing
  writers; and retains existing handles/sequences through retries and relevant policy changes.
  Initial preparation/readiness checks failed on missing APIs before implementation.
- A focused partial-failure test reproduced audio lazily opening a writer after its preparation
  failed. Prepared subscriptions now reject missing or out-of-set tracks until explicit preparation
  succeeds. Successfully opened writers survive a partial failure and are reused on retry.
- Exposed the recorder's required writer/subscription descriptors for collector monitoring. The
  integration first failed on the missing inventory API. Standalone artifact tests do not start
  Call Engine (a runtime-false dependency), so this fixture explicitly supervises the collector's
  named task supervisor when absent. It verifies writer death revokes a ready barrier while the
  recorder remains available. This avoids relying only on the recorder's PID.
- Final review found that an arbitrary map returned as writer evidence could be accepted as ready
  and omitted from dependency monitoring. A regression reproduced that false readiness. The owning
  boundary now requires a bound recording-writer descriptor and rejects malformed evidence.
- Thirty-one engine mixer/recording/collector checks and nine artifact writer/pipeline checks pass.
  The resource decision document records the separate design review and rejected frame probes,
  PID-only subscription checks, first-sample preparation and synchronous remote-storage waits.
  Root gates follow. Media bindings, complete room inventory and lifecycle use remain outstanding.
- The final recording checkpoint passes all five root gates: formatting, warnings-as-errors
  compilation, strict Credo, 1,096 umbrella tests with zero failures (15 integrations excluded), and
  unused-dependency checks. A transient build lock cleared without restarting a running process.
  The milestone records the implemented recording boundary and leaves lifecycle acceptance open.

## Gateway pipelines and room-route readiness

- Resumed the three pending readiness tests and confirmed the expected red result: 26 tests,
  three failures on missing ingress/output/egress APIs. Added participant/connection-scoped
  descriptors tied to the actual current pipeline initialization acknowledgement. Replacement or
  removal changes the resource generation; unrelated policy and native output clear retain it.
- Room ingress requires its installed input interval. Room egress combines its pipeline evidence
  with the actual mixer subscription and requires matching output intervals. The query happens
  outside the egress receive loop to avoid blocking policy acknowledgement on the mixer. Separate
  subscription descriptors let the collector observe mixer loss while egress remains available.
- Added real mixer/egress/collector integration and malformed/foreign subscription checks. The
  first integration run exposed a fixture cleanup error: the mixer child ID includes its incarnation.
  Correcting that ID allowed the intended mixer-loss assertion. All 27 focused checks now pass.
- Updated the resource decision document with the local design review and limits. The shared
  output acknowledgement proves its room binding, not native codec or negotiated transport readiness.
  WebRTC connection/track evidence, STT ingress, private output bindings, full prospective inventory
  and lifecycle orchestration remain outstanding. No browser/provider acceptance is claimed.
- All five root gates pass: formatting, warnings-as-errors compilation, strict Credo, 1,100 umbrella
  tests with zero failures (15 integrations excluded), and unused-dependency checks. No running
  server was restarted. The milestone records the component evidence and keeps full acceptance open.
- Next inspected integration points: WebRTC native output currently lacks participant identity,
  and the arbiter is constructed with only its native PID. WebRTC learns input track codecs lazily
  from the first RTP packet; readiness needs negotiated track evidence before microphone release.
  Engine Media.Ingress owns the bounded STT handoff separately from room audio normalization.

## Shared output readiness and revocable room bindings

- Added explicit recipient identity and native adapter wiring for web/phone output. WebRTC native
  readiness pins its initialized encoder and configured peer/track. The arbiter validates the actual
  native descriptor outside its receive loop and rechecks its binding snapshot before reporting.
  Missing adapters fail closed; pending clear/drain prepares without changing resource lifetime.
- Initial focused tests failed on missing APIs after correcting a misplaced fixture assertion.
  The new collection check proves private output retains its descriptor through hold/release and
  room rebinding, while the exact old room token becomes unavailable. Codec initialization/readiness
  does not encode a probe packet or advance the RTP timeline. Native loss revokes collection.
- A second red check exposed missing arbiter-route evidence in the shared room path. Added the
  shared pipeline's current binding query and included that descriptor in room egress evidence.
  A live old pipeline cannot retain readiness after another caller replaces its route. Private
  output and encoder readiness remain unchanged. Egress also rechecks its snapshot after queries.
- Fifty-one focused web/phone/media checks pass, including both actual phone pipeline fixtures
  querying private/room readiness and the existing two-peer WebRTC/human-transfer regressions.
  Updated the resource contract with the local design review and remaining limits. Root gates follow.
- Next inspected transport boundary: ExWebRTC exposes bounded public connection-state and
  negotiated-transceiver queries. Query those outside Connection's receive loop; a ready configured
  encoder alone cannot prove transport connectivity or an available input track. Session snapshots
  contain identity but not candidate capability demand, so the prospective inventory must explicitly
  select required input evidence, including receive-only and private preparation cases.
- All five root gates pass: formatting, warnings-as-errors compilation, strict Credo, 1,103 umbrella
  tests with zero failures (15 integrations excluded), and unused-dependency checks. The milestone
  records the shared-output boundary and leaves negotiated transport, inventory and lifecycle
  acceptance unchecked. No running server was restarted or live provider acceptance claimed.

## Negotiated WebRTC connection and input evidence

- Added separate output/connection and input resource queries backed by actual ExWebRTC transport
  state and negotiated transceivers. Queries run outside Connection's receive loop and recheck its
  negotiation revision before accepting evidence. Output pins the configured sender track/codec;
  input requires one receiving track with a supported Opus format. No media probe is generated.
- The selected resource list requires explicit input demand, so receive-only listeners do not need
  microphone negotiation. The input-track projection supplies the same string ID/format used by
  received engine frames for later ingress and recording preparation. This does not bind those
  handoffs yet. Session identity alone cannot choose the prospective room's input demand.
- Red evidence: two real-peer checks failed on missing Connection readiness APIs; two projection
  checks failed on the absent negotiated-audio module. A separate direction regression then showed
  that changing only the opposite direction changed the signature. Signatures now use their relevant
  direction, retaining the unchanged track/codec evidence.
- One receive-only run exposed a fixture race: the client reported connected before the server's
  transport had reached connected. The fixture now awaits the collector's actual server evidence,
  instead of assuming the client event proves both sides. All seven focused checks pass, including
  collection before any RTP, stable evidence after two-way audio, receive-only negotiation,
  incompatible codecs and multiple active inputs. Root gates follow.
- Local design review and remaining limits are in the resource contract. The next input boundary
  is Engine Media.Ingress: it currently learns its track from the first accepted frame. Its eventual
  preparation/readiness must also match SpeechToText's configured media format and policy interval,
  while keeping held microphone frames discarded. Phone media and full lifecycle integration remain.
- All five root gates pass: formatting, warnings-as-errors compilation, strict Credo, 1,107 umbrella
  tests with zero failures (15 integrations excluded), and unused-dependency checks. The completed
  gate process was polled and its final zero exit verified on continuation. No server was restarted.
  Milestone evidence records this boundary without checking off common readiness or lifecycle work.

## Prepared speech input handoff

- Added explicit track preparation to Engine Media.Ingress. The external query validates the actual
  STT owner, complete connection identity and public codec/rate before committing a still-current
  ingress binding. Repeating the same preparation preserves queued work even while the provider is
  busy. Closed input continues to discard frames; preparation does not open it or start a session.
- Readiness combines prepared track/capacity, provider connection evidence and matching installed
  speech-policy intervals. The resource inventory includes the actual STT dependency. Both queries
  run outside the ingress loop and recheck the local binding. Prepared streams reject changed
  tracks/formats before provider delivery. Unrelated recording policy changes retain resources.
- Four new tests first failed on the missing APIs (10 ingress tests, four failures). All ten then
  passed; the combined ingress, STT and readiness checks pass 42 tests. One intermediate focused run
  was launched from the root; the combined focused run used the owning engine child's directory.
- Reviewed current policy/opening contracts and recorded the preparation decision and alternatives
  in the resource contract. Candidate-policy preparation, gateway normalizer track binding and
  orchestration remain unfinished. Root gates follow; no browser/provider acceptance is claimed.
- All five root gates pass: formatting, warnings-as-errors compilation, strict Credo, 1,111 umbrella
  tests with zero failures (15 integrations excluded), and unused-dependency checks. The milestone
  records component evidence and retains every unfinished orchestration/acceptance requirement.
- Next inspected boundary: WebRTC's normalizer still learns its track from first RTP. Phone
  normalizers already receive an authenticated stream ID, but Telnyx uses Opus at 16 kHz and Twilio
  uses PCMU at 8 kHz; neither may inherit WebRTC's negotiated 48 kHz input assumption. Their
  prepared input must preserve these transport formats and the common 48 kHz mono room output.

## Decoder preparation before packets

- Inspection of the installed Opus parser/decoder source found that graph-playing acknowledgements
  precede actual decoder allocation for WebRTC: the parser waits for a packet to emit a format.
  Added a preparation filter that sends the negotiated format and an ordered reference-bearing
  Membrane event through the decoder/mono conversion/frame parser to the PCM sink. Only the matching
  sink acknowledgement can mark the prepared input resource ready; no sample or probe is generated.
- Repeated preparation is idempotent and preserves queued partial frames and the pipeline generation.
  A path with an observed Opus format keeps it rather than resetting it to negotiated channel capacity;
  the dependency retains its normal packet-format handling. Different/invalid input bindings fail.
- Two new real-pipeline tests first failed on missing APIs (six tests, two failures), then all six
  passed. The collector reaches ready before PCM, wrong tracks cannot become the first accepted
  input, and two 10 ms packets still form one 20 ms frame across repeated preparation.
- This corrects the distinction between a playing graph and a prepared decoder in the resource
  contract. Common room-ingress preparation/inventory and phone evidence remain unfinished.
  Broader focused checks and root gates follow. No rendered/browser/provider acceptance is claimed.
- Twenty related checks and an initial full root pass succeeded. Review then found that an early
  preparation notification could emit a stream format before Membrane permits output. A focused
  element-boundary regression failed on those premature actions. The filter now retains one pending
  request until playing; the combined 21 focused checks pass. Root gates are repeated for this fix.
- Rechecked orchestration rather than inferring it from component tests: StartupReadiness still
  marks startup from caller/STT attachment, and HumanHandoff still cancels its timer and calls the
  committer immediately after acceptance/briefing. Neither uses the collector or wait players yet.
  These remain mandatory runtime changes under the same startup/transfer deadlines; the component
  work does not establish the requested end-to-end behavior.
- Final root gates pass after the early-preparation fix: formatting, warnings-as-errors compilation,
  strict Credo, 1,114 umbrella tests with zero failures (15 integrations excluded), and unused
  dependency checks. Milestone evidence records the prepared decoder boundary and its remaining
  integration requirements. No running server was restarted.
