# ElevenLabs Realtime models

## Investigation

- Started from a clean worktree. `bin/setup` completed after the sandbox initially
  prevented access to local PostgreSQL. No live calls have been made.
- ElevenLabs documents Mini and Max on a standalone OpenAI-compatible Realtime
  WebSocket endpoint. Its documented authentication path creates an ephemeral
  client secret from model configuration; it does not create an ElevenAgents agent.
- Existing GPT-Live uses a different protocol. Reuse the engine's scoped STS
  channel and private Mint socket, not the GPT-Live or historical agent adapters.
- User requires ElevenLabs native turn detection with no local VAD; the initial
  profile exposes only provider-controlled turns.
- Initial red run: six focused configuration/codec/auth tests fail because the new
  modules do not exist, as expected.
- User authorized small coherent commits only after verification and an independent
  GPT-6 Astra xhigh review with findings fixed and clean follow-up review.

The [milestone](milestones/elevenlabs-realtime-models.md) tracks remaining work.

## Checkpoint A

- Configuration/codec/auth focused run: 6 tests, 0 failures after correcting
  the Req test-plug option placement. The earlier malformed option made two
  attempts with a synthetic key; neither used real credentials or generated audio.
- First authorized live selection: exactly one Mini protocol test. Ephemeral
  credential POST and Bearer-authenticated WebSocket succeeded. `response.created`
  omitted the requested metadata, so the correlation assertion failed before
  audio acceptance. No retry was run. This changes the adapter design: serialize
  explicit response requests, bind the sole pending request on `response.created`,
  and reject unexpected responses. Native VAD remains configured, while automatic
  response generation and automatic interruption are disabled.

## Native generation and review fixes

- The first scoped Mini audio run closed during input. A bounded telemetry
  diagnostic identified `:unexpected_event` on a targeted retry: the only
  unmatched decoded case was `response.created` without an explicit pending
  request. Thus the provider was generating natively despite echoing
  `create_response: false`. The adapter now requests native generation explicitly
  (`true`), retaining room-owned interruption (`false`). Native stop evidence
  establishes the response origin; final transcription can follow response creation.
- The next Mini-only live selection passed: one test, 6.4 seconds, native caller
  activity/transcript and credited audio/final output. Total actual provider
  sessions so far: four Mini (three diagnostic failures, one pass); no Max
  session yet. A Max command failed before test execution due to concurrent Mix
  protocol consolidation. No other provider or real telephony was used.
- Initial independent GPT-6 Astra xhigh review found eight lifecycle/bounding
  issues. Added focused regressions; the first review regression run failed for
  expected immediate-response announcement, competing PCM admission and premature
  quiescence. A local WebSocket burst test failed by receiving all 32 frames
  without a session acknowledgement.
- Fixes now defer public speech announcement/ordinal until PCM; tool-only turns
  remain private and do not manufacture an empty playback. Completed tool IDs
  remain bounded within their response. Cancelled tool tails are ignored.
  PCM is not admitted while an explicit request lacks a response ID. Caller
  completion compares accepted-audio serials before clearing pending input.
  Native response/final obligations have scoped deadlines. Socket frame admission
  uses the shared transport's acknowledged handoff.
- Focused session verification: 14 tests, 0 failures, including native response
  before final transcript, mixed ordinal order, tool continuation/deduplication,
  cancellation with an outstanding credit, fixed-opening mismatch, output rejection,
  deadlines and owner loss during blocked credential preparation. Local socket
  integration: one test passed (no external service). Follow-up independent review
  and compiled room verification are pending; no clean final review or commit yet.

## Follow-up review and verification

- A second review found that local audio serials are not proof of provider buffer
  consumption, native policy/hold transitions could remain busy forever, and
  queued explicit dispatch could bypass microphone exclusions. New regressions
  first failed for false quiescence, missing allocation closure and accepted PCM
  during a queued request. The adapter now pins the first authorization context
  for its allocation lifetime, closes before changed-context admission, and never
  reports input quiescence after accepted PCM. No source-cutover continuity is
  claimed. A fresh allocation is required for a changed authorization context.
- Readiness regressions rejected changed PCM/VAD settings, then separately failed
  for disabled input transcription. Readiness now requires the advertised input
  transcription to be acknowledged as well.
- Max live acceptance passed: one test, 6.3 seconds. Actual paid sessions to this
  point: four Mini, one Max. No other provider or telephony was contacted.
- The earlier full umbrella run was stopped after source changed underneath it;
  it is not final evidence. All final Mix gates will run sequentially to avoid
  shared-build protocol-consolidation races.
- Compiled room test passed with native caller evidence, a room-executed ping,
  no phantom tool-only playback, credited resampled PCM and local sink settlement.
  It asserts no local activity detector or STT capability was started.

- The next independent review correctly rejected waiting for changed input:
  delayed native caller evidence can arrive after hold/release first. Three room
  tests gave two expected red failures at hold and policy revoke (the tool/audio
  case still passed). Added a generic, opt-in STS `input_cutover: :close` contract,
  validated only with stop-hold; ElevenLabs closes at those boundaries before
  evidence can enter a new epoch. Existing providers retain their default behavior.
- A queued tool continuation could also starve an already-speaking caller of the
  PCM needed to endpoint. Its regression failed with `:busy`; continuation queues
  now admit same-origin PCM while waiting, unlike queued text/opening requests.
- Focused adapter, descriptor, compiled-room and existing capability checks pass:
  95 tests, zero failures. The preceding umbrella run passed 2,270 Call Engine
  cases and earlier child apps, then was stopped during Gateway because these
  shared-boundary corrections superseded its source. It is not a completed gate.
- Subsequent review found direct release could rotate an already-bound epoch,
  and immediate closure omitted the independent sink's playback fence. The room
  regression group failed five of ten cases for those exact reasons. Shared
  cutover now marks held, retires pending/tools, fences active playback and then
  closes. Bound new-epoch release uses that path; repeated same-epoch release is
  idempotent. The combined focused group now passes 102 tests, zero failures.
- A malformed `response.created.metadata` codec regression first raised an
  exception containing its synthetic sentinel. The decoder now rejects non-map
  metadata with a sanitized error; all four codec/configuration cases pass.

## Final acceptance in progress

- Final Mini live selection passed one test in 11.1 seconds: two native turns on
  one connection, distinct output handles, caller/output transcripts, credited PCM
  and local settlement. Total actual provider sessions: five Mini and one Max.
  No further paid run is planned; only ElevenLabs and recorded PCM were used.
- Independent GPT-6 Astra xhigh source review reports no remaining actionable
  code/test findings. Final sign-off awaits all common gate results.
- Strict Credo caught the shared capability at 803 lines after the policy hook.
  Moved its direct-policy handling into the existing cohesive Policy module,
  retaining behavior; 73 affected capability/room tests pass. Final gates restart
  sequentially on that source. The gate's failed size check is not waived.

- Final root verification passes on the refactored source: `mix format
  --check-formatted`, `mix compile --warnings-as-errors`, `mix credo --strict`,
  `mix test` (4,491 cases, zero failures, 159 excluded), `mix deps.unlock
  --check-unused`, and `bin/verify-lean` (nine build jobs and one passing oracle
  replay). Call Engine: 2,280 cases; Gateway: 863; Persistence: 423; Console: 393.
- Final local socket burst test passes with `--no-compile --include integration`;
  it uses a loopback peer, not an external provider. All paid checks remain
  exclusively the recorded ElevenLabs sessions above. Final independent sign-off
  has been requested with the passing evidence before any commit.

## Reviewed checkpoint commits

- Final independent GPT-6 Astra xhigh review verified the source, docs and gate
  evidence and gave clean sign-off with no remaining actionable findings. All
  implementation and verification finished before the first commit.
- Checkpoint: persist pure model/session configuration, bounded wire codec,
  redacted ephemeral connection/authentication and focused synthetic HTTP tests.
  No hosted-agent provisioning or local VAD is introduced.
