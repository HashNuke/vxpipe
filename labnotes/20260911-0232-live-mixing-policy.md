# Live mixing and media policy

## 2026-09-11 — immutable policy contract

- Began milestone 15 on `milestone/live-mixing-media-policy`. The first checkpoint deliberately
  establishes one compiled policy input before implementing realtime frame routing: public JSON
  semantics must not be duplicated by Room Authority, a mixer, transcript projection, and storage
  gates.
- Selected four independently optional fields for both normal `media_policy` and participant
  `while_present`: `audio_routes`, `transcript_routes`, `record_audio`, and `save_transcripts`.
  Omission is represented as `:inherit`; an explicit empty route map remains an empty map. Route
  values retain ordered definition keys in the validated definition and compile to participant IDs
  plus `MapSet` recipients in the immutable plan.
- Wrote the focused compiler test first. Its red run stopped at test compilation because
  `CallDefinition.MediaPolicy` did not exist, which was the expected missing contract.
- Added separate validated-definition and resolved-plan policy modules. The call definition owns
  closed shape/reference validation; the resolved policy owns the one-time definition-key to
  runtime-ID translation. Participant parsing owns only the optional `while_present` field, and the
  compiler continues to compose the immutable plan rather than absorbing policy behavior.
- The first complete Call Engine run exposed two expected migration gaps: the older compiler test
  still classified the newly supported keys as invalid, and direct resolved-plan fixtures lacked
  the new enforced field. Updating those assertions/fixtures restored the suite without weakening
  the new invalid-shape coverage.
- Focused verification: `mix test
  test/vxpipe/call_engine/call_definition/media_policy_compiler_test.exs` passes four tests.
  The final focused case first mutated an otherwise validated policy to an unsupported permission
  atom and demonstrated that compilation accepted it. The resolved-policy compiler now revalidates
  those permission values and rejects the forged typed input at the policy boundary.
  Complete Call Engine verification: `mix test` passes 286 tests with one tagged integration
  exclusion. Umbrella formatting, warnings-as-errors compilation, strict Credo, and unused-lock
  checks pass.
- The first database-backed umbrella test run exposed the prior transfer commit race documented in
  the transfer labnote. After that independently committed correction, a fresh run against a
  disposable PostgreSQL 17 instance passes: MCP 37 tests with three exclusions, Agent Runtime 58
  with two exclusions, Call Engine 286 with one exclusion, Calls 37, Persistence 25, Gateway 67
  with four exclusions, and Console 57. The disposable database was removed after verification.
- Runtime policy intersection, authoritative presence transitions, media commit barriers, mixer
  supervision, route delivery, and transcript/archive gates are intentionally not claimed yet.

## 2026-09-11 — pure effective-policy intersection

- Wrote the effective-policy tests before the implementation. All five initially failed because
  `Vxpipe.CallEngine.MediaPolicy.Effective` did not exist.
- Added a pure composer that accepts the resolved host ceiling, normal call policy, and a map of
  authoritatively present participant contributions. It performs no process, transport, or database
  work.
- Inherited routes become unrestricted only when every input inherits. Otherwise every explicit
  route map is treated as a complete allowlist: sources must survive every map and recipient sets
  are intersected. A surviving source with an empty recipient intersection remains explicit.
- Effective audio-recording and transcript-storage permissions are concrete booleans. Omission does
  not restrict; any false input wins. Recomputing without one owner removes only that contribution.
- Moved resolved-policy representation validation into its owning module. Malformed or forged
  inputs return `{:error, :invalid_policy}` so the later admission barrier can fail closed.
- Focused verification passes nine tests across the policy compiler and effective composer.
- Complete verification passes formatting, warnings-as-errors compilation, 291 Call Engine tests
  with one integration exclusion, strict Credo, and the unused-lock check. A fresh database-backed
  umbrella run also passes: MCP 37 tests with three exclusions, Agent Runtime 58 with two
  exclusions, Call Engine 291 with one exclusion, Calls 37, Persistence 25, Gateway 67 with four
  exclusions, and Console 57. The disposable PostgreSQL 17 container was removed afterward.

## 2026-09-11 — room policy authority

- Wrote four process-contract tests first. The red run failed at compilation because the
  `MediaPolicy.Authority` and revisioned `MediaPolicy.Snapshot` contracts did not exist.
- Added one temporary, significant GenServer per planned room. It owns only the immutable host/call
  policy inputs, participant-ID-to-policy catalog, active contribution map, monotonic revision, and
  current effective snapshot. It accepts only participant identities pinned into the resolved plan.
- Added a separate supervision-boundary assertion. Its red run found no registered policy process
  beside a live planned room; adding the significant child to the room incarnation made it green.
  If this privacy-critical process terminates, `auto_shutdown: :any_significant` ends the room
  subtree rather than restarting with an empty presence map.
- Tightened the existing definition-driven startup scenario from a revision-zero expectation to
  both entry participants at revision two. That red run proved the initially supervised process was
  not yet synchronized with Room Authority membership.
- Participant commit now applies the pinned `while_present` contribution before writing membership
  to Room Authority state. A transition failure aborts admission. Authoritative participant exit
  removes its contribution; a connection detach does not, which preserves the approved distinction
  between transport loss and leave.
- Focused room tests confirm the two entry admissions, disconnect-versus-leave behavior, and
  fail-closed room teardown on policy-authority loss. Media sinks do not consume policy revisions
  yet, so this is state ownership and commit-order groundwork rather than a completed media barrier.
- A subsequent boundary test submitted a participant ID absent from the pinned catalog. The policy
  rejection was correct, but the red test found its already-prepared participant supervisor still
  registered. `ParticipantLifecycle.start/3` now discards every preparation whose commit fails;
  rejection leaves neither membership nor a stray participant process and does not advance policy
  revision.
- Complete verification passes formatting, warnings-as-errors compilation, 297 Call Engine tests
  with one integration exclusion, strict Credo, and the unused-lock check. A fresh database-backed
  umbrella run also passes: MCP 37 tests with three exclusions, Agent Runtime 58 with two
  exclusions, Call Engine 297 with one exclusion, Calls 37, Persistence 25, Gateway 67 with four
  exclusions, and Console 57. The disposable PostgreSQL 17 container was removed afterward.

## 2026-09-11 — revision acknowledgement barrier

- Added the focused barrier tests first. Four cases failed with the expected undefined
  `register_enforcer/2` boundary; a fifth then demonstrated that a zero enforcement timeout was
  accepted during authority startup.
- Added a small `MediaPolicy.Enforcer` message boundary and a bounded `MediaPolicy.Barrier`.
  Registration first installs the current snapshot and only then monitors the enforcer as required.
  A transition computes a candidate revision, applies it to every registered enforcer within one
  shared deadline, and commits the authority state only after every acknowledgement is `:ok`.
- Enforcers do not run policy math. They receive the complete revisioned snapshot they must install
  locally. Rejected, timed-out, malformed, or unavailable enforcement fails the significant policy
  authority, which ends the room rather than allowing partially applied revisions to continue.
  Later loss of a registered enforcer has the same fail-closed outcome.
- A deliberately blocked test enforcer proves that `admit/2` remains pending until the final
  acknowledgement. Other focused cases prove initial revision installation, duplicate rejection,
  transition rejection, enforcer loss, and timeout validation.
- Focused verification passes nine policy-authority tests. The complete Call Engine suite passes
  302 tests with one tagged integration exclusion. A fresh umbrella run against a disposable
  PostgreSQL 17 instance also passes: MCP 37 tests with three exclusions, Agent Runtime 58 with two
  exclusions, Call Engine 302 with one exclusion, Calls 37, Persistence 25, Gateway 67 with four
  exclusions, and Console 57. The disposable database was removed afterward. No concrete mixer,
  transcript projector, or archive consumer is registered yet; this checkpoint establishes their
  common commit boundary but does not claim that media is enforced.

## 2026-09-11 — bounded room mixer

- Added the standalone mixer tests before implementation. The red run failed while expanding the
  absent `Media.MixedFrame` struct, confirming that no prior live-mix contract existed.
- Defined normalized input as fixed-size signed 16-bit little-endian PCM on the room clock. Every
  frame carries its policy revision, source participant, track, timestamp, and monotonic source
  sequence. This revision tag is required to distinguish late old-interval media from data received
  after a policy change; arrival time alone cannot make that distinction safely.
- Added a bounded timestamp buffer and saturating PCM mixer. A flush processes timestamp buckets in
  order. It selects sources independently for each recipient through effective `audio_routes`,
  excludes a participant's own source for mix-minus, and supports output-only full-mix and
  individual-track monitor subscriptions.
- Kept slow sinks out of the GenServer hot path. Each subscription has a fixed mixer-owned queue,
  receives only a coalesced availability notice, and pulls bounded batches using an opaque handle.
  A full queue drops the new mixed frame and increments an explicit overflow counter instead of
  blocking or expanding a remote process mailbox.
- Applying a policy revision clears both aligned input buckets and pending output queues before
  acknowledging the barrier. Frames tagged with another revision are rejected, so old data cannot
  be replayed under a later relaxed policy. Tests also cover exact room identity, present recipient
  and source checks, explicit monitor non-publication, 16-bit saturation, duplicate/stale input,
  and malformed or non-monotonic policy snapshots.
- The initial planned-room tests failed because no registered mixer existed. Planned room
  supervision now starts one temporary significant mixer after the policy authority and before
  Room Authority. Room Authority registers it as an enforcer before admitting either entry
  participant. The entry test reaches mixer revision two, and killing the mixer ends the room.
- A leave-path audit then found that an unrestricted route could still target a retained output
  subscription after its recipient left. The regression failed with one delivery; delivery now
  also requires the recipient to be present in the installed snapshot, and the test is green.
- Before committing, the initial cohesive implementation was split along its actual reasons to
  change. The 539-line mixer module is now a 181-line GenServer boundary delegating configuration
  and state construction, policy installation, frame admission, timestamp buffering, routing and
  fan-out, PCM arithmetic, and monitored subscription queues to named modules. The same focused
  behavior tests remained green after the split.
- Focused mixer and planned-room checks pass. The complete Call Engine suite passes 310 tests with
  one tagged integration exclusion; strict Credo reports no issues. A fresh umbrella run against a
  disposable PostgreSQL 17 instance also passes all seven child applications with the same counts
  as the preceding checkpoint except for the expanded Call Engine suite. The disposable database
  was removed afterward. Transport PCM normalization, connection-to-mixer input/output wiring,
  transcript/archive policy consumers, and human-only startup remain open.

## 2026-09-11 — transcript routing and archive source policy

- Added the transcript-router and archive override tests before implementation. The red run failed
  while expanding the absent decision struct; after the standalone policy boundary existed, a
  live planned-room regression still received agent text despite a present participant's explicit
  empty route.
- Added one temporary, significant `TranscriptRouter` per planned room. Room Authority registers it
  with the policy authority before the mixer and before entry admission. It installs the same
  monotonic snapshots, filters connected/present recipient identities through
  `transcript_routes`, and retains prior snapshots for source-interval storage decisions. That
  history is bounded to 128 revisions by default; a projection older than the retained window is
  rejected rather than assigned a guessed policy.
- A projection tagged with an older policy revision receives no live recipients. Relaxing policy
  later therefore cannot replay a queued denied interval. The source revision still determines
  `save_transcripts`, independently of current live sharing.
- Participant-transcription and generated-agent-text events now pass through this boundary.
  Transcript-bearing typed/audio input and generated/delivered output facts carry the effective
  media revision and storage permission into `Archive.Port`. The port merges that decision with
  the base source policy and removes denied text before offering the fact to either archive or live
  inspection queues; the delayed Calls-side filter remains defense in depth.
- Router unavailability denies both live transcript projection and transcript storage, and loss of
  the significant router ends the room through the existing fail-closed supervision policy.
- Focused checks cover unrestricted and explicit routing, independent storage denial, stale
  revision non-replay, bounded revision eviction, invalid identity/revision/source, pre-handoff
  payload filtering, the full room regression, and router-loss teardown. The complete Call Engine
  suite passes 317 tests with one tagged integration exclusion.
- The complete database-backed umbrella suite passes across all seven child applications using a
  disposable PostgreSQL instance. Formatting, warnings-as-errors compilation, strict Credo, and
  the umbrella lockfile unused-dependency check also pass.
- Provider STT sessions do not yet carry/pivot source revisions across a presence transition. That
  lifecycle work, demand-based STT stopping, future recorder policy, mixer transport wiring, and
  human-only startup remain open; this checkpoint does not claim the in-flight provider boundary.

## 2026-09-11 — human-only planned startup

- Added schema and live-room tests first. Both failed at the old requirement that
  `entry_receiver` resolve to an agent participant.
- The dated schema now permits a human receiver while retaining the existing requirements that the
  caller be human and that the two entry refs be different declared participants. Compilation
  continues to assign activation IDs only to agents.
- Planned startup now carries STT runtime selections by human participant ID. An agent receiver
  follows the unchanged activation/coordinator/TTS path; a human receiver is admitted without an
  activation, text capability, greeting, or TTS process. The explicit
  `text_capability_required?` state keeps legacy rooms and agent-backed planned rooms fail-closed
  while allowing intentional human-only attachments. `send_text` still rejects the absence of an
  agent.
- Moved the vertical behavior into `HumanOnlyCallTest` rather than expanding the already broad
  definition-driven test module. It starts exactly two human entries, attaches both, verifies
  policy revision two, sends fixed-size normalized PCM in both directions, proves mix-minus output
  contains only the other participant, and ends the room through its pinned maximum-duration
  timer.
- The focused checks and complete Call Engine suite pass: 319 tests, zero failures, and one tagged
  integration exclusion. Browser transport normalization/subscription remains a later checkpoint;
  this test exercises the live supervised engine and mixer boundary directly.
- The complete database-backed umbrella suite passes across all seven child applications using a
  disposable PostgreSQL instance. Formatting, warnings-as-errors compilation, strict Credo, and
  the unused-dependency check also pass.

## 2026-09-11 — Gateway Opus normalization

- A first six-test prototype used the Opus NIF directly and implemented RTP admission, timestamp
  rollover and PCM framing in Vxpipe. It passed, but duplicated responsibilities already provided
  by Membrane and was removed before commit.
- Replaced it with a per-track Membrane pipeline. The first pipeline test run failed because
  `AudioPipeline` and `PCMFrame` did not exist. After implementation, four focused tests pass for
  one 20 ms packet, accumulation of two 10 ms packets, stereo-to-mono normalization, and rejection
  outside the pinned connection/track/room identity.
- Official Membrane elements now own RTP jitter buffering and rollover-aware PTS, Opus
  depayloading/parsing/decoding, and exact 20 ms PCM rechunking. A small Vxpipe Membrane filter
  aligns the stream to the shared VM-relative room clock. Another passes mono through or averages
  stereo channels; FFmpeg was tried briefly as a converter dependency and removed because Opus is
  already decoded at 48 kHz and only channel averaging is needed.
- The existing room mixer remains Vxpipe-owned for policy-aware mix-minus/full/individual routing,
  policy revision barriers and bounded opaque subscriptions. Its sample addition now delegates to
  Membrane's public audio-mixer adder instead of maintaining duplicate saturating arithmetic.
- This checkpoint intentionally stops before connection integration. Mixer push/revision refresh,
  policy-transition pipeline restart, bounded subscription draining, and Membrane-backed Opus
  WebRTC output remain next; no browser-runnable two-human path is claimed yet.
- Verification after replacement: the Gateway suite passes 71 tests with four tagged integration
  exclusions; the Call Engine suite remains at 319 tests with one tagged integration exclusion.
  A fresh database-backed umbrella run passes across all seven child applications. Formatting,
  warnings-as-errors compilation, strict Credo, and the unused-dependency check pass. The
  disposable PostgreSQL container used for the umbrella run was removed afterward.
