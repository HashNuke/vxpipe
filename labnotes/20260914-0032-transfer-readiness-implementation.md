# Transfer readiness implementation

Current delivery tasks and curated status now live in the
[milestone checkpoints](../docs/milestones/transfer-readiness-and-wait-sounds.md#implementation-checkpoints).
The [latest phone diagnosis and delivery review](#phone-diagnosis-and-vertical-delivery-review)
records the remaining unsupported-audio failure and the documentation-first restructuring.
Earlier sections below are chronological evidence, not parallel current task lists.

The current [automatic human handoff work](#wire-normal-acceptance-through-prepared-media) connects
normal acceptance to private preparation, whole-room collection, local cues, exact policy adoption
and acknowledged release. All six WebRTC transfer checks pass, including delayed destination STT,
actor reuse and a surviving room after source teardown. This work remains uncommitted: embedded
fixture migration, phone integration, complete recovery and earlier audience holds are unfinished. The
1,274-test umbrella result below belongs to `c4fea8c`, not to this worktree or full acceptance.

The last verified [Gateway preparation checkpoint](#integrate-private-gateway-preparation) allocates
dormant private media on actual WebRTC and phone connections. Complete prospective WebRTC room
collection waits for destination STT while retaining caller pipelines and source capabilities.
Preparation without STT cannot bypass adoption; private actor loss cancels the attempt, and
unrelated policy refresh leaves an undemanded decoder stopped. All 46 engine and 46 Gateway
focused checks pass, followed by all five root gates: 1,274 tests, zero failures and 15 integration
exclusions. Automatic lifecycle invocation and successful prepared handoff remain unfinished.

The earlier [Gateway notes snapshot](#gateway-preparation-detour-and-current-boundary) retains the
initial three-test result and then-unverified work. The implementation evidence below supersedes
that snapshot without claiming end-to-end transfer acceptance.

This extends authorized private speech binding in `5ab8c17`, persistent transfer ownership in
`4801597`, private allocation in `c005511`,
speech adoption in `a8106d4`,
the complete-membership commit in `69b5ad6`,
native tap preparation in `666ca37` and writer/track adoption in `4b14530`.
The earlier [investigation](#private-stt-initialization-and-cancellation-ownership)
and pause audit retain their historical failures/worktree snapshots, not current status.

**The end-to-end milestone remains unfinished.** Prepared destination adoption, startup/transfer
orchestration, waits/cues and recovery still require integration
and acceptance. Passing this component checkpoint does not establish the requested transfer flow.
The [handoff investigation](#recording-tap-investigation-and-handoff-resume-point) identifies the
existing completion sequence that still needs to use the prepared resources.
The [phase-owner integration findings](#phase-owner-integration-findings) retain the source audit
before this checkpoint; the implementation evidence below records the changes since that audit.

## Detour update after the pause audit

The additional groundwork since the audit addresses room output, recording and policy adoption:

- `bd7b1e1` added per-listener holds and released-frame generations, and acknowledged discarded
  shared frames so a retained producer could resume. These were prerequisites for using the
  existing output through a transfer; the codec and subscription stay in place.
- The prepared-egress checkpoint stages only a missing joining route and adopts its prepared
  mixer subscription while held. Its boundary checks exposed foreign-queue gating, stale native
  route evidence, accidental activation during unrelated membership changes, an unanswered
  readiness waiter and a queue assigned to the wrong consumer. Each defect and its red/green
  evidence is recorded in [the checkpoint below](#prepare-room-egress-for-policy-adoption).
- An existing diagnostics fixture failed because unrelated rooms finished shutting down during
  page mount. Its separate fix checks for newly added registry bindings and room processes while
  allowing cleanup. Committed as `0eaa94d`; see
  [the diagnostics labnote](20260914-0942-diagnostics-registry-cleanup.md).
- `9fc4b83` connected prepared speech, decoder and output resources to the candidate connection
  query. Review exposed a decoder that was replaced after its demand disappeared; preparation now
  stages its shutdown instead. A new WebRTC fixture also needed to await server transport readiness
  rather than assume client connection completion proved it. See
  [candidate connection selection](#select-candidate-connection-resources).
- The whole-room runner assembles those connections with prepared mixer subscriptions
  and transcript routing. Its original recording-source guard is documented in
  [the prospective room checkpoint](#prepare-the-prospective-room-graph).
- The [recording checkpoint](#prepare-recording-ownership-and-policy) now stages future recording
  writers and tracks without changing live recording, retains existing sequence numbers, and adopts
  the prepared mixer subscriptions. Review caught mixer/writer loss and retained-descriptor defects;
  their red/green evidence is recorded below.
- `666ca37` completed [candidate native tap preparation](#prepare-native-recording-taps-for-a-candidate-policy).
  Physical tap/codec evidence stays stable while the prepared mixer owns future recording permission.
  Preparing the candidate leaves currently denied recording closed; adoption retains the tap.
  An existing transcript fixture's 100 ms acknowledgement failed under the umbrella load; its
  separate one-second fixture correction is `ec5d408`, with production deadlines unchanged.
- `69b5ad6` added [one complete membership commit](#commit-the-exact-prospective-membership).
  Separate destination admission and source departure would produce policy revisions different
  from the snapshot prepared for transfer. The new operation commits that exact snapshot within
  the original deadline. The human handoff still needs to call it and coordinate control state.
- The [private STT checkpoint](#adopt-private-speech-through-the-policy-barrier) now avoids the
  preliminary provider connection, keeps the pair outside critical registration until commit,
  and proves explicit cancellation preserves source audio. It also corrects repeated enforcement
  of an unchanged membership candidate. Authorized connection binding and persistent phase cleanup
  were still required at that checkpoint; the later commits below address them.
- The [allocation lifetime checkpoint](#bind-private-allocation-to-its-phase) closes the interval
  before provider preparation starts and prevents unprepared/no-demand adoption. It reuses the
  temporary actor lifecycle and existing ingress monitor. An unrelated membership refresh already
  retained the private provider through existing policy reconciliation; the added check confirms
  that behavior without changing it. Connection binding followed in `5ab8c17`; full coordinator
  wiring remains unfinished.
- `4801597` retained the existing supervised transfer task through handoff. Previously its exit
  after destination configuration would prematurely cancel resources leased to it. Completion now
  checks that phase before publishing success; this does not implement readiness, cues or release.
  See [phase ownership](#retain-the-actual-transfer-phase).
- `5ab8c17` bound private speech to the exact authorized connection with closed input. Review found
  three related integration defects: direct commit could bypass prepared adoption, startup could
  open private input, and cancellation removed only one private connection. Their reproductions
  and fixes are recorded in [the binding checkpoint](#bind-private-speech-to-the-authorized-connection).
- The [Gateway checkpoint](#integrate-private-gateway-preparation) addresses the next boundary:
  ordinary media setup assumes room admission, so it cannot prepare a private joining participant.
  The notes snapshot records the initial rationale; the implementation section records the
  completion-guard, actor-loss and policy-refresh defects found during integration and verification.

No dependency versions or production deadlines changed in these committed checkpoints. These are
component results: complete resource selection, startup/transfer orchestration, waits/cues,
restoration and rendered/provider acceptance remain unfinished.

## Status and detour audit at the user-requested pause

On 2026-09-14 the user asked why implementation was still running after approximately eight
hours, then requested an accounting of dependency work and detours in this labnote. Implementation
is paused. This audit documents existing work; it does not resume the milestone.

**The requested end-to-end transfer/wait flow is unfinished.** The milestone has completed its
definition/assets and private playback component checkpoints. Common readiness is partial;
initial caller waiting, coordinated transfers, recovery and sample/browser/provider acceptance
remain open. The `transfer_receiver` to `transfer_joining` rename was already committed separately
as `6dd801f` at 00:31. Subsequent work implements the broader authorized milestone.

### What the eight hours produced

The implementation labnote began at 00:32; the latest implementation commit, `b079dbf`, is dated
08:44, approximately eight hours and twelve minutes later. These are local commit/note timestamps
(UTC+07:00), not measurements of time spent coding or testing. The range `6dd801f..b079dbf` contains
31 commits and changes 230 files, with 17,205 insertions and 330 deletions across implementation,
tests, documentation and assets. Those totals describe scope, not completed acceptance criteria.
There is no reliable per-activity timing record, so this audit does not assign invented durations
to the detours or test runs.

| Commit times | Work completed | Checkpoints |
| --- | --- | --- |
| 00:46–01:07 | Call-level URL/default/null semantics, pinned assets, independent private players, and clearing queued output while retaining codecs. | `66b6033`, `b9ddac9`, `f8bd969` |
| 01:22–01:51 | Shared native output for private/room audio, phone playback marks, final cue drain and pacing after idle. One separate fixture-timeout adjustment. | `0e8efc6`, `b2bb177`, `840090e`, `1e36913` |
| 02:06–03:42 | Readiness descriptors and bounded collection; STT/TTS, model/tools/MCP, room services, recording writers, media pipelines and exact output-route evidence. | `c0bd41f`, `13ebd83`, `52e3047`, `d3d6532`, `2e02e6a`, `59712bd`, `7f434b5` |
| 04:04–04:49 | Negotiated web input, prepared speech tracks and decoders before microphone packets, native phone formats and validated phone streams. One separate catalog fixture adjustment. | `71d3a06`, `245e59e`, `c776097`, `0bc649e`, `bbba94e`, `cde2f91` |
| 04:58–06:51 | Prospective membership preview, connection graphs, complete room requirements and resource expansion, agent recording taps, and cancellation of nested preparation workers. | `b02a2d2`, `1a2646c`, `a4730fb`, `be0267f`, `aa9993f`, `3f86d4a` |
| 07:25–08:44 | Prepare affected STT sessions, bind their input, prepare replacement decoders, reserve shared output routes and stage mixer subscriptions before policy application. | `fb567d0`, `e9284ea`, `43aafa2`, `004f4ef`, `b079dbf` |

The implementation proceeded from each component into the next missing prerequisite. Focused
checks and all five umbrella gates were run for the committed checkpoints; some checkpoints
repeated their gates after an additional defect was found. This added verification work, but the
central sequencing problem was continuing to expand infrastructure before demonstrating a runnable
startup/transfer slice. Passing component checks did not establish the requested user experience.
I should have surfaced that gap and the expanding scope much earlier. The evidence below explains
the path taken; it does not establish that doing all this groundwork serially was the best order.

### Dependency and integration detours

No dependency lockfile or package version changed in this commit range. The Agent Runtime
application added the existing OTP `:crypto` application for its new signatures. The dependency
work otherwise concerns project-owned integration with installed libraries and provider protocols.
The earlier checkpoint sections retain the detailed red/green evidence; this index explains why
each material detour was taken and where it ended.

| Finding and its consequence | Resolution or remaining limit | Evidence |
| --- | --- | --- |
| Bundled ChucK WAV files had RIFF lengths including the eight-byte header; strict decoding rejected the intended defaults. Existing opening fixtures also had caches too small for those loops. | Corrected the engine asset headers without changing samples; kept remote decoding strict. Enlarged only fixture caches. Added legacy-plan hydration so old serialized plans receive omitted defaults. | `66b6033`; [definition/assets](#definition-and-asset-checkpoint). |
| Private audio entered native recording taps, and direct/room paths used separate encoders. Existing phone interruption replaced its pipeline. | Added private/mixed audio scopes, a shared output arbiter and ordered clear while preserving native codecs and their timelines. These primitives still need lifecycle use. | `b9ddac9`, `f8bd969`, `0e8efc6`; [playback](#playback-primitive-checkpoint), [native clear](#ordered-native-output-clear-checkpoint), [shared output](#shared-recipient-output-checkpoint). |
| Socket submission did not prove phone playout; provider clear also returns pending marks. A socket waiting synchronously on a leg could prevent that leg from receiving the playback acknowledgement it needed. | Correlate fresh marks after clear, drain the final cue, and dispatch leg events asynchronously with bounds. Stale marks cannot acknowledge new work. Deterministic checks pass; audible live-provider acceptance is outstanding. | `840090e`; [phone playback](#phone-playback-marks-and-finite-cue-drain). |
| The installed Membrane.Realtimer emits overdue timestamps immediately. A retained output timeline excludes idle gaps, so resumed audio could burst to catch up. | Added a local paced-frame boundary that accounts for idle and encoding delay while retaining codec/timeline state. | `1e36913`; [idle pacing](#phone-pacing-across-idle-gaps), including the controlled-clock 20-second idle case. |
| Process existence and a global policy revision cannot establish readiness of a particular provider, queue, subscription or tool dependency. | Added exact configuration/generation/interval descriptors and bounded external collection across selected capabilities. Missing dependencies keep readiness closed. This is substantial planned groundwork, with lifecycle integration still open. | `c0bd41f` through `7f434b5`; [barrier](#required-resource-barrier), [collection](#asynchronous-readiness-collection), and intervening adapter checkpoints. |
| Recording writers opened on first audio; a failed preparation could be bypassed by lazy opening. Aggregate evidence could accept malformed or foreign dependencies. Agent tracks also lacked their exact native output tap. | Prepare required local writers from validated actual tracks/taps, retain successful writers, reject missing/foreign evidence and incompatible PCM formats. Remote storage completion remains outside the local readiness barrier. Candidate-policy recording preparation remains open. | `2e02e6a`, `be0267f`, `3f86d4a`; [recording](#recording-resources-and-mixer-subscriptions), [agent taps](#prepare-agent-recording-output-paths). |
| WebRTC transport readiness needed server-side negotiated directions. A playing Membrane graph could still have no allocated decoder because Opus parsing waited for its first packet. Early preparation could also emit a format before Membrane allowed output. | Query actual transport/track evidence; send negotiated format plus an ordered preparation event through the real decoder to its sink, deferring output until playing. No microphone probe is required. | `71d3a06`, `c776097`; [negotiation](#negotiated-webrtc-connection-and-input-evidence), [decoder preparation](#decoder-preparation-before-packets). |
| Common ingress held a Membrane supervisor PID rather than the pipeline actor; native phone formats differed from WebRTC. Reflection could label a configured but unloaded adapter unsupported. | Query the registered pipeline, pin actual web/phone formats, and load the configured module before checking callbacks. Cold-process and actual pipeline checks pass. The phone graph fixtures do not establish phone STT parity. | `0bc649e`, `1a2646c`; [common input](#common-prepared-input-and-phone-formats), [connection graphs](#bound-connection-resource-graphs). |
| Existing admission/leave calls apply policy immediately; using them to discover future readiness would change permissions too early. A partial caller-supplied inventory could omit required actors. | Added authoritative read-only membership previews and reconstructed full room/connection requirements. Discovered and reused the existing per-participant TTS registry instead of creating another owner. Full candidate installation and orchestration remain open. | `b02a2d2`, `a4730fb`, `be0267f`; [prospective membership](#prospective-membership-policy), [inventory](#prospective-requirements-and-authoritative-room-bindings), [expansion](#expand-room-requirements-for-collection). |
| Cancelling room preparation left nested blocked queries running because their task-stream ownership did not propagate cancellation. | Changed both preparation levels to supervised linked streams. Tests monitor the actual blocked workers and prove the owning media actors remain usable. Increasing timeouts was rejected for this defect. | `aa9993f`; [dedicated cancellation labnote](20260914-0641-readiness-worker-cancellation.md). |
| Affected STT still connected during policy application. Prepared session evidence disappeared at adoption; pending events could replay, and unrelated membership refreshes could create another replacement. | Prepare affected sessions under the existing owner/attempt/deadline, retain the live session, preserve adopted evidence and advance only pending sequence cutoffs. Unchanged pending transports survive authoritative refresh. Input can select the same exact prepared session. | `fb567d0`, `e9284ea`; [speech policy](#prepare-affected-speech-policy), [prepared input](#bind-prepared-speech-input). |
| Decoder replacement still happened during commit. Stopping a forbidden decoder could return a fatal connection error; unchanged permissions could mask removal of all actual demand. | Stage and acknowledge affected decoders before adoption, drop denied input normally, and compare demand as well as scoped policy. WebRTC/Telnyx/Twilio decoder checks pass. Full connection selection of these preparations remains open. | `43aafa2`; [decoder policy](#prepare-input-decoder-policy). |
| Constructing a shared output route revoked its live predecessor before collection. | Added a separate pending route tied to the held generation and original deadline; activation requires exact ready evidence and drained private playback. Native output survives. Gateway room-egress integration remains open. | `004f4ef`; [shared output preparation](#prepare-shared-output-routes). |
| New mixer subscribers could receive buffered pre-commit speech, collide with reserved IDs, lose an adopted handle on the next attempt, or remain required after leaving the prospective audience. | Stage missing subscriptions separately, fence new subscribers with source cutoffs, reserve IDs, retain per-subscription adopted bindings and reconcile the explicit complete desired set. Existing listeners retain queues and identities. | `b079dbf`; [mixer preparation](#prepare-mixer-policy-and-subscriptions). |
| A held/released room output expects a new generation, but mixer frames still use zero. Clearing an in-flight shared frame can also leave its producer waiting forever. | Investigation paused with two red tests and no runtime fix. Subscription-local gates and discarded-frame acknowledgements are proposed, not implemented. | [paused hold/release work](#hold-and-release-room-output). |

### Verification and fixture detours

- Two policy fixtures had 100 ms acknowledgement deadlines that failed under umbrella scheduling
  load. Increased those fixture deadlines to one second without changing production deadlines or
  assertions. See `b2bb177` and the [policy-timeout labnote](20260914-0136-media-policy-test-timeouts.md).
- The MCP catalog timeout fixture could expire before its blocked worker announced startup.
  Increased only its refresh/wait headroom, retaining the timeout behavior under test. See
  `bbba94e` and the [catalog-timeout labnote](20260914-0443-stabilize-catalog-timeout.md).
- Updated simulated phone sockets to acknowledge the new clear/mark protocol and transfer fixtures
  to await asynchronous start-event completion. WebRTC fixtures now wait for actual server evidence
  and explicitly supply delayed STT/TTS Connected acknowledgements. These were fixture assumptions
  exposed by stricter evidence, not a reason to bypass readiness in production.
- New-fixture corrections included child IDs/required registries, actor versus supervisor handles,
  missing identity/PCM format/deadline settings, valid policy/provider event shapes, callback arities,
  and a context-versus-plan update. They are recorded at the owning checkpoints. Also corrected the
  mix-minus self-audio expectation and used the earlier valid rejection boundary in a policy race.
  These corrections do not count as fixed production defects. Two helper names conflicted with
  `Kernel.binding/1`; renamed them. Formatting sometimes required another owning-child pass.
- An existing transcript suppression path made one synthetic replay test pass without proving the
  STT boundary; a valid turn-start replay reproduced the actual defect before the fix. The first
  paused output-clear fixture blocked on its own manual pacing clock; advancing the actual tick
  changed the failure to the intended missing producer acknowledgement. The original fixture
  failures are not claimed as evidence for those production defects.
- A transient build lock cleared without restarting a process. An expected Gateway fault-test run
  emitted a logger-handler removal; its completed command and suite results still passed. Neither
  incident required a dependency upgrade. Root reruns followed runtime fixes and fixture corrections;
  detailed checkpoint results above/below distinguish intermediate runs from final verification.

### Exact state and unfinished work

- Latest committed implementation: `b079dbf`. Its final five root gates passed, including 1,210
  tests with zero failures and 15 integration exclusions. The child counts in the retained final
  test log sum to that result. This documents the last verified commit, not the paused worktree.
- At pause, the only uncommitted code changes were one new test in `room_mixer_test.exs` and one
  in `output_arbiter_test.exs`. Both focused runs failed for the expected missing behavior; neither
  fix was implemented. The labnote was also modified. This documentation audit leaves those tests
  untouched and does not include them in its documentation commit.
- Startup still determines readiness from the existing caller/STT path. Human handoff still cancels
  its timer and calls its existing committer after acceptance/briefing. The complete resource
  collector, participant wait players, ordered cues and release acknowledgements are not composed
  into those lifecycle paths. Do not present component readiness as a working transfer feature.
- Remaining integration includes room-egress adoption of its prepared mixer/output pair; affected
  transcript/recording policy preparation; complete graph selection with persistent phase ownership;
  private destination preparation; early caller output and opening-message ordering; all-listener
  holds, waits, cues and acknowledged release; bounded restoration and safe phase/blocker telemetry.
  These must preserve the existing attempt deadline and unaffected capabilities.
- Complete desktop/mobile sample verification, multi-participant/race coverage, and web/phone plus
  phone/phone acceptance remain outstanding. Decoder checks alone do not prove phone STT support;
  the Twilio PCMU versus configured STT-format question still needs explicit resolution. No rendered
  browser check, live provider call or development-server restart was performed in this run.
- The milestone and its implementation-order index entry remain unchecked. Their acceptance gates
  are the completion criterion. The latest documentation request authorizes this accounting only;
  implementation remains paused.

Audit verification: cross-checked the timeline against all 31 commits in the stated range, checked
all 26 local links/section anchors in this audit, reviewed the paused diffs and retained test
results, and ran `git diff --check`. No new tests or runtime changes were made for this audit.

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

## Common prepared input and phone formats

- Phone packet sources now follow their startup format with a correlated preparation event.
  Telnyx/Twilio readiness and the existing pipeline-ready notification wait for the PCM sink's
  acknowledgement. Their authenticated stream and native format stay pinned; repeated preparation
  is validation only. Two new checks first failed on missing APIs, then all six phone checks passed.
- Common RoomAudioIngress now prepares/observes the selected pipeline outside its receive loop,
  then rechecks its exact binding. Inspection showed that its stored PID belongs to the Membrane
  supervisor, not the pipeline actor, so queries use the registered pipeline ID. The composite
  descriptor includes the decoder generation; the inventory exposes both resources for monitoring.
- A revised delayed-decoder test and four new common-ingress checks first produced five failures:
  graph-playing was wrongly treated as ready, preparation APIs were absent, and missing adapters
  were accepted. All 16 focused common/phone checks now pass. Actual WebRTC, Telnyx and Twilio
  pipelines collect readiness without input packets, retain descriptors across unrelated policy,
  and validate their different negotiated/authenticated formats.
- Missing adapters fail explicitly. A replacement invalidates the actual decoder dependency;
  old callbacks cannot restore readiness. Updated the resource contract with these decisions and
  the remaining phone transport, prospective inventory and lifecycle requirements. Root gates follow.
- All five root gates pass: formatting, warnings-as-errors compilation, strict Credo, 1,120 umbrella
  tests with zero failures (15 integrations excluded), and unused-dependency checks. The milestone
  records this common prepared-input boundary without claiming complete connection/lifecycle readiness.
- Next inspected transport boundary: phone MediaSocket receives and validates media-start events and
  dispatches them asynchronously to the exact leg. MediaSession currently has no readiness descriptor.
  A socket query must attest the exact accepted stream/binding, rather than treating its PID or the
  configured decoder as proof of a live transport; preserve the asynchronous socket dispatch contract.

## Phone socket and connection evidence

- Added a bounded socket query that reports preparing before a validated stream start and pins the
  exact socket, stream, provider format and binding afterward. It remains responsive with the leg
  dispatcher suspended. Replies use a process alias so a timeout does not accumulate late messages.
  No output command or input probe is emitted. Two new socket tests first failed on the missing API;
  all 15 socket checks passed after implementation. An initial local `binding/1` call conflicted with
  Kernel.binding/1; the query is named `snapshot/1` instead.
- MediaSession now observes and validates the socket outside its receive loop, rechecks its binding,
  and supplies connection/input resources plus the actual socket dependency. Complete identity,
  provider, stream and actor must match. Its normalized input projection is available only while
  that evidence is ready. Input demand is explicit and does not grant microphone permission.
- Both deterministic media-session regressions failed on absent resource APIs, then the combined
  18 socket/session checks passed: collection before audio, stable evidence after delivery, and
  failed readiness/unavailable input on a changed stream. The fixtures model socket evidence;
  actual callback validation is covered separately. No live-provider acceptance is implied.
- Added the input format to the socket configuration digest and updated the decision document.
  Root gates follow. Prospective inventory and startup/transfer orchestration remain unfinished.
- The first root run passed the phone checks but failed an existing MCP refresher fixture waiting
  for its worker-start notification. Its 100 ms deadline lacked scheduler headroom under umbrella
  load. The separate catalog-timeout labnote records the test-only adjustment; full gates repeat.
- All five final root gates pass: formatting, warnings-as-errors compilation, strict Credo, 1,122
  umbrella tests with zero failures (15 integrations excluded), and unused-dependency checks.
  The socket/session checkpoint closes the component transport-evidence gap; prospective inventory,
  candidate-policy preparation and startup/transfer orchestration remain unfinished.

## Prospective membership policy

- Inspection found that policy authority admission/leave immediately applies enforcers; using those
  calls to discover a transfer's final policy would prematurely change permissions and resources.
  Added a read-only exact-membership preview that recomposes pinned policies and scoped intervals.
  It excludes the departing source's contribution without removing the live source or starting the
  incoming participant. Unchanged target membership retains the exact installed snapshot.
- Candidates pin the actual authority and base snapshot. Validation recomputes the expected result;
  foreign/altered candidates and stale live-policy bases cannot pass. This does not authorize a
  transfer or replace its attempt/deadline and resource checks. No enforcer is called by preview.
- Five new authority checks first failed on the missing API (14 tests, five failures), then all 14
  passed. Coverage includes four retained listeners plus the incoming participant, host restrictions,
  unchanged output intervals, invalid membership, stale/foreign candidates and exact agreement with
  the corresponding live transition. Refactored live transitions to share candidate composition only
  after those checks were green; broader focused and root verification follow.
- The resource-contract document records this boundary and rejected alternatives. Actual prospective
  resource enumeration, gated enforcer preparation and lifecycle integration remain unfinished.
- All 45 focused policy/readiness checks and all five root gates pass after the shared-composition
  refactor: formatting, warnings-as-errors compilation, strict Credo, 1,127 umbrella tests with zero
  failures (15 integrations excluded), and unused-dependency checks. No browser or live-provider
  acceptance is claimed, and the common-readiness/lifecycle milestone requirements remain unchecked.

## Bound connection resource graphs

- Component transport queries did not enumerate the actual decoder, STT ingress, private/native
  output or room routes. Added an engine-owned connection protocol: a bounded supervised worker
  reads the exact attachment binding, invokes the Gateway adapter outside the connection callback,
  validates resource scopes/keys and rechecks the unchanged connection. Preparation does not start
  capabilities or open gates. Callers can cap the five-second query bound to the remaining deadline.
- Six engine protocol checks first failed on the absent API, then passed. They cover exact identity,
  retained evidence, malformed demand, unsupported adapters, foreign resources, binding replacement
  during preparation and cancellation of a worker that never returns. An initial local `binding/1`
  helper hit Kernel.binding/1's import conflict; it is now `read_binding/1`.
- The common Gateway adapter explicitly selects room input/output and speech input, always includes
  private/native output and transport dependencies, and prepares existing demanded input tracks.
  It validates admitted directions and required policy intervals before and after preparation.
  Receive-only demand cannot enable microphone processing. Full prospective resource enumeration
  and attempt-bound private destination preparation remain unfinished.
- WebRTC graph regressions failed without the connection callback and then passed. Phone fixtures
  initially supplied their connection supervisor rather than the attached MediaSession actor. After
  correcting that handle, withheld the new callback and confirmed both phone cases fail at the
  missing protocol boundary; restoring it made their complete graphs pass before audio.
- Broader WebRTC transfer coverage initially remained preparing because the STT fixture had never
  supplied a Connected message. It now explicitly checks that blocker, delivers the provider
  acknowledgement and verifies readiness followed by audio/transcripts. All eight gateway checks
  pass, including native WebRTC/Telnyx/Twilio media; phone fixtures do not select STT here.
- Added a prospective-policy mismatch check to the real WebRTC graph, which must preserve the
  installed graph while rejecting an unprepared input interval. Focused/root verification follows.
  Documented the ownership, bounded query and remaining full-inventory/lifecycle work; no browser
  or live-provider acceptance is claimed.
- The first complete pass succeeded with 37 focused engine checks, 31 gateway checks and all five
  root gates (1,133 umbrella tests, zero failures, 15 excluded integrations). The initial root format
  check flagged two multiline keyword-call layouts; formatting in their owning children resolved it.
- Recording preparation inspection confirmed that individual writers need the exact prepared track
  ID. Added `prepare_graph` and a typed `PreparedConnection` result to carry identity/generation,
  optional input metadata and resources from one fenced observation; `prepare` remains its list
  projection. Two focused contracts failed first: the graph API was absent and demanded input could
  omit its track. The expanded 39 engine checks pass. WebRTC and both phone fixtures now check the
  returned native track metadata against their actual negotiated/authenticated track; final gateway
  and root gates follow after this addition.
- That broader run exposed a cold-loading bug in common room-ingress readiness: reflection treated
  a configured but not-yet-loaded pipeline adapter as unsupported. The existing focused ingress
  contract reproduced the failure alone in a fresh test process (one test, one failure). Loading the
  selected module before checking its readiness/preparation callbacks makes that isolated contract
  pass; truly missing callbacks still fail closed. This fix belongs to the graph's required input
  boundary. Final combined and root checks repeat for the track result and cold-loading correction.
- Final verification passes: 39 focused engine tests, 31 gateway tests and all five root gates
  (formatting, warnings-as-errors compilation, strict Credo, 1,135 umbrella tests with zero failures
  and 15 integrations excluded, unused-dependency checks). This is the complete demanded graph for
  one attached connection, with track metadata available to recording preparation. The full
  prospective room inventory, actual candidate-resource installation and startup/transfer waiting,
  cues and release orchestration remain unfinished. The running development server was not restarted.

## Prospective requirements and authoritative room bindings

- The rename-only response was a no-progress goal turn. Revalidated the clean worktree and resumed
  the inventory gap without changing the full milestone objective.
- Seven selection contracts first failed at the absent inventory API. The implementation derives
  requirements from the prospective membership and pinned capability choices, including all five
  resulting listeners, every authorized sink, a receive-only monitor and a private destination
  bound to its attempt. Departing/unused participants are excluded while the live source can remain
  available for recovery. Missing humans and missing selected agent actors never shrink the set.
- Audio normalization is demanded for permitted routes or enabled/selected recording tracks;
  recording permission alone is insufficient. Speech demand additionally requires a selected STT
  capability and a microphone-capable connection. Agent model readiness retains its tool/MCP
  dependency contract; TTS is required when selected and its output is demanded.
- The first green iteration caught a test helper mistake: `put_in(context.plan...)` returns the
  updated context, not the plan. Bound the plan first and corrected that fixture. This was not a
  production defect.
- Two real-room capture contracts failed at the absent API, then passed. RoomAuthority exposes a
  small binding projection without dependency calls; bounded candidate validation and inventory
  construction happen outside its loop. Planned room recorders now have an incarnation-scoped
  registry entry. Standalone fixtures keep their previous unnamed startup unless explicitly named.
- A third red contract showed that validating only the source binding allowed a caller to shorten
  the derived inventory. Validation now reconstructs the complete projection and rejects changes.
  Recorder termination invalidates the old capture, while the next capture keeps recording required
  with an explicit missing instance. Suspending policy validation leaves room binding reads usable,
  and the capture respects its bounded timeout.
- A recording-target contract first rejected valid pinned participant IDs. Added their supported
  form and validation for empty, duplicate, unknown and incompatible target selections, matching
  the recorder's supported full-mix/individual-track shapes.
- Focused verification passes: 51 inventory, policy-authority, collector, recording and connection
  checks. All five root gates pass: formatting, warnings-as-errors compilation, strict Credo,
  1,148 umbrella tests with zero failures and 15 integrations excluded, and unused-dependency checks.
- Design review is recorded in `docs/readiness-resource-contract.md`. This is requirements plus
  authoritative roots, not complete prepared-resource collection or transfer authorization. Next:
  expand every selected connection graph and required participant/room adapter, prepare recording
  writers using exact tracks, then connect candidate preparation and the readiness collector to the
  startup/transfer lifecycle. Existing state still has one active TTS handle plus pending transfer
  preparation; any additional required actor correctly appears missing until its lifecycle owns it.
  No development-server restart, rendered-browser check or live-provider acceptance was performed.

## Expand room requirements for collection

- The prior goal turn committed the authoritative inventory and passed all gates, so it was
  progress. Revalidated the clean worktree and continued with actual resource expansion.
- Three new preparation checks failed at the missing API after correcting an attachment fixture's
  required deadline. The supervised operation now expands every selected connection, queries
  required room/participant adapters, prepares individual human recording writers and returns the
  exact descriptor set for collection. Missing or failed requirements cannot yield a partial set.
- Preparation uses at most eight concurrent observations, a bounded total budget, the captured
  attempt deadline when present, and a 256-resource limit. Repeated preparation preserves actual
  resource descriptors. A blocked connection observation is terminated on expiry while its owning
  actor remains usable; a monitored worker proves cleanup without a sleep/liveness assertion.
- Five-participant expansion and uninstalled-policy rejection pass. A race check initially expected
  only final stale-candidate rejection, but a concurrent room-mixer observation correctly rejected
  its changed interval first. The check now accepts either valid rejection boundary and still
  requires that no prepared result be returned.
- A real-room check exposed that the previous binding capture missed a supervised TTS actor outside
  the room's active/pending handles. The capability supervisor already registered TTS per incarnation
  and participant. Exposed its lookup and changed capture to use it; the same real TTS instance now
  appears on repeated reads. This resolves the prior checkpoint's assumption about unavailable
  non-active TTS handles without adding a second ownership registry or starting another actor.
- Full two-human WebRTC preparation/collection passes before any audio and retains all 22
  descriptors afterward. Extending the existing agent fixture first exposed a missing readiness
  callback in its selective model test provider; it now reports only after its validated constructor
  returns. The next failure correctly remained preparing for TTS because the fixture had not sent
  Connected. It now asserts that exact blocker, delivers the acknowledgement, verifies readiness,
  then continues its existing transfer/audio/transcription behavior.
- A red foreign-dependency check demonstrated that a recording adapter's foreign participant scope
  could enter the aggregate set. The aggregate now requires bound descriptors with valid scopes and
  configuration signatures, in addition to exact primary-owner checks and candidate intervals.
- Recording writer fixtures expose their own readiness binding so the collector can observe local
  writer status independently of the composite recorder. A delayed writer holds the barrier closed
  and becomes ready without changing resource generations; a failed writer stops preparation.
- Inspection confirmed the remaining agent-recording gap: normalized agent audio uses the native
  receiving connection's `agent-egress` track. Individual agent recordings fail explicitly with
  `output_track_unavailable` until the exact output recording tap is exposed/validated. Full-mix and
  prepared human input writers work; no guessed or omitted agent writer is accepted. The next
  recording step must cover that actual tap through WebRTC and common phone output.
- Focused results: 52 engine checks and five WebRTC checks pass. All five root gates pass:
  formatting, warnings-as-errors compilation, strict Credo, 1,157 tests with zero failures and
  15 integrations excluded, and unused dependencies. The initial formatting check required a
  second owning-child formatting pass for a multiline call.
- This remains partial common readiness. Candidate enforcer preparation, initial asynchronous setup,
  private destination prewarming, audience holds/waits, cues, release acknowledgements, restoration
  and rendered/provider acceptance remain necessary. No running server was restarted.

## Prepare agent recording output paths

- The preceding rename-only turn verified existing state and made no implementation progress.
  Revalidated the clean tree and resumed the actual native recording-output gap.
- Initial checks failed at missing native/mixer binding APIs and full room preparation returned
  `output_track_unavailable` for the selected agent. Corrected the mixer fixture's helper name
  before confirming the intended failures.
- Native WebRTC and common phone outputs now expose their existing recording handoff and codec
  descriptor. The engine validates the actual mixer-issued token/configuration, room identity,
  receiving connection and installed recording interval outside the native callback. It rechecks
  the native descriptor/handoff after dependency observation, preserving codec generations.
- Required output taps enter the full-mix and individual recording resource graph. Individual
  agent writers use the source agent ID plus the receiving connection and tap-reported track ID.
  Selected human writers continue to use negotiated input tracks. Missing output paths remain an
  explicit failure; no track is guessed, no audio cursor advances, and no codec is restarted.
- WebRTC room preparation opens caller and agent writers before speech and includes them in its
  existing delayed-TTS barrier. Common phone output prepares its agent writer while the codec is
  still preparing, then collects ready with the same generation after codec acknowledgement.
  The standalone mixer/phone fixtures initially lacked required format and call-identity settings;
  supplied the same explicit options as production before checking the readiness behavior.
- Binding checks cover missing/foreign connection and room evidence, another mixer with the same
  room identity, stale policy, handoff replacement during observation and collector invalidation.
  Existing accepted-egress coverage now queries readiness before/after audio and verifies that the
  first recording timestamp remains unchanged. Unrelated transcript revisions retain the descriptor.
- Broader checks reproduced an independent nested-worker cancellation leak. The focused fix and
  its red/green evidence are recorded in `20260914-0641-readiness-worker-cancellation.md` and committed
  separately. Request cancellation now owns blocked queries throughout the nested preparation path.
- Final review exposed that an issued tap could still have a mixer sample rate or frame size that
  rejects the native output's PCM. Separate sample-rate and frame-size checks reproduced both
  failures. Native recording bindings now report their PCM format and preparation requires an
  exact match with the mixer's declared format, including the number of samples per frame.
- Final focused results: 71 engine checks and 26 Gateway checks pass. All five root gates pass:
  formatting, warnings-as-errors compilation, strict Credo, 1,168 tests with zero failures and
  15 integrations excluded, and unused dependencies. The root run emitted a logger-handler removal
  during the Gateway fault-test output; the command and all test suites completed successfully.
- Design review is recorded in `docs/readiness-resource-contract.md`. This closes the selected
  agent recording-output preparation gap under installed policy. Candidate enforcer preparation,
  attempt-bound private destination prewarming, asynchronous startup, audience waits/cues, final
  release acknowledgements, restoration and rendered/provider acceptance remain necessary.
  No development server was restarted and no live/provider or rendered-browser check was performed.

## Prepare affected speech policy

- The previous goal turn committed recording-output readiness and nested query cancellation, with
  all gates passing. Revalidated the clean tree and moved into candidate-policy preparation.
- Inspection confirmed that existing policy application retains unchanged STT sessions, but an
  affected session still starts its replacement during application. The next checkpoint prepares
  that replacement asynchronously while retaining the installed session, then adopts only its
  ready instance when the matching policy commits. Other enforcers and lifecycle orchestration
  remain part of the full milestone; this does not narrow the goal to STT.
- Added room-level red checks for prewarming and discard. Corrected the authored policy fixture
  to omit inherited routes rather than use the internal unrestricted marker. The first commit
  check then correctly rejected a malformed synthetic final transcript; its fixture needed the
  provider's required trigger field. Valid pending transcripts remain private before commit.
- Positive room checks now exercise unchanged retention, deferred denial, replacement adoption,
  exact discard, owner loss, deadline expiry, provider failure and a blocked provider constructor.
  Validation against a second authority with identical policy requires a standalone authority
  fixture with its significant-child flag adapted to the test supervisor. Final checks follow.
- The corrected foreign-authority check reproduced acceptance of another authority's candidate
  with an identical base snapshot. Preparation now verifies the capability's incarnation authority
  in addition to validating the candidate and exact installed base.
- A red adoption check showed that the prepared resource stopped being queryable once its session
  became active. The adopted lease token now resolves to the same generation/configuration/interval;
  stale cleanup rejects that token and cannot close the live session.
- A synthetic final-transcript replay was already suppressed by the room's turn handling, so it did
  not prove the capability boundary. Repeating a valid turn-start event after adoption reproduced
  an unadmitted transcript. Pending events now advance only the provider sequence boundary and stay
  out of the room; old sequences remain rejected after commit. Connected/failure observations use
  existing usage and safe provider-failure reporting.
- Review then reproduced unnecessary replacement startup after an unrelated participant joined.
  Exposed the existing scoped policy comparison and retained pending sessions across irrelevant
  installed revisions. A stale candidate cannot claim readiness; refreshing it under the same
  owner/attempt/deadline retains the ready transport and generation, updating only its candidate
  policy binding. The revised room test commits and sends audio through that retained transport.
- Seventy-five focused speech, authority, interval, inventory and collector checks pass. The first
  full gate run passed 1,177 tests before the additional pending-retention contract; final gates
  for the complete checkpoint are recorded after execution below.
- Final root verification passes all five required gates: formatting, warnings-as-errors
  compilation, strict Credo, 1,178 tests with zero failures and 15 integrations excluded, and
  unused dependencies. The milestone/index remain incomplete. No running server was restarted.
- Design review and contract are recorded in `docs/readiness-resource-contract.md` and linked from
  `docs/incremental-media-policy.md`. Remaining work includes candidate preparation for the other
  enforcers, selecting prepared bindings in the full connection/room graph, private destination
  prewarming, initial asynchronous setup, participant waits/cues, fenced release and restoration,
  and rendered/phone-provider acceptance. These checks do not prove that larger runtime sequence.

## Bind prepared speech input

- The previous goal turn committed candidate STT preparation as `fb567d0`; this turn starts from
  a clean worktree. Inspection found that input readiness still queries only the installed session,
  so it cannot collect the prepared provider together with its actual input buffer and track.
- Extend the existing input protocol to select an exact prepared STT resource. Validate the negotiated
  format and installed input interval against that session's existing policy lease; retain the input
  buffer generation and all current microphone permissions. The STT owner/deadline remains the single
  lease owner. Room tests will collect both resources before and after real participant admission,
  and invalidate the input binding when that provider preparation is discarded.
- The two extended room checks failed at the missing three-argument track preparation API. The
  implementation now validates the selected provider descriptor and exposes a binding that the
  collector can observe both before and after policy adoption. Ordinary current-session callers
  retain their existing API and descriptors.
- Focused checks also exercise preparation under a currently denied input policy, incompatible
  codec rejection without pinning the track, altered provider descriptors, and refreshing a stale
  candidate after unrelated membership changes. The denied-input check confirms that no held audio
  reaches the prepared session; the existing live input policy remains unchanged until commit.
- Design review rejected a second ingress policy lease/timer and synthetic readiness based solely on
  the future interval. The input adapter queries the existing provider lease and validates the live
  buffer's interval, track, identity and capacity. No capability query runs inside an ingress callback.
  The complete connection graph and startup/transfer orchestration still need to select these bindings.
- Final focused run passes 45 checks across speech-policy rooms, input buffers, STT and the readiness
  collector. All five root checks pass: format, warnings-as-errors compilation, strict Credo,
  1,179 tests with zero failures and 15 integrations excluded, and unused dependencies. No browser,
  provider call, or running-server restart was performed.
- Gateway's connection adapter still calls the two-argument track preparation and current-resource
  query, and accepts only installed policy intervals. Its next integration needs explicit persistent
  phase ownership and the attempt's existing deadline; an ephemeral query worker must not own STT
  preparations. Other candidate media/room enforcers and the complete lifecycle sequence remain open.

## Prepare input decoder policy

- The prior goal turn committed prepared STT input bindings as `e9284ea`. The worktree is clean.
  Gateway input policy application still starts the replacement decoder during commit. Move that
  startup and negotiated-track preparation ahead of commit, retaining the installed decoder until
  the candidate decoder has acknowledged readiness. Unrelated revisions must retain both decoders.
- Added Gateway boundary checks using the actual policy authority and per-connection pipeline
  supervisor. A controlled decoder fixture delays operational readiness independently of process
  startup. The first checks require ready-instance adoption, pending-audio isolation and exact discard.
- Fixed the new fixture's missing compiler registries, then confirmed two failures at the absent
  `prepare_policy/4` API. The first collector check also required the controlled pipeline's readiness
  method to accept its actual instance PID, matching the production adapter contract.
- Prepared decoder adoption/discard passed, followed by owner loss, expiry, pending failure,
  unchanged retention, a future denial and candidate refresh after unrelated membership. The real
  WebRTC check exposed a startup-ready flag changing during track preparation. Comparing that flag
  as identity incorrectly returned unavailable. Validation now compares stable pipeline bindings
  while incorporating the current readiness flag; actual WebRTC/Telnyx/Twilio decoder checks pass.
- Review of incoming web/phone audio found that stopping a denied decoder would surface
  `pipeline_unavailable` and could disconnect a live leg. A red denial check reproduced that result.
  Input forbidden by the installed policy is now discarded with the ordinary accepted/drop outcome;
  the phone input boundary confirms it is not a connection failure. No forbidden input is decoded.
- The adoption check also exercises the committed transport timestamp cutoff and preservation of
  normalized-frame sequence across pipelines. Corrected the clock fixture callback's arity.
  Twenty-two focused checks pass. Final root verification follows.
- The first root gate run passed before a further demand review. An unchanged permission interval
  does not imply continued input demand: without recording, departure of the last recipient makes
  the decoder unnecessary. A new red check returned retained resources for that case. Preparation
  now checks demand before interval retention and prepares a missing decoder when recipients return.
  The check removes and re-adds the decoder through actual authority commits; final gates are rerun
  for this additional runtime change below.
- Final focused checks pass 24 tests across input policy preparation, input pipelines and web input
  delivery. All five final root gates pass: formatting, warnings-as-errors compilation, strict Credo,
  1,192 tests with zero failures and 15 integrations excluded, and unused dependencies. Actual decoder
  checks cover WebRTC Opus, Telnyx Opus and Twilio PCMU; no browser or provider call was exercised.
- Recorded the input preparation contract and rejected alternatives in the readiness contract. The
  remaining milestone includes candidate output/mixer/recording preparation, complete graph selection,
  persistent lifecycle ownership, startup/transfer waits and cues, final release, restoration,
  telemetry and rendered/provider acceptance. The milestone and index remain unchecked.

## Prepare shared output routes

- The preceding goal turn committed prepared room-input decoders as `43aafa2`. Inspection starts
  from a clean worktree. Shared output pipeline construction currently binds its route immediately,
  revoking the live route before a prospective policy can be collected.
- Add a prepared room route that retains the active route and the native encoder/RTP timeline.
  Bind the preparation to the existing persistent owner, attempt, deadline and held-output generation.
  Commit must acknowledge the exact collected resource and require private playback to have drained.
  The first red checks cover held preparation, cue-before-commit ordering, adoption and scoped discard.
- Direct arbiter checks passed after the preparation protocol was added. The shared-pipeline red
  checks then reproduced loss of the live route during construction (16 checks, two failures).
  Construction now reserves a pending route, and explicit owner activation adopts its exact ready
  descriptor after private playback drains. All 19 focused checks pass, including deadline expiry,
  stale cleanup, generation changes, owner loss, unchanged native output and RTP continuity.
- The preceding rename-only turn made no implementation progress. Reinspection confirmed the pending
  output work and its completed 16-check run; work resumed from those files without restarting a
  live job. Expiry and restoration checks now verify the source route remains usable.
- Design review preserves the native encoder and current room binding during preparation. A new
  held generation invalidates pending work; commit releases only the phase lease, so later phase
  shutdown cannot stop an adopted route. Deadline extension and mismatched collected evidence fail.
  Full mixer/room-egress candidate integration and lifecycle orchestration remain unfinished.
- Final umbrella checks pass: formatting, warnings-as-errors compilation, strict Credo,
  1,199 tests with zero failures and 15 integrations excluded, and unused dependencies. The
  readiness contract and milestone record this output checkpoint without closing lifecycle gates.
  No application restart, browser inspection or provider call was performed for this backend change.

## Prepare mixer policy and subscriptions

- The previous goal turn completed and committed shared output preparation as `004f4ef`; this is
  progress. The worktree is clean. The next missing dependency is a mixer acknowledgement of the
  prospective policy and initialized destination subscription without admitting future media.
- Keep current queues and subscription tokens in place. Reserve only missing subscriptions outside
  active fanout, under the existing owner/attempt/deadline. Matching policy commit adopts them, while
  discard/failure leaves live subscriptions untouched. A candidate is validated by its authority
  outside the mixer callback; the callback must check the actual room authority and installed base.
- Start with boundary checks for isolated preparation, exact descriptor adoption and retained live
  delivery, using the actual policy authority and mixer rather than a fabricated policy snapshot.
- The first two checks failed at the absent mixer preparation API, then passed with isolated staged
  subscriptions and matching-policy adoption. Further red checks exposed delivery of pre-commit
  buffered source audio to the joining subscriber and collision with ordinary registration of a
  reserved ID. New subscriptions now receive per-source sequence cutoffs at adoption; existing
  listeners retain their queues, and reserved IDs cannot be registered by another path.
- The collector stops probing once ready and requires explicit refresh. Cancellation now notifies
  the phase owner and new subscription owners. Failed preparation reports its known descriptor as
  failed on refresh rather than leaving terminal failure classified as a transient unavailable query.
  Source delivery remains available, and a failed candidate cannot be installed.
- A red handle query showed that Gateway consumers need the same opaque subscription handle to
  report readiness before and after commit. Handles now carry a private policy token when needed.
  A later-attempt regression then exposed loss of that adopted handle during unchanged preparation.
  Store the adopted policy binding on the affected subscription instead of tying every handle to
  the newest room-level lease. Unchanged handles, configurations and generations now survive later
  attempts; changed permissions update only their policy evidence.
- Twenty-seven focused mixer checks pass, including ten new policy-preparation checks. They cover
  the real authority, privacy application, source queue retention, discarded/expired/orphaned work,
  subscriber loss, unchanged second-attempt handles, candidate refresh, foreign candidates and an
  invalid subscription set. Root verification follows. No browser or live-provider acceptance yet.
- Final membership review added a red case where one of two prospective listeners disappears.
  Appending requested subscriptions kept the departed listener in the required set and rejected
  refresh. An explicit subscription list now reconciles the complete desired set, cancelling only
  removed new queues after the new set validates. Omission retains the prior selection. The joining
  listener keeps its handle, generation and readiness evidence. All 28 focused checks pass.
- All five final root gates pass: formatting, warnings-as-errors compilation, strict Credo,
  1,210 tests with zero failures and 15 integrations excluded, and unused dependencies. Final
  verification includes the listener-removal fix; earlier partial gate runs are not the final evidence.
  Updated the readiness contract and milestone, leaving the common-readiness and lifecycle gates open.
- Next dependency: Gateway room egress must prepare its prospective subscription/output pair,
  validate the opaque prepared subscription handle, and adopt the ready output without querying
  the mixer from a policy-enforcement callback. Transcript/recording candidate preparation, complete
  graph selection, waits/cues, coordinated release, restoration and rendered/provider acceptance remain.

## Hold and release room output

- The prior mixer preparation checkpoint is committed as `b079dbf`, with a clean worktree and all
  root checks passing. This is progress. While tracing room-egress adoption, found two prerequisites:
  the mixer always emits output generation zero, and clearing a current arbiter room frame leaves
  its shared producer without a completion acknowledgement. A retained room route cannot resume
  reliably after a generation-fenced hold until both are addressed.
- Proposed, not implemented: add subscription-local output gates that preserve subscription/readiness
  identity, discard held audio and buffered pre-release frames, and stamp released frames with the
  acknowledged generation.
  Compose the mixer gate and native output hold/release outside the room-egress callback. Keep
  per-listener gates separate from privacy policy and capability lifecycle.
- Added a red mixer check: holding one listener must clear its old/held audio, leave the other
  listener and subscription identity intact, and release only fresh frames with the new generation.
  The focused run completed with 18 tests and one failure because `Subscription.hold/2` is absent.
- Added a red shared-output check: clearing a playing room frame must acknowledge its discard to
  the producer after native drain, allowing later room delivery. After correcting the manual pacing
  fixture to advance its outstanding native tick, the run completed with 20 tests and one failure
  on the missing `vxpipe_room_audio_output_sent` acknowledgement. This is flow-control evidence,
  not proof that discarded audio played.
- Both runs completed before this audit; no test job remains pending from this checkpoint. Retained
  local log filenames are `vxpipe-mixer-output-gate-red.log` and `vxpipe-room-output-clear-red.log`.
  No runtime changes for these two findings were made before the user-requested pause. The tests
  remain uncommitted; no green or end-to-end acceptance is claimed.

## Resumed room output hold and release

- The preceding documentation turn made progress by committing the detour audit as `a6527f9`.
  The subsequent goal continuation requested implementation again. Rechecked the worktree: only
  the two documented red tests remained modified, with no live test job. Continued from those
  checks without broadening their scope into another readiness-adapter survey.
- Mixer subscription holds now clear only that listener's queue and suppress held delivery. Release
  captures source cutoffs so buffered held audio cannot replay, and fresh frames carry the released
  generation. Duplicate transitions retain state; stale generations cannot change it. Subscription
  tokens/readiness, other listeners, policy and recording lifetimes remain unchanged.
- Native clear now sends a distinct discarded-room-frame notification only after its successful
  drain. Shared output translates that into producer flow control, releasing an otherwise stuck
  egress frame. It never claims that the discarded frame played or that a private cue completed.
  The original focused files passed with 29 engine checks and 20 Gateway checks.
- Added the missing combined Gateway operation: hold the real mixer subscription before native
  output; release native output only after private playback drains, then release the subscription.
  Capture/revalidate the exact route and relevant policy binding outside the egress callback.
  A failure after native release reports uncertain release and notifies the connection owner to end
  its room-output boundary. The coordinator still owns cancellation/deadlines and all-listener release.
- Two Gateway integration checks first failed at the absent `RoomAudioEgress.hold/2` boundary
  (22 tests, two failures). The completed implementation passes 31 Gateway checks plus 29 engine
  checks. The actual mixer, shared pipeline and native WebRTC output prove private audio precedes
  fresh room audio on the same RTP clock/SSRC and retain their exact readiness descriptors. A lost
  mixer during release proves terminal connection-owner notification. Full root gates follow.
- Remaining lifecycle wiring must supply the current generation to direct conversational TTS and
  opening/briefing output as well as wait players, and gate microphone/model admission. Those frame
  producers still default to generation zero unless explicitly supplied; this checkpoint only
  integrates the room-mixer output path. Prepared egress adoption, complete readiness, startup,
  transfer orchestration, restoration and rendered/provider acceptance remain unfinished.
- The focused combined fixture needed no production dependency or timeout workaround. Recorded
  the gate ordering, rejected alternatives and acceptance limits in the readiness resource contract.
- Final root verification passes all five required gates: formatting, warnings-as-errors compilation,
  strict Credo, 1,214 tests with zero failures and 15 integrations excluded, and unused dependencies.
  The root command completed with exit zero; retained local logs use the prefix
  `vxpipe-output-gate-root-`. No browser, live provider or development-server restart was performed.
  The milestone records the room-output boundary while leaving all remaining lifecycle acceptance
  gates open. Pending prepared subscriptions still need their held generation carried through
  egress adoption before this can be used for the incoming transfer destination.

## Prepare room egress for policy adoption

- The previous goal turn committed coordinated room-output gates as `bd7b1e1` and passed all
  root checks. Revalidated a clean worktree. Continued into the existing Gateway egress path,
  rather than adding another survey of capability adapters.
- Design decision: shared output has no codec or policy configuration of its own. Retain an
  existing pipeline and mixer subscription through an affected output-policy change while held;
  stage a shared pipeline only for a joining connection that has no room route. The mixer owns
  audio permission changes. Ordinary direct-encoder fallback behavior is retained.
- Five integration checks first failed on the absent egress preparation API. Candidate validation,
  the exact prepared mixer handle, held generation and original owner/attempt/deadline now bind
  preparation. Newly prepared mixer queues can be held before adoption and stay held afterward.
  The first green run passes all five checks, covering retained and joining output, unchanged
  resource identity, scoped discard and phase-owner loss.
- Readiness validates the opaque prepared subscription binding and persists its descriptor through
  adoption. Dependency observations run outside the egress callback; policy acknowledgement defers
  mixer delivery until after the callback returns. Pending shared routes support explicit discard,
  so cancellation can acknowledge native reservation cleanup without waiting for a DOWN race.
- Review exposed two real defects in the initial implementation. A foreign subscription was held
  before its identity was rejected, silencing another room. Also, replacing a retained native room
  binding after collection still allowed stale readiness to commit. Both red checks reproduced their
  intended failures. Validation now precedes gating and rechecks before staging; retained route
  adoption revalidates the exact native binding. Broader focused verification follows.
- The only new-fixture correction so far was removing a leftover `do` while extracting the mixer
  preparation helper. No dependency version, production timeout or running server changed. Full
  connection-graph selection and startup/transfer lifecycle integration remain unfinished.
- The first broader pass succeeded with 38 Gateway checks. A further membership check then
  reproduced the dormant joining egress taking the ordinary replacement path on an unrelated
  admission, colliding with its reserved native route and failing the policy barrier. Dormant
  egress now updates its installed policy without launching a live pipeline. Candidate refresh
  retains the pending route, subscription, original lease and resource generations/configurations.
- Extending the joining check to an already-waiting `await_ready` caller exposed a missing adoption
  acknowledgement: the prepared pipeline's earlier ready message correctly stayed private, but
  commit did not answer that caller. Commit now replies only after successful prepared-route
  activation. Both defects were reproduced before their fixes; final focused and root checks follow.
- Concurrent user work appeared under `vxpipe-docs/` during this checkpoint. Preserve those edits
  and stage only this checkpoint's engine/Gateway implementation, checks and documentation.
- The initial full root run passed all five gates with 1,222 tests. Final delivery-path review
  then reproduced false readiness for a mixer queue with matching room/participant IDs but the
  wrong subscriber process (nine checks, one failure). The mixer now confirms the actual queue
  consumer before egress can hold or prepare it. This adds no new resource lifetime. Final focused
  and root gates repeat for this additional boundary fix; the earlier run is intermediate evidence.
- The repeated root run passed all engine/Gateway checks but failed an existing diagnostics
  read-only fixture when the global registry lost 20 bindings during page mount. Equality rejected
  unrelated cleanup. The fixture now compares actual binding/room PID sets to reject additions
  while allowing removals; it does not merely compare counts. The separate
  [diagnostics cleanup labnote](20260914-0942-diagnostics-registry-cleanup.md) records this detour and
  its verification. Application/UI code and production timeouts are unchanged by that correction.
- Final focused results pass 29 engine checks, 40 Gateway checks and eight diagnostics checks.
  The final root logs record passing formatting, warnings-as-errors compilation, strict Credo,
  and all eight application suites: 1,223 tests, zero failures and 15 integration exclusions.
  Log filenames use the prefix `vxpipe-egress-policy-verified-root-`. The original job handle was
  unavailable after context recovery, so the last unused-dependency check was confirmed separately
  with exit zero; the already-completed test suite was not rerun for that bookkeeping issue.
- Updated this labnote's detour index and the milestone evidence. The diagnostics fixture is a
  separate commit purpose from engine/Gateway prepared output. Concurrent documentation-app edits
  remain outside both checkpoints. No new implementation was added for this notes update, and no
  browser, provider call or development-server restart was performed. The full milestone remains
  open; these checks do not establish the requested end-to-end transfer behavior.

## Select candidate connection resources

- The previous turn committed prepared egress as `97119f8` and the diagnostics fixture as
  `0eaa94d`. This is progress. Rechecked the worktree; only concurrent `vxpipe-docs/` edits remain.
- The connection graph still collects only installed-policy resources. It cannot select prepared
  speech/input/output bindings, so the complete resource collector rejects a prospective policy.
  Add a candidate collection path under the persistent phase owner and existing absolute deadline,
  selecting exact prepared mixer/speech dependencies. Validate candidate and connection bindings
  before and after the bounded external work; collection must not grant prospective permissions.
- Start with the actual WebRTC connection, authority, mixer and native media path. The regression
  will prepare an affected graph while keeping current media installed, collect it, and adopt the
  same resources through the authoritative policy barrier.
- The red WebRTC run failed at the absent `ConnectionReadiness.prepare_candidate/5` boundary.
  The completed query now selects prospective decoder, speech input and room-output resources,
  preserves the phase lease, and checks the actual authority and connection before returning.
  Returned input/output handles support scoped discard, including partial preparation cleanup.
- The WebRTC adoption check passes using actual negotiated input, native output and the public
  participant join path. It proves discard/retry, retained codec descriptors, collected bindings
  surviving adoption, and subsequent audio delivery to the new participant. A separate extension
  of the existing human-transfer fixture selects an affected pending STT session, waits for its
  explicit Connected message, discards it and resumes the original audio/transcript conversation.
- Fixture corrections: prepared the initial decoder before asserting it ready; used public
  participant join rather than policy-only admission before opening a new participant connection;
  replaced an assumed STT close callback with monitoring actual connector-owned transport exit.
  These fixture failures are not claimed as production regressions. No package or production
  timeout changes were needed. The intended red log is `vxpipe-candidate-graph-red.log`.
- Focused checks pass 32 engine tests and nine Gateway WebRTC/Telnyx/Twilio tests. Strict Credo
  also passes. Final root verification follows a deadline review that removes the one-millisecond
  fallback after an absolute preparation deadline has already elapsed.
- This connects prepared resources into the per-connection query, not the complete room phase.
  `Readiness.Preparation.run/3` still uses current-policy graph collection; the persistent lifecycle
  owner must prepare the complete mixer/STT set, create private destination bindings, select this
  query and finish room-service/recording candidate preparation. Startup/transfer waits, cues,
  microphone/model gates, restoration and rendered/provider acceptance remain open.
- The first root run passed all five gates with 1,224 tests. Final review then found that a false
  prospective input demand skipped preparation entirely, allowing the legacy policy callback to
  replace a decoder that should stop. Extending the real WebRTC check reproduced the unwanted
  decoder after commit. Candidate collection now stages the existing input's deferred shutdown,
  requires no track/readiness for the removed decoder, and includes its handle for cancellation.
  The regression passes; final gates repeat for this additional runtime fix. No broader lifecycle
  completion is inferred from it. Retained red/green logs use `vxpipe-candidate-graph-removal-`.
- The repeated full run caught a new fixture race: client connection completion preceded the
  server's readiness event. The new receiver assertion observed `preparing`. The fixture now
  collects both exact server transport resources and waits for their ready acknowledgement before
  capturing candidate bindings. No sleep or production timeout increase is used. This correction
  stays with the connection checkpoint, rather than becoming an unrelated fixture commit.
- Final root verification passes all five gates: formatting, warnings-as-errors compilation,
  strict Credo, 1,224 tests with zero failures and 15 integration exclusions, and unused
  dependencies. All eight application suites completed and the runner exited zero. Retained
  logs and the explicit per-check result file use `vxpipe-candidate-graph-verified-root-`.
  The final WebRTC file also passes all five focused checks after the server-readiness correction.
- Verified the changed documentation's local links/anchors and `git diff --check`. No rendered
  browser inspection, live provider call or development-server restart was performed. Keep the
  milestone/index open and preserve concurrent `vxpipe-docs/` work outside this commit.

## Prepare the prospective room graph

Status recorded by notes commit `ec93f3b`: **uncommitted implementation; focused verification only**.
The subsequent implementation and final gates are recorded in the verification checkpoint below.

- The preceding turn committed candidate connection collection as `9fc4b83` with all root gates
  passing. This is progress. Rechecked the worktree and retained concurrent `vxpipe-docs/` changes.
- Connect whole-room preparation to the existing authoritative inventory and candidate connection
  query. Derive the complete mixer subscription request set from actual connection bindings, prepare
  selected speech sessions under the persistent phase lease, and collect every remaining participant
  plus room resource. Transcript routing needs prospective-policy acknowledgement without changing
  current projection decisions or restarting its process.
- Start with actual WebRTC listeners and a prospective departure that changes permitted routing.
  The check must collect the complete resulting room before policy application, preserve unaffected
  resources, and deliver audio after adoption. Recording candidate preparation and creation of
  private destination actors remain explicit requirements; do not silently substitute current
  resources when their prospective configuration is unsupported.
- The initial WebRTC check failed at the missing `Preparation.run_candidate/3` API. Its retained
  red log reports one test and one failure. The subsequent green log reports one test, zero
  failures and five excluded tests. These are `vxpipe-room-candidate-red.log` and
  `vxpipe-room-candidate-green.log` in the local temporary log directory.
- The working implementation captures actual connection bindings, prepares the complete requested
  mixer subscription set and transcript router, selects affected speech preparations, and collects
  connection resources under one owner/attempt/deadline. It returns cancellation handles and
  revalidates the authoritative inventory before success. Transcript policy preparation keeps
  current projections unchanged until policy installation and retains the router process.
- The green WebRTC check removes a restrictive participant prospectively, collects the two
  remaining connections, verifies that transcript permissions stay closed before commit, and
  adopts the same resource descriptors. Actual audio reaches the remaining listener after release;
  native output descriptors are retained. This fixture configures neither recording nor STT, so
  it does not establish whole-room recording or speech preparation, private transfer admission,
  or the user-facing transfer flow.
- Existing engine transcript-router, connection-readiness and inventory checks also finished:
  38 tests, zero failures, recorded in `vxpipe-room-candidate-engine.log`. This notes update read
  the completed logs; it did not rerun those commands. The new router lease/cancellation behavior
  still needs focused failure coverage, and the whole-room changes have not passed all five root
  gates. Do not carry forward the preceding commit's green gates as evidence for this worktree.

### Recording preparation gap

- `RoomRecording.Preparation` reads the installed mixer recording policy, rejects a different
  interval, and validates individual tracks against currently present participants. It then
  changes the live recorder's required tracks and opens missing writers. Calling this path for a
  future participant set is insufficient for private preparation before policy commit.
- `Recording.Writer` provides `open/2`, `offer/2` and optional `readiness/1`; it has no scoped
  cancellation callback. `RoomRecording.Streams` passes the recorder as the writer's source.
  A future writer therefore needs an explicit ownership/cancellation design before it can be
  prepared independently and either adopted or discarded without disturbing live recording.
- Candidate preparation also needs exact prospective recording subscription and output-tap
  evidence. Relabeling current resources with the future interval would claim readiness without
  preparing the actual paths. No recording fix or writer-interface change was made in this update.
  This is an unresolved project implementation dependency, not an external service outage or a
  reason to raise the transfer deadline.

### Resume boundary and notes verification

- Seven engine/Gateway source and test files currently contain the uncommitted whole-room changes,
  including the new candidate-preparation and transcript-policy-preparation modules. Keep their
  implementation, remaining verification and documentation together in a subsequent checkpoint.
  Concurrent changes under `vxpipe-docs/` belong to the user's separate work.
- After this component is verified, the milestone still needs recording candidate preparation,
  private destination actors and persistent phase ownership wired into startup and transfer;
  all-listener waits/cues and release acknowledgements; bounded restoration; and sample/browser
  plus web/phone acceptance. None of those remaining gates is checked off by this notes update.
- Cross-checked this update against the relevant diffs, writer/preparation interfaces, completed
  focused logs and the preceding checkpoint's per-command root result file. The earlier eight-hour
  timeline and detour table remain historical evidence. No new test, browser session, provider call
  or development-server restart was performed for this documentation request.
- Documentation verification passed: all 33 local links/anchors resolve, and `git diff --check`
  reports no whitespace errors in the changed labnote.

### Prospective room verification checkpoint

- Resumed implementation after the notes commit `ec93f3b`. The preceding turn made progress by
  recording the evidence and outstanding ownership gap. The worktree remains authoritative;
  concurrent `vxpipe-docs/` edits are preserved outside this checkpoint.
- Added router boundary checks for current permissions through candidate refresh, original-deadline
  retention, adopted resource identity, scoped discard/retry, owner loss and actual lease expiry.
  Their initial fixture registered the router after admission and therefore lacked the historical
  speech interval needed by current projection. Registering it before membership changes, as in
  production, corrected the fixture; this was not a production regression. All four checks pass.
- Extended the real whole-room departure check to discard and retry all preparations before
  collection/adoption. The human-transfer fixture now also holds both connected humans, collects
  their unchanged STT and recording writers through the whole-room runner, cancels preparation,
  then resumes the existing audio/transcript conversation. Both WebRTC files pass: seven tests,
  zero failures. Retained logs: `vxpipe-router-candidate-focused.log` and
  `vxpipe-room-candidate-gateway.log`.
- Recording membership changes still need independent preparation: even when its policy interval
  stays unchanged, calling the current track preparer for a future set would change live required
  tracks before commit. The new retained-recording check uses unchanged membership and policy; it
  does not prove future recording readiness. This limitation is explicit in the durable resource
  contract and milestone evidence. Full recording adoption remains the next missing room boundary.
- Whole-room, router and connection implementation remain one coherent checkpoint. Final focused
  and all five root gates follow; no browser/provider acceptance is claimed by these checks.
- Recorded a real failure before final verification: removing a recorded caller prospectively
  returned a successful room preparation and changed the live required track set before commit.
  The extended WebRTC check failed at that unexpected success. Recording preparation now compares
  authoritative current/future recorded sources and returns `policy_not_prepared` before mutating
  writers when they differ. The check verifies exact writer resources survive and a subsequent
  unchanged-room preparation succeeds, proving cleanup of the other pending resources as well.
  Logs `vxpipe-room-recording-boundary-red.log` and `vxpipe-room-recording-boundary-green.log`
  record the intended red failure and the seven passing WebRTC checks. This guard does not replace
  the required future recording implementation; it prevents premature live changes in the new runner.
- Broader focused engine checks passed: 42 tests, zero failures. The five root gates are running
  with per-command exit codes retained under `vxpipe-prospective-room-root-` for recovery.
- Final verification passes all five root gates: formatting, warnings-as-errors compilation,
  strict Credo, 1,229 tests with zero failures and 15 integrations excluded, and unused dependencies.
  All eight application suites completed; every result in the retained root result file is exit
  zero. Verified all 48 local documentation links/anchors and `git diff --check`. No package change,
  production timeout increase, browser session, provider call or server restart was required.
- Commit the whole-room preparation, router leases, recording failure boundary and their focused
  checks/documentation together. Preserve the separate `vxpipe-docs/` work. The milestone and index
  remain open; the future recording ownership gap above is still unresolved.

## Prepare recording ownership and policy

- The preceding whole-room checkpoint `02ab65e` passed all gates and made progress. Revalidated
  that only the user's separate `vxpipe-docs/` work remains dirty before this checkpoint.
- Recording preparation must stage future required tracks without mutating live streams, retain
  existing writers, and adopt under the authoritative policy barrier. The existing writer port
  already accepts a source process; artifact writers monitor that source and drain when it exits.
  Use an independently supervised source for each newly prepared writer, bound to the recorder,
  phase owner and original deadline. Adoption removes only the phase lease; discard ends only
  pending sources. Existing writers and their sources remain untouched.
- This avoids adding provider-specific cancellation or rebinding live writer sources. Opening a
  local writer remains governed by the existing non-blocking writer contract; asynchronous remote
  storage is outside the local readiness barrier. The subsequent recorder policy must also select
  exact future mixer subscription evidence and preserve current recording until commit.
- Six writer-source checks first failed on the missing `PreparedWriter.start/3` boundary, then
  passed. The source keeps provider options separate from phase options, opens the existing writer
  port with itself as source, and supports recorder-only adoption, scoped discard, phase/recorder
  loss and actual deadline expiry. Adoption preserves the handle and source until recorder exit.
  Logs use `vxpipe-recording-owner-red.log` and `vxpipe-recording-owner-green.log`.
- Four recorder checks then failed at the absent `RoomRecording.prepare_policy/4` boundary. The
  implementation stages only missing writers and future track selection, obtains exact prepared
  recording subscriptions from the mixer, and confirms readiness outside recorder callbacks.
  Policy adoption retains current live stream counters and adopts new source lifetimes. Initial
  green evidence is in `vxpipe-recording-policy-green.log`.
- A new mixer-loss check reproduced the pending-policy DOWN clause swallowing the mixer's death.
  Giving the existing mixer-monitor clause priority restores recorder termination. Its red log is
  `vxpipe-recording-mixer-loss-red.log`. The first broader run also showed that registering every
  recorder as an enforcer at startup changed existing missing-recorder inventory behavior. Instead,
  register on first candidate preparation after identity validation, outside the recorder loop.
  Ordinary startup remains unchanged; a recorder participating in the policy barrier is thereafter
  governed by the existing enforcer-loss contract.
- Replaced the previous whole-room failure-only recording check with successful future preparation,
  unchanged live writer evidence, discard and retry. It first failed at the old rejection boundary
  (`vxpipe-recording-room-red.log`), then passed through the candidate recording runner. The seven
  WebRTC checks in `vxpipe-recording-room-green.log` continue the original audio/transcript flow.
- Two further retention checks reproduced unnecessary descriptor replacement for unchanged full-mix
  recording and failure to confirm a new preparation through a previously adopted descriptor.
  Readiness now compares actual selections/handles/subscriptions independently of initialization
  metadata and confirms a later matching pending selection through the retained binding. Red/green
  logs use `vxpipe-recording-retained-`. No writer/provider restart or deadline increase was needed.
- Final focused engine coverage passes 52 tests with zero failures (`vxpipe-recording-final-focused.log`);
  strict Credo also passes. Native agent-output tap evidence is still installed-policy-only, so an
  agent recording requirement whose recording interval changes remains explicitly unsupported in
  candidate output selection. This checkpoint completes recorder track/writer staging, not that
  native tap boundary or the complete lifecycle. Root verification follows.
- The first full root run passed all five gates with 1,242 tests. Final ownership review then
  reproduced a required writer dying after its ready report without invalidating recorder adoption.
  The new check failed at the absent failure notification (`vxpipe-recording-writer-loss-red.log`).
  The recorder now monitors the exact required writer instances when confirming readiness, in
  addition to its phase and newly prepared sources. Losing one invalidates pending adoption and
  closes pending writers. The expanded focused run passes 53 tests; final root gates repeat for
  this runtime correction under `vxpipe-recording-policy-verified-root-`.
- Final root verification passes all five gates: formatting, warnings-as-errors compilation,
  strict Credo, 1,243 tests with zero failures and 15 integrations excluded, and unused dependencies.
  Every retained per-command result is exit zero and all eight application suites completed. Local
  documentation links/anchors and `git diff --check` pass. No dependency version, production timeout,
  running server, browser session or live provider call changed for this checkpoint.
- Keep the implementation, focused checks and documentation together and preserve concurrent
  `vxpipe-docs/` changes, including the user's separate `ae699c5` logo commit. The milestone/index
  remain open; native agent tap intervals and startup/transfer lifecycle acceptance are still required.

## Recording tap investigation and handoff resume point

This is the requested labnote update after `4b14530`. The findings below come from source inspection;
no additional runtime change or regression test was made for this update.

- **Why recording needed separate groundwork:** future membership can change required recording
  tracks even when recording permission stays the same. Preparing those tracks through the old
  path changed live recorder selections before commit. `4b14530` stages missing writers under the
  phase owner and deadline, then adopts them while preserving existing writers and sequence numbers.
  The preceding checkpoint records the ownership, monitor-ordering and descriptor-retention fixes
  and their actual red/green evidence.
- **Remaining native tap boundary:** `RecordingOutputs.prepare/2` passes the candidate snapshot to
  `Recording.EgressReadiness.prepare/4`, but that adapter observes the mixer's installed recording
  interval. `RoomMixer.RecordingEgress.readiness/3` also requires recording to be currently enabled.
  A required agent tap therefore cannot report prospective readiness when that interval changes.
  Recorder writer preparation alone does not resolve this mismatch.
- **Design considered, still unimplemented:** the mixer changes the recording permission gate
  without reallocating the native tap or codec. Separating physical tap evidence from the prepared
  mixer policy resource could preserve that allocation while keeping recording closed until commit.
  This would still need exact native binding, identity, format, capacity and candidate lease checks.
  A separate per-tap preparation registry would duplicate ownership and require reconciliation;
  merely substituting the future interval into current evidence would not prove readiness. Neither
  approach has been implemented or verified by this inspection.
- **Concrete handoff integration gap:** `HumanHandoff.apply_control/2` currently accepts an early
  acceptance request; progression waits for briefing completion. Once both conditions hold,
  `progress/2` cancels the attempt timer and calls `HumanCommitter.commit/3`. That committer starts
  the destination participant, promotes its admission, queues connection promotion, and publishes
  completion before the queued media promotion has been acknowledged. The new whole-room readiness
  runner is not wired into this sequence. These are source findings, not a fresh reproduction of
  the reported phone/console failure.
- **Resume at the runnable transfer boundary:** finish candidate tap evidence where required, then
  connect private destination media and the persistent phase owner to this handoff. Keep the
  original deadline through readiness, listener waits/cues, policy adoption and release. Completion
  must follow the required release acknowledgements. Startup, AI transfers, restoration and the
  sample/browser plus phone acceptance gates remain explicit unfinished work in the milestone.
  Further component checks must not be reported as completion of the user-facing transfer flow.

Verification for this notes update re-read the committed implementation and the retained
`vxpipe-recording-policy-verified-root-results.json` results: all five commands exited zero.
The eight application summaries total 1,243 tests, zero failures and 15 integration exclusions.
Those are evidence for `4b14530`, not newly run checks or live transfer acceptance. No dependency
upgrade, production deadline change, browser session, provider call or server restart was performed.
Concurrent `vxpipe-docs/` changes remain outside this documentation checkpoint.
Documentation verification: all 34 local labnote links/anchors resolve, and `git diff --check` passes.

## Prepare native recording taps for a candidate policy

- The preceding goal turn made progress by committing the requested investigation notes as
  `8dc6726`. Resumed implementation from the verified worktree; concurrent `vxpipe-docs/` work stays
  separate. The remaining tap mismatch above was confirmed in the installed recording query.
- The mixer already owns the mutable recording gate; changing permission does not allocate another
  native tap or codec. Separate physical tap readiness from permission readiness, and require the
  exact prepared mixer resource alongside the tap in candidate recording collection. Reuse the
  existing authoritative candidate and phase lease rather than creating a per-tap registry.
- A focused authoritative-policy check first failed at the missing `EgressReadiness.prepare_candidate/5`
  API (`vxpipe-tap-policy-red.log`). It now proves that preparation leaves denied recording closed,
  adoption retains the native resource and tap, and only committed permission admits audio. The
  installed query still rejects mismatched or denied recording policy. Initial focused coverage
  passed seven checks (`vxpipe-tap-policy-green.log`).
- Candidate recording selection first failed at its missing prepared-mixer argument, then passed
  with physical tap and mixer dependencies carried into the recording result. The test prepares an
  agent writer privately and verifies scoped cancellation. The whole-room runner supplies its
  already prepared mixer resource. Final focused engine coverage passes 41 tests in
  `vxpipe-tap-selection-green.log`.
- Corrected one new test expectation: an unavailable discarded mixer binding keeps the existing
  collector in `preparing`, not immediate `failed`. The check now verifies closed collection and
  the actual unavailable mixer binding while the physical tap remains ready. This did not require
  changing collector semantics or its original deadline.
- Added a real WebRTC agent-room check for recording permission relaxation, complete resource
  collection, discard/retry, exact adoption and output release. Its first run exposed a fixture
  error: direct calls assumed every adapter implemented the optional `readiness_binding/1` callback.
  Rechecking through the actual collector uses the supported adapter contract and verifies the
  complete resource set. This fixture failure is not claimed as a production defect.
- The durable readiness contract records the ownership decision and rejected alternatives. Native
  tap selection no longer needs a recording-interval workaround. Private destination preparation,
  persistent startup/transfer orchestration, waits/cues, recovery and browser/provider acceptance
  remain unfinished. No package version or production deadline changes are part of this checkpoint.
- Both WebRTC files now pass eight tests (`vxpipe-tap-policy-room-green.log`), including the new
  full-room permission change and the existing human audio/transcript transfer. Root verification
  initially stopped at formatting of the changed recording-output fixture; formatted that exact
  file and restarted the gates under `vxpipe-tap-policy-verified-root-`. Formatting, compilation and
  strict Credo have passed; the full test command is still running. No runtime fix was needed for
  that formatting failure.
- That root run completed with one existing event-publisher fixture failure at its 100 ms policy
  setup acknowledgement; all new engine and Gateway cases passed. The unchanged fixture passes
  in isolation. Its separate [deadline labnote](20260914-1156-transcript-fixture-deadline.md)
  records the evidence and one-second fixture correction. Production timeouts and transcript
  behavior remain unchanged. Final root gates repeat for the corrected worktree.
- Final verification passes all five root gates: formatting, warnings-as-errors compilation,
  strict Credo, 1,248 tests with zero failures and 15 integration exclusions, and unused dependencies.
  The eight application summaries and all per-command exits in
  `vxpipe-tap-policy-final-root-results.json` confirm completion. The fixture fix is committed
  separately as `ec5d408`; no package change or production timeout increase was needed.
- Verified local documentation links/anchors and `git diff --check`. No rendered browser inspection,
  live provider call or development-server restart was performed. The user's concurrent Starlight
  migration is committed as `175b331`; remaining `vxpipe-docs/` edits are preserved. This completes
  the native tap dependency, while milestone/index acceptance and lifecycle integration remain open.

## Commit the exact prospective membership

- The preceding goal turn made progress: native recording tap preparation was committed as
  `666ca37` with all root gates passing; the independent fixture correction is `ec5d408`.
  Revalidated the worktree before continuing into destination preparation.
- Source inspection confirms private connections have no main room ingress/egress actors, and STT
  configuration/binding currently requires main admission. Their future initialization needs a
  narrowly authorized attempt binding. `ParticipantLifecycle.prepare/3` already exists for staging
  a participant subtree and should be reused; a second participant owner is unnecessary.
- A related commit dependency must be resolved for that preparation to survive: `HumanCommitter`
  currently admits the destination, then source retirement later applies departure. Those separate
  policy revisions differ from the complete post-transfer candidate used for readiness. Install
  that exact final snapshot through one barrier, while the eventual lifecycle keeps media held.
  This checkpoint adds the policy operation; it does not yet change the human handoff sequence.
- Three focused checks first failed at the missing `Authority.commit_candidate/3` API
  (`vxpipe-candidate-commit-red.log`). The new operation revalidates the candidate inside its owner,
  uses the original absolute phase deadline to bound enforcer acknowledgement, and publishes the
  exact complete membership only after success. An expired request changes nothing; failed/late
  acknowledgement stops the authority because partial policy installation cannot be assumed safe.
- All 17 authority checks pass (`vxpipe-candidate-commit-green.log`). The deadline check uses a
  one-second phase budget with a five-second fixture enforcement budget and a bounded two-second
  caller wait, so using the enforcement budget instead of the original phase budget would fail.
  Existing production deadlines are unchanged. No additional test-only timing workaround was needed.
- The real WebRTC candidate-recording check now adopts through this API and refreshes the entire
  collected graph before releasing output. Both focused WebRTC files pass eight tests
  (`vxpipe-candidate-commit-gateway.log`). This verifies prepared resource adoption, not yet private
  destination admission or final transfer completion. Root gates follow.
- Resume detail from the private STT path: `SpeechToText.State.new/1` starts a transport immediately.
  Registering a new destination capability against a base policy where it is absent would then stop
  that transport before candidate preparation starts another. Private initialization therefore needs
  to avoid that preliminary connection, while retaining the existing prepared-session path. Ordinary
  STT binding also opens ingress when opening audio is complete, so its private counterpart must keep
  ingress closed. No STT constructor, private binding or Gateway media allocation was changed here.
- Final root verification passes all five gates: formatting, warnings-as-errors compilation,
  strict Credo, 1,251 tests with zero failures and 15 integration exclusions, and unused dependencies.
  All eight application suites completed; every entry in `vxpipe-candidate-commit-root-results.json`
  is exit zero. All 51 local documentation links/anchors and `git diff --check` pass. No new fixture
  fix, package change, production timeout increase, browser/provider session or server restart was
  required. Keep milestone/index acceptance open and commit the policy operation, focused checks
  and documentation together.

## Private STT initialization and cancellation ownership

This is the requested notes update after `69b5ad6`. It records the current implementation attempt
and source investigation; this documentation checkpoint does not complete or commit that code.

- **Why initialization needs groundwork:** the ordinary STT constructor opens its transport
  immediately. A private joining participant is absent from the installed policy, so applying
  that policy would close the new session before candidate preparation creates another. This
  extra connect/close/connect cycle is avoidable and consumes the existing handoff budget.
- **Current uncommitted change:** an internal `initial_policy` option determines whether the
  constructor allocates a transport. Omission preserves ordinary startup. A valid policy with no
  speech demand leaves the transport absent; later policy demand starts the existing asynchronous
  connector and still requires the provider acknowledgement. The initial snapshot is only an
  allocation input: normal enforcement installs the actual policy. Storing it as already installed
  would conflict with the existing rejection of duplicate policy revisions during registration.
  Invalid initial policy is rejected before starting a transport. This adds no call-definition field.
- **Observed focused evidence:** `vxpipe-private-stt-initial-red.log` records 12 tests and one
  intended failure because a provider connection started without demand. The retained green run,
  `vxpipe-private-stt-initial-green.log`, has 12 tests and zero failures. It proves deferred startup
  and acknowledged readiness at the capability boundary, not private room admission or transfer.
- **Current failing boundary:** `vxpipe-private-stt-pair-red.log` completed with 14 tests and one
  failure: `RoomCapabilitySupervisor.start_speech_to_text/8` does not exist. The new test proposes
  passing the initial policy to a supervised capability/ingress pair, preparing one provider session,
  and keeping microphone ingress closed through adoption. Execution stops at the missing API, so
  its later readiness, retention and closed-input assertions have not passed.
- **Ownership problem found in review:** that draft test registers both private actors with
  `Authority.register_enforcer/3`. Registration installs a critical monitor; losing any registered
  enforcer stops the authority. Stopping a cancelled private pair through its supervisor would
  therefore stop the room's policy authority. This follows from the registration and `:DOWN`
  handlers; it is not a newly reproduced phone failure or a verified cancellation fix.
- **Proposed next boundary, not implemented:** keep the staged pair under the phase owner and
  original deadline, apply the base policy locally, and include the new actors in the final
  candidate enforcement barrier before promoting them to critical enforcers. Cancellation before
  commit must clean up only the staged pair and preserve the source. Existing participant subtree
  preparation and supervisor cleanup should be reused. A separate pending-enforcer registry would
  duplicate ownership; simply forwarding the constructor option would leave cancellation unsafe.
  This proposal still needs focused failure evidence and a durable contract before implementation.
- **Resume checks:** first correct the draft test's premature registration. Prove cancellation and
  phase-owner loss preserve the source, then prove adoption retains the exact prepared provider
  generation while ingress stays closed until explicit release. Capture the source resource before
  preparation to check exact retention, and construct fresh audio frames for each push so stale
  fixture timestamps cannot masquerade as closed ingress. The full connection authorization and
  persistent phase ownership remain separate integration requirements.

At this snapshot, four code/test files are uncommitted: the STT capability, its state module,
`capability/speech_to_text_test.exs`, and `speech_to_text_media_policy_room_test.exs`. They are
preserved outside this notes commit. No new implementation or test was added during this notes
update, and no root suite was rerun. Re-reading `vxpipe-candidate-commit-root-results.json` confirms
five exit-zero commands; the eight test summaries total 1,251 tests, zero failures and 15 excluded
integrations. Those results belong to `69b5ad6`, not the current worktree. No dependency upgrade,
production deadline change, browser/provider session or server restart was performed.

The milestone and index remain open. Startup, human/AI handoff, waits, cues, release acknowledgements,
bounded recovery and browser/phone acceptance still need a runnable integrated slice. More passing
component checks must not be presented as resolution of the reported phone/console transfer problem.

Documentation verification for this update: all 38 local labnote links/anchors resolve, and
`git diff --check` passes.

## Adopt private speech through the policy barrier

- The preceding goal turn made progress by committing the requested notes as `fb0fd11`.
  Revalidated the four uncommitted STT files before resuming. The constructor and room-supervisor
  work below complete the preparation/adoption boundary; connection authorization and persistent
  phase ownership still need lifecycle integration.
- Three new authority checks first failed at the missing `commit_candidate/4` operation
  (`vxpipe-private-enforcer-red.log`: 20 tests, three failures). The optional new-enforcer list
  joins the final barrier, deduplicates existing/new actors and stores critical monitors after
  acknowledgement. Invalid/expired requests do not register actors; failed application closes the
  authority. All 20 checks then passed in `vxpipe-private-enforcer-green.log`.
- The room supervisor now forwards the internal initial-policy option. Corrected the draft pair
  test to apply its base policy locally rather than register private actors as critical before
  commit. Candidate preparation starts one provider session, waits for its acknowledgement, binds
  the prepared input, and adopts through the combined barrier with microphone input still closed.
  The source's exact readiness resource is retained, and fresh frames verify the admission gate.
- Added explicit discard, supervised pair cleanup, retained source audio and another preparation.
  Its first run incorrectly expected the fake transport's graceful-close notification; asynchronous
  prepared connectors terminate their linked transport. The check now monitors actual termination,
  consistent with the existing prepared-session cancellation checks. This was a fixture expectation
  error, not a production cancellation defect. That intermediate run had 27 tests and one failure
  in `vxpipe-private-speech-pair-green.log`.
- The durable resource contract records the ownership decision: reuse the phase owner and final
  policy barrier instead of adding a pending-enforcer registry. This component API does not itself
  authorize a private connection or clean up the whole allocated pair on preparation-worker loss.
  Those responsibilities remain explicit requirements for the persistent lifecycle owner. No
  package version or production timeout was changed. Final focused and root verification follow.
- All 47 focused authority, speech capability and room-policy checks pass in
  `vxpipe-private-speech-focused.log`. Formatted the exact changed Elixir files and started all five
  root gates under `vxpipe-private-speech-root-`, retaining per-command result codes for recovery.
  Preserve concurrent `vxpipe-docs/artwork/` and its separate visual-task labnote.
- The first full root run passed all five gates with 1,257 tests and 15 integration exclusions.
  Final source review found that a candidate with unchanged membership would send the installed
  revision to enforcers again; real enforcers reject that stale revision. A new check reproduced
  the unnecessary application (`vxpipe-private-speech-unchanged-red.log`: 21 tests, one failure).
  An unchanged candidate now preserves registered actors without reapplication. Supplying new
  actors with that unchanged candidate is rejected before mutation: private transfer destinations
  require an actual membership transition, while ordinary initial registration retains its API.
  This avoids inventing a revision or weakening stale-policy rejection. Repeat root gates for
  this final runtime correction; the earlier full run is not evidence for the changed worktree.
- Final focused verification passes 48 checks (`vxpipe-private-speech-final-focused.log`).
  The final root run uses `vxpipe-private-speech-final-root-`; formatting, compilation and strict
  Credo have passed, and the full suite is running. No further runtime changes were made after
  starting that run.
- That root test command finished with one failure in the existing recorder preparation case:
  `RoomMixer.flush_through/2` returned `unavailable` on the first source frame, before policy
  adoption. All new speech/authority checks passed. The default flush call is bounded at one
  second, but its generic error does not distinguish scheduling timeout from process loss; do not
  claim a cause from this output alone. Run the recorder file in isolation before deciding whether
  any correction is warranted. Preserve this failed root evidence and do not increase production
  deadlines to make the test pass.
- The unchanged recorder file passes all eight checks in isolation
  (`vxpipe-private-speech-recording-isolated.log`). Re-run the complete umbrella suite with the
  failed run's seed, `262903`, followed by the unused-dependency check, under
  `vxpipe-private-speech-verified-root-`. Formatting, compilation and strict Credo already passed
  against the same unchanged code in the preceding root run. No fixture or runtime change is
  justified by the isolated result alone; the flush failure's cause remains unconfirmed.
- Final verification passes all five root gates on the unchanged code. Formatting, compilation
  and strict Credo are exit zero in `vxpipe-private-speech-final-root-results.json`; the same-seed
  full-suite rerun and unused-dependency check are exit zero in
  `vxpipe-private-speech-verified-root-results.json`. All eight application suites completed:
  1,258 tests, zero failures and 15 integration exclusions. The recorder failure did not recur;
  no fixture, dependency or production timeout was changed to obtain that result.
- All 56 local documentation links/anchors and `git diff --check` pass. Commit this coherent speech
  initialization/adoption boundary with its checks and docs, preserving the concurrent visual work.
  The next integration must bind private actors to the authorized transfer connection and persistent
  phase owner, then use the complete readiness/cue/release sequence before publishing success.
  No browser session, live provider call or development-server restart was performed; milestone
  acceptance and the index entry remain open.

## Bind private allocation to its phase

- The preceding goal turn made progress with `a8106d4`, verified by all five gates. Revalidated
  that only the concurrent visual-task files were dirty. The next connection binding needs to
  cover the interval between allocating a private pair and starting provider preparation: existing
  provider leases begin too late and close only pending sessions, not the allocated actors.
- Reused the STT actor's temporary child lifecycle and ingress's existing capability monitor.
  An internal allocation lease can stop both actors without adding a supervisor, owner process or
  registry. The lease pins the original phase owner, attempt and deadline from construction;
  successful prepared-session adoption removes it, leaving the live policy enforcers responsible
  for ordinary failure handling. Connection authorization must still supply this trusted scope.
- Two focused checks reproduced owner loss before provider preparation and deadline expiry leaving
  the pair alive (`vxpipe-private-allocation-red.log`: 17 tests, two failures). A third reproduced
  accepting a different preparation attempt before a pending provider existed
  (`vxpipe-private-allocation-scope-red.log`: 18 tests, three failures).
- The new allocation lease closes pending work explicitly on owner loss/expiry, and validates
  preparation owner, attempt and deadline before provider startup. Admission requires an actual
  prepared session; the same provider resource survives adoption and later phase-owner shutdown,
  while microphone ingress remains closed. The initial green run passes 18 checks in
  `vxpipe-private-allocation-green.log`.
- Review then reproduced an empty, no-demand preparation being admitted as a new live enforcer
  (`vxpipe-private-allocation-demand-red.log`: 19 tests, one failure). A private allocation must
  have a prepared replacement session before adoption; no-demand actors remain private and must
  be discarded by selection/phase cleanup. This prevents an unused actor's allocation deadline
  from later becoming a critical room failure. Final focused verification follows.
- The expanded focused run passes 52 checks (`vxpipe-private-allocation-focused.log`). Added one
  further private-membership refresh check: it passes immediately without a policy-reconciliation
  change. Existing scoped signatures already retain the session and retarget its future interval;
  the check proves compatibility with the new allocation lease, not a newly fixed reconnect defect.
  Its initial log name is `vxpipe-private-allocation-refresh-red.log`, but the actual result is
  20 tests, zero failures. The durable contract records the lifetime decision and remaining
  connection/coordinator integration. Final combined checks and root gates follow.
- Final combined coverage passes 53 checks (`vxpipe-private-allocation-final-focused.log`). Root
  verification under `vxpipe-private-allocation-root-` has passed formatting, compilation and strict
  Credo; the umbrella suite is still finishing. Per-command results and code hashes are retained.
- Concrete coordinator resume point: the existing `RoomTransferSupervisor` already owns the
  destination preparation task, but that task returns after configuration, leaving `Pending.task.pid`
  unsuitable as the later phase owner. Reusing that supervised task as a persistent phase, sending
  a typed prepared notification instead of returning, would keep one owner through readiness,
  cues and release. Its existing monitor and original deadline must remain until completion;
  current settle/commit paths release them too early. This is a proposed integration step, not an
  implemented coordinator. It avoids an additional owner process or lookup registry, and enables
  RoomAuthority to authorize private binding against the exact pending phase PID.
- Final root verification passes all five commands: formatting, warnings-as-errors compilation,
  strict Credo, 1,263 tests with zero failures and 15 integration exclusions, and unused dependencies.
  All eight application suites completed; every retained command result is exit zero. No fixture
  correction, package change or production timeout increase was needed for this checkpoint.
  All 58 local documentation links/anchors and `git diff --check` pass. Commit the allocation
  lifetime, focused checks and contract together,
  preserving the concurrent artwork and visual-task labnote. No browser/provider session or server
  restart was performed; full lifecycle integration and milestone/index acceptance remain open.

## Phase-owner integration findings

This documentation follow-up records source inspection after `c005511`. No runtime changes or
new tests were made. The existing detour audit and checkpoint sections remain the evidence for
completed work; the integration steps below are still proposals.

- `RoomTransferSupervisor.prepare/8` runs `DestinationPreparer.prepare/7` as a task that returns
  after destination configuration. `Pending.task.pid` therefore cannot own subsequent readiness,
  cues and release. This matters because the private speech allocation now closes when its phase
  owner exits. Wiring allocation directly to the current short-lived task would cancel it too soon.
- `ParticipantTransfer.prepared/3` removes the preparation monitor. The agent path also cancels
  the deadline timer immediately; the human path keeps the timer until acceptance and briefing
  finish, then cancels it before commit. A persistent phase must retain ownership and the original
  absolute deadline through the remaining handoff, without giving each stage a fresh timeout.
- Reusing the existing supervised task with a typed preparation notification remains the proposed
  approach. That notification would mean configuration finished, not that all capabilities are
  ready. The task would stay alive through final adoption and release, avoiding a separate owner
  process or registry. Private connection binding would still require authorization against the
  exact pending phase, attempt and connection.
- Keeping that task alive also changes failure routing. The current matching task-DOWN branch uses
  generic destination cleanup/restoration. A prepared human destination needs `HumanHandoff` cleanup
  for its private connection, briefing speech and possible outbound leg. Every terminal path must
  settle the retained task and timer; simply extending task lifetime would leave this incomplete.
- Both committers currently publish completion internally. The human committer queues connection
  promotion, and the agent committer starts the first message. Neither waits for the planned
  all-listener cue and release acknowledgements. The coordinator must retain ownership through
  adoption and publish success only after that sequence; owner loss or expiry after partial commit
  must not be reported as a successful transfer.
- Early human acceptance is still latched before briefing completes. Enforcing the approved
  acceptance window, integrating startup/transfer waits and recovery, and completing browser/audio
  acceptance remain outstanding. These findings do not establish the cause of any new live-call
  failure or demonstrate that the end-to-end milestone works.

Verification for this follow-up: cross-checked the supervisor, preparation settlement, worker-DOWN,
human cleanup and both commit paths against the current source; checked local Markdown links and
anchors and `git diff --check`. The 1,263-test result above belongs to `c005511`; no runtime suite,
browser/provider session or server restart was performed for this documentation-only update.

## Retain the actual transfer phase

- The preceding turn committed the source-only integration findings as `ab5d3ff`. That is progress
  in the requested detour accounting; the active milestone still requires runtime integration.
  Revalidated the worktree and preserved the concurrent artwork and its separate labnote.
- Added real human-transfer checks for phase scope through briefing, rejection of completion by a
  non-owner, cleanup after owner loss, and owner termination after successful handoff. The initial
  run fails because the phase API is absent (`vxpipe-transfer-phase-red.log`: seven tests, two
  failures). The existing supervised task now sends a typed preparation notification and remains
  alive under the original authority, attempt and deadline. The same seven checks pass in
  `vxpipe-transfer-phase-green.log`; two compiler warnings remain for the refactor pass.
- Human owner-loss handling now uses the existing human cleanup path, including the private
  connection and briefing speech. A separate real-room check blocks policy adoption at an actual
  enforcer and kills the phase before acknowledging adoption. This targets the previously documented
  risk of publishing success inside the committer before the phase can acknowledge completion.
  The red run emitted a `ToolCallCompleted` before a failed phase acknowledgement crashed authority
  (`vxpipe-transfer-phase-commit-red.log`: eight tests, one failure). Both committers now return
  control to a common completion boundary, which checks the phase before publishing success or
  starting the first message. Failure after mutation exits authority with `shutdown`, closing its
  incarnation rather than claiming a recoverable handoff.
- The combined room run exposed an old agent fixture that used task exit as configuration evidence
  (`vxpipe-transfer-phase-rooms.log`: 19 tests, one failure). It now waits for the phase's prepared
  scope, then kills the actual destination as before and verifies failed-transfer cleanup ends
  the phase. No failure assertion or production deadline was relaxed.
- Strengthened the existing one-second deadline case by suspending room authority after private
  attachment/acceptance and observing the actual phase exit before resuming authority. This proves
  the original budget survives configuration independently of the authority's receive loop. The
  19 combined agent/human web checks pass in `vxpipe-transfer-phase-rooms-green.log`. Removed the
  obsolete settlement helper and unused binding; expanded phone and root verification follow.
  Full readiness/wait/cue/release integration is still outstanding.
- All 22 focused agent, human web and human phone checks pass in
  `vxpipe-transfer-phase-focused.log`. Root checks run sequentially under
  `vxpipe-transfer-phase-root-`, with per-command exit codes and source hashes retained. No package
  or production timeout changed. No rendered browser, live-provider session or server restart was
  performed; those full-milestone acceptance gates remain open.
- Final root verification passes all five commands: formatting, warnings-as-errors compilation,
  strict Credo, the full suite and unused dependencies. All eight application suites completed:
  1,265 tests, zero failures and 15 integration exclusions. Every retained command result is exit
  zero, and all ten changed/new code and test files match their hashes from the start of the run.
  The 60 local documentation links/anchors and `git diff --check` pass. Commit the phase lifetime,
  completion ordering, focused checks and documentation together, preserving concurrent visual work.
- The next integration can authorize private connection preparation against the now-live
  `Pending.task.pid` and its original scope. It must keep destination input closed, collect the
  full candidate room graph, and compose holds/waits/cues/adoption/release before invoking the
  completion boundary. Keeping the task alive does not itself perform these steps. Early acceptance,
  startup waiting, restoration and rendered/provider acceptance remain unfinished.

## Bind private speech to the authorized connection

- The previous goal turn made progress with `4801597`: a persistent transfer task, real-room
  failure checks and all five gates. Revalidated that only the concurrent visual-task files were
  dirty before beginning this checkpoint.
- The ordinary speech binding immediately registers critical enforcers and opens ingress. The
  private lane needs a separate internal authority operation: validate the exact live transfer and
  owning connection, allocate from the destination's resolved profile with no provider connection,
  apply the installed base policy locally, and retain closed ingress under the original phase lease.
  Allocating these dormant actors locally avoids passing caller-supplied actor PIDs into an
  authorization boundary; network provider preparation remains outside authority.
- Two real-room checks fail because the private allocation API is missing
  (`vxpipe-private-speech-binding-red.log`: ten tests, two failures). The initial implementation
  passes those ten checks in `vxpipe-private-speech-binding-green.log`, including idempotent exact
  binding, foreign identity/connection/attempt rejection and phase cancellation. This does not yet
  wire Gateway or the complete coordinator to use the internal operation.
- Extending the binding check through acceptance/briefing targets the existing committer's unsafe
  interaction with an allocated private pair: allocation must not be treated as readiness or permit
  ordinary promotion to bypass prepared adoption. The check also starts the actual pending provider
  under the same phase and requires private capability loss to fail the attempt while preserving
  the source. The red run published `ToolCallCompleted` for that unadopted private pair
  (`vxpipe-private-speech-commit-guard-red.log`: ten tests, one failure). An allocated private pair
  now keeps the attempt pending for the prepared-media path; direct commit cannot stand in for
  readiness/adoption. Private speech failures use the human attempt's cleanup instead of the
  ordinary main-connection unavailable path. Ten checks pass in
  `vxpipe-private-speech-commit-guard-green.log`.
- Expanded checks cover both actor termination and the capability's unavailable event, absence of
  a destination STT profile despite enabled application STT, ordinary activation rejection and late
  calls after cancellation. The 46 combined transfer and speech room checks initially pass in
  `vxpipe-private-speech-binding-focused.log`.
- Review exposed a second gate: `ConnectionLifecycle.open_inputs/1`, used by startup/opening
  completion, opened the new private ingress. The two failure variants reproduce this in
  `vxpipe-private-speech-open-inputs-red.log` (12 tests, two failures). That operation now opens
  only main-admitted connections. Private allocation neither grants microphone access nor changes
  the ordinary source input. Final focused/root verification follows. No package or production
  timeout was changed; Gateway/full coordinator activation and successful prepared handoff remain
  unfinished.
- Final ownership review reproduced cleanup leaving a second private connection attached to the
  same transfer (`vxpipe-private-speech-connections-red.log`: 12 tests, one failure). Cancellation
  now removes every private connection with that exact attempt ID, preserving main connections.
  This is observed cleanup behavior, not evidence for the cause of the earlier live-browser failure.
- All 46 focused agent, human web/phone and speech-policy room checks pass against the final code
  in `vxpipe-private-speech-binding-verified-focused.log`. Root gates run sequentially under
  `vxpipe-private-speech-binding-root-`, retaining per-command results and source hashes. No browser,
  provider session or development-server restart was performed.
- Concrete Gateway resume point: WebRTC `ConnectionPeerSupervisor.start_room_audio_ingress/4` and
  `start_room_audio_egress/5` ask ordinary engine configuration and register new actors immediately.
  Private attachments currently receive disabled modes and therefore have no room media actors.
  The next coordinator path must create dormant actors outside critical registration, bind this
  private ingress, and expose the prepared output subscription for candidate collection. It cannot
  reuse ordinary main-media activation, which assumes admission has already happened.
- Final root verification passes all five commands: formatting, warnings-as-errors compilation,
  strict Credo, the full suite and unused dependencies. All eight application suites completed:
  1,269 tests, zero failures and 15 integration exclusions. Every retained result is exit zero;
  all seven changed/new code and test files match their hashes from the start of verification.
  All 61 local documentation links/anchors and `git diff --check` pass. No dependency, fixture
  timeout or production deadline was changed. Commit the internal private binding, gates, failure
  cleanup and evidence together while preserving the concurrent visual work. Full milestone and
  index acceptance remain open.

## Gateway preparation detour and current boundary

This update answers the request to keep the detours in the labnote. It records the existing
uncommitted implementation and retained test results; it does not resume runtime editing or claim
that this checkpoint is ready to commit with the implementation.

- **Why this groundwork is needed:** ordinary Gateway setup asks the engine for admitted room
  media configuration and immediately registers its actors as critical policy enforcers. Private
  transfer attachments deliberately have disabled room input/output modes, so that setup creates
  no room actors. Calling ordinary activation would conflate allocation with admission; merely
  allocating engine speech would leave the decoder and room output missing from readiness.
- **Current approach:** the actual WebRTC connection or phone media session requests preparation
  from authority. Authority reuses private speech authorization and returns the installed base
  policy, mixer configuration and original phase scope. Gateway allocates dormant room ingress
  and egress under the existing connection supervisor, without starting their pipelines or live
  subscription. The attachment retains disabled room permissions and closed speech input while
  readiness can describe the future output subscription. The existing native output is retained.
- **Ownership decision:** reuse the connection supervisor and existing phase-cancellation path
  instead of introducing another owner process or registry. A repeated authorized request reuses
  actors. Partial allocation failure stops the private connection so its supervisor owns cleanup.
  The latter failure path and policy-refresh branch still need focused verification.
- **Observed evidence:** `vxpipe-private-gateway-media-red.log` reports three tests with one
  expected failure for the missing `Connection.prepare_transfer_media/2` operation. The completed
  `vxpipe-private-gateway-media-green.log` reports three tests with zero failures. The new real
  WebRTC check covers stale-attempt rejection, repeated allocation, retained native output,
  dormant pipelines, disabled room permissions, no provider startup or caller audio leakage, and
  actor cleanup after phase loss while the caller remains ready. It does not exercise successful
  prepared-media adoption or a complete handoff.
- **Still unverified:** the phone callback exists in the current diff but this focused run does
  not cover it. Complete candidate collection using these actors, partial-construction cleanup,
  refreshed policy, and successful adoption/promotion need verification. The five umbrella gates
  have not been run for this Gateway diff. The 1,269-test result above belongs to `5ab8c17`.
- **Remaining integration:** no lifecycle coordinator calls this new preparation operation yet.
  Startup waiting, the acceptance window, all-listener holds/waits/cues, final policy and control
  adoption, acknowledged release, restoration and rendered/audio acceptance remain open. The
  milestone and index remain unchecked; this preparation API is not the requested finished flow.
- **Dependency and environment accounting:** these Gateway changes add no package or lockfile
  change and do not increase the original transfer deadline. No new provider/browser session or
  development-server restart was performed for this notes update. Concurrent visual documentation
  changes and the existing implementation/test diff are outside this documentation commit.

Notes verification: compared this account with the current engine/Gateway diff, the completed red
and green log summaries, and the milestone's unchecked acceptance tasks. Checked local Markdown
links/anchors and whitespace. No new tests were written or run for this documentation update.

## Integrate private Gateway preparation

- The preceding notes-only turn made progress with `83156d9`. Revalidated the current worktree
  and resumed the existing implementation while preserving the separate visual documentation work.
- Extended the real WebRTC check through complete prospective room preparation: remove the source
  from future membership, include caller and destination, hold outputs and collect actual resources
  under the original phase scope. Delayed destination STT keeps the collector preparing; its
  acknowledgement permits readiness without admission. Caller pipelines and source capabilities
  remain unchanged, and discarding preparation ends the pending provider. The first run failed on
  a new fixture's nonexistent `deliver_control/2` helper; changing it to the existing `deliver/2`
  produced a passing check (`vxpipe-private-gateway-candidate-green.log`). That initial failure is
  not evidence of a production defect.
- Added Telnyx and Twilio private decoder/output checks with no selected STT. The simulated socket
  now optionally reports its exact bound transport and acknowledges the existing playback-mark
  protocol. The first combined run rejected duplicate subscription resources supplied by the test;
  deduplicating identical descriptors matches the whole-room runner's existing collection behavior.
  All six phone checks pass in `vxpipe-private-gateway-phone-green.log`. They prove Opus/PCMU media
  preparation, not STT support for either format or live phone playback.
- Review identified an STT-dependent completion guard. A real engine check with no destination STT
  reproduced `ToolCallCompleted` after allocation but before prepared adoption
  (`vxpipe-private-gateway-no-stt-red.log`: one test, one failure). Authority now records private
  room-media preparation independently of speech, and the human commit guard covers either.
  All 12 human web engine checks pass in `vxpipe-private-gateway-no-stt-green.log`.
- Abrupt private ingress/egress loss did not notify the connection because these dormant actors
  were intentionally outside critical registration. The real WebRTC variants reproduced both
  missing cleanup paths (`vxpipe-private-gateway-actor-loss-red.log`: five tests, two failures).
  The connection now monitors its private actors and uses its existing shutdown/failure path.
  Eleven combined web/phone checks pass in `vxpipe-private-gateway-actor-loss-green.log`.
- A subsequent policy-refresh check exposed another concrete dependency: an absent participant's
  default audio-input interval changes with the room revision. Ordinary ingress enforcement
  interpreted that as a request to launch its missing decoder even though input remained
  undemanded (`vxpipe-private-gateway-refresh.log`: 11 tests, three failures). Such a dormant input
  now updates policy without starting a decoder. The refresh preserves every private actor,
  starts no speech provider, and the complete graph can still prepare afterwards. All 24 combined
  Gateway transfer and input-policy checks pass in `vxpipe-private-gateway-refresh-green.log`.
- No dependency version, production deadline or application configuration changed. The extra
  failures above distinguish project integration defects from new test-fixture errors. Full
  lifecycle invocation and prepared adoption remain outstanding; the currently automatic handoff
  still uses its earlier path. No browser/provider session or development-server restart was used.
  Formatting, broader focused verification and the five root gates follow before implementation
  commit. The milestone/index acceptance boxes remain open.
- Final focused verification passes 46 engine checks (`vxpipe-private-gateway-engine-focused.log`)
  and 46 Gateway checks (`vxpipe-private-gateway-verified-focused.log`). All five root commands pass
  under `vxpipe-private-gateway-root-`: formatting, warnings-as-errors compilation, strict Credo,
  all eight application suites and unused dependencies. The full suite reports 1,274 tests,
  zero failures and 15 integration exclusions. Per-command exit codes are retained, and all 15
  changed/new code and test files match their hashes from the start of root verification.
  Local documentation links/anchors and `git diff --check` pass. Commit implementation, focused
  checks, contract and labnotes together; preserve the concurrent visual documentation work.
- Concrete integration boundary for resuming: the owning connection now accepts
  `{:vxpipe_prepare_transfer_media, attempt_id}` and candidate collection can use its dormant
  actors. The persistent phase must invoke it, select enforcers by actual future demand, and
  coordinate all listeners through waits, readiness, cues, held policy/control adoption and
  acknowledged release. Existing committers still discard source TTS and schedule source teardown
  during commit, while Gateway promotion still calls ordinary media startup. Those paths must use
  the prepared actors and retain source resources until the required completion point. The
  current successful preparation/discard checks do not establish successful adoption or release.

## Coordinate the live human handoff

- The previous turn committed `c4fea8c` with all five gates and 1,274 passing tests. That was
  progress on private Gateway preparation; the automatic handoff still used ordinary promotion.
  Revalidated the worktree and preserved the separate visual documentation changes.
- Added an actual WebRTC transfer check using normal acceptance, with wait slots explicitly nil.
  It requires destination STT to start while admission and room policy remain private, retains
  the source transport until handoff finishes, and requires the same prepared actors after main
  admission. The initial run fails at the intended boundary: destination admission is already
  `:main` when its STT transport starts (`vxpipe-human-ready-handoff-red.log`: one test, one
  failure). The existing component checks do not prove this automatic lifecycle ordering.
- Source inspection confirms the integration points: `HumanHandoff.progress/2` still selects the
  immediate committer; that committer discards source TTS, schedules source removal, and only then
  signals Gateway ordinary media startup. The persistent phase, complete candidate runner and
  dormant Gateway actors now exist, but those pieces must replace this sequence. This section
  records ongoing work, not a completed or fully verified checkpoint.

### Why the prepared components have not completed the handoff

| Integration finding | Consequence and remaining work |
| --- | --- |
| The private preparation API exists, but normal acceptance does not invoke it. | Wire the actual transfer phase to prepare and collect destination media before admission. The failing WebRTC check exercises this missing connection between components. |
| `HumanCommitter` uses ordinary participant admission, discards source TTS and queues promotion after source teardown. WebRTC and phone promotion then start ordinary media. | Adopt the exact prepared membership and existing media actors while held; retain source resources until the handoff reaches its completion boundary. A passing preparation/discard check does not prove adoption. |
| `Completion.finish/3` synchronously asks the persistent phase to finish before publishing success. | A phase that synchronously asks authority to complete would introduce a call cycle. The orchestration must leave the phase responsive to authority while coordinating preparation and completion. This is a design constraint identified by inspection, not an implemented fix. |
| Acceptance currently latches before briefing completes; completion has no coordinated cue/release acknowledgements. | Enforce the approved acceptance window and compose readiness, listener cues, held adoption and acknowledged release under the original deadline. Startup waits and bounded recovery remain additional unfinished milestone work. |

This notes update adds no runtime changes, dependencies, lockfile changes or deadline increases.
It preserves the existing failing test and the separate visual documentation work. No tests were
added or run for this documentation update, and no development server or provider session was
restarted. Verification compares the account with the current source, the retained one-test
failure, the five successful `c4fea8c` gate results and the milestone's unchecked acceptance tasks.
All 46 local Markdown links/anchors and the documentation whitespace check pass.

## Wire normal acceptance through prepared media

- Previous goal turn: progress, committed the requested detour accounting as `6f9455a`. Revalidated
  the existing failing WebRTC test and kept the concurrent visual work separate. This turn resumes
  implementation; it does not redefine the full milestone around that one reproduction.
- Normal human acceptance now asks the persistent phase to supervise preparation outside authority
  and Gateway message loops. The phase stays responsive to scope/completion requests, and links
  its supervised worker so abrupt phase loss cannot leave it running independently. Workers retain
  the original attempt deadline and lease prepared resources to the phase.
- The new flow invokes private preparation on actual owning connections, captures all connections
  in the prospective membership, gates input/output, starts participant-local waits, collects the
  complete prepared graph, stops/clears waiting, and awaits each mandatory local cue. It refreshes
  readiness and validates the captured room before the policy/control commit. This currently begins
  after acceptance/briefing; immediate audience waiting at authorization remains unfinished.
- Human commit uses the exact prepared candidate and registers only enforcers present in the
  required resource set. Participant installation checks that committed snapshot instead of creating
  another admission revision. Gateway adoption updates attachments on existing actors; it does not
  call ordinary pipeline startup. Release rechecks ready resources, opens the prepared outputs and
  input gates, and acknowledges before completion. Source TTS is retained until completion; source
  participant cleanup recognizes its already-committed departure. Removed the old human committer.
- The first wiring run appeared green, but compilation reported an alias declared below its use.
  That caused completion to crash authority after sending `transfer.active`; source shutdown alone
  let the original test pass. Added the missing surviving-room assertion, observed the expected
  failure (`vxpipe-human-handoff-completion-red.log`), fixed alias scope, and reran successfully
  (`vxpipe-human-handoff-completion-green.log`). The earlier apparent green is insufficient evidence.
- A held-text check exposed the missing model-admission gate. The fixture initially expected the
  sideband error type instead of RTVI's `error-response`, then incorrectly counted a continuation
  of the original source request as a newly admitted held request. Corrected both fixture assumptions
  and bound the assertion to the held request's correlation. That check now passes in
  `vxpipe-human-handoff-held-text-correlated.log`. Held input cannot interrupt/cancel the transfer;
  held model output and caller-idle eligibility are also gated. Broader gate/race coverage remains.
- The older WebRTC integration check awaited activation before delivering its simulated provider's
  Connected acknowledgement. It now acknowledges STT before activation and expects ready media
  afterwards. Its later independent preparation exercises also use a fresh output generation rather
  than resetting a transferred output to generation one. All six WebRTC checks pass in
  `vxpipe-human-handoff-web-updated.log`, including the existing transcript/recording integration.
- Broader focused runs expose outstanding embedded connection fixtures: they attach the ExUnit
  process as the connection and cannot answer the required preparation/readiness protocol. The
  engine human web/phone run has five failures out of 15; the earlier Gateway web/phone run has
  three failures out of 12, of which the WebRTC provider-order failure is now corrected. These need
  proper simulated connection adapters and updated completion assertions; do not add a production
  bypass that considers an unsupported connection ready.
- Remaining runtime concerns include recovery after a held preparation failure, the server-side
  acceptance window, audience holds before destination preparation, participant/multiple-connection
  changes during the attempt, removal of selected-but-undemanded private speech, and corresponding
  agent/startup orchestration. Phase loss currently closes a held connection; this does not implement
  the required bounded source recovery. Complete acceptance, live browser/audible checks and the
  milestone/index checkboxes remain open.
- Formatting, warnings-as-errors compilation, strict Credo and unused dependencies pass. The full
  umbrella run completed with exit 2 in `vxpipe-human-handoff-root-test.log`: 1,275 tests, nine
  failures and 15 exclusions. Five failures are in engine human-transfer checks, two in outbound
  phone checks, and two additional failures in the actual Telnyx/Twilio incoming-call harnesses.
  Those harnesses wait for source retirement and require diagnosis; do not assume all failures are
  fixture-only. The other six application suites pass. This is not a committable checkpoint yet.
  No dependency versions, lockfiles, production deadline values or server processes were changed
  or restarted. Complete the remaining implementation and verification before committing.

## Phone diagnosis and vertical delivery review

### Remaining phone integration failure

- The existing incoming Telnyx/Twilio harnesses invoked media socket callbacks from the test
  process. Updated their supervised socket fixture to own and execute the real callbacks,
  retain socket state, deliver outbound frames and echo playback marks through the real parser.
  Provider mark envelopes require Telnyx stream/sequence fields and Twilio sequence numbers;
  the first fixture revision omitted those fields and failed before meaningful handoff evidence.
- Added handling for the actual four-element normal close callback and supplied the simulated
  source STT Connected acknowledgement before its transcript events. With those fixture issues
  corrected, both harnesses still fail during preparation with
  `media_connection/unsupported_audio`. The retained `vxpipe-human-handoff-phone-cause.log`
  reports two tests and two failures. This is a remaining media integration issue, not evidence
  that all current phone failures can be fixed by increasing test waits.
- A temporary trace printed only the safe preparation scope/reason to locate that boundary.
  Removed it after diagnosis. No production workaround, provider downgrade, dependency change or
  deadline change was made. The phone fixture edits and human handoff runtime remain uncommitted;
  no full root run after these fixture edits is claimed.

### Delivery-plan review, separate from implementation progress

- The user requested the milestone document be split into checkpoints and concrete tasks first,
  with a curated account of work already done. Paused runtime editing for this documentation step.
  The preceding status response changed no implementation state; this step changes the actual
  delivery document and records the evidence needed to resume the first runnable slice.
- Replaced the component-first checklist with five runnable checkpoints: human web handoff, AI
  handoff, initial caller waiting, phone handoff parity, and changing/multiple listeners. Each
  contains implementation tasks, user-observable acceptance, failure handling, relevant diagnostics,
  verification and a coherent commit. Dependencies follow the existing contracts and prepared
  components; no generic framework or additional prerequisite milestone was introduced.
- Human web acceptance remains first. Its existing phone/embedded regressions must pass before
  that implementation commit; a later phone parity checkpoint does not permit those failures to
  be deferred. Broader phone/provider verification remains a complete runnable call slice, with
  any external blocker recorded without a false pass. Independent work can continue while a
  specific external check is unavailable.
- Reviewed coverage against all existing acceptance items: sound resolution/isolation, all selected
  participant/room capabilities, unaffected-instance retention, audience/cue ordering, opening
  playback, clocks, recovery, safe diagnostics, rendered samples and live phone evidence. These
  remain requirements; the final audit only reconciles missing or invalidated evidence, rather than
  delaying failure handling or testing until all implementation is written.
- Replaced the milestone's long chronological evidence with committed-component summaries and
  representative commits, a separate dirty-worktree account, a verification ledger and a concise
  detour explanation. Existing historical labnotes retain the detailed failed approaches and
  intermediate results. Corrected stale statements that common collection/private playback did
  not yet exist and that implementation approval was still pending in the index review table.
- The ledger distinguishes `c4fea8c` (all five root gates; 1,274 tests, zero failures), six passing
  WebRTC checks with simulated providers, the later full worktree run (1,275 tests, nine failures),
  and the latest two failing phone harnesses. No browser/audible acceptance or completed delivery
  checkbox was inferred from component evidence. Milestone 23 and the packaging/retention hold
  remain unchanged in completion status.

### Documentation checkpoint verification

- All 145 local Markdown links/anchors across the milestone, index and implementation labnote
  resolve. The JSON example parses and is unchanged. Comparison with the committed document
  confirms the definition, readiness, private playback, initial sequence and complete acceptance
  checklist are preserved. The transfer sequence changes only stale approval wording and records
  the already generated cue's exact duration/frequency/ramps from the packaged asset README.
- All 25 milestone identities, order and completion states are preserved. Five delivery checkpoint
  sections exist and none of their implementation/acceptance tasks is checked complete. The local
  design-review checklist is separate from those runtime tasks.
- `git diff --check` passes. No tests were added or run for this documentation-only checkpoint;
  no runtime file, dependency or running development server was changed during the restructuring.
  Runtime edits already present in the worktree are left for the first runnable implementation
  checkpoint and retain their explicitly recorded failures.
