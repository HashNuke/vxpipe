# Agent backchannel research

## Scope and starting state

- User requested research followed by a separate milestone for agent listening
  cues driven by transcripts with no default local VAD requirement. No prototype,
  runtime implementation, paid synthesis, deployment or commit was requested.
- Existing uncommitted classifier design/labnotes and contextual barge-in
  milestone changes were preserved. Inspected runtime baseline `64a4626a`.
- `bin/setup` already completed in this checkout during this conversation;
  no dependency or runtime changes needed another setup run.
- Created this file with `bin/create-labnotes agent-backchannel-research`.

## Research findings

- Read all four supplied URLs: Rime's backchannel guide, Pipecat's community
  extension page, NVIDIA's nightly turn-taking/backchannel page and Inworld's
  realtime back-channel API. Followed Rime's links to its Mist v2 announcement
  and Ward's researcher-authored overview, and Pipecat's link to the extension
  source repository README. Exact source links and bounded summaries live in
  `docs/design/agent-backchannel-responses.md`.
- Inworld is the closest architectural reference: partial-transcript evaluations,
  optional pause gating, small LLM/rule selector, phrase bank, rate/deadline
  controls and separately identified cue audio. Pause gating off does not prove
  its backend is VAD-free; no hosted behavior was measured.
- Pipecat's linked extension requires its own VAD/turn analysis and caches TTS
  clips. Its documented implementation is community-maintained, pause-based
  and English-specific. NVIDIA primarily covers suppression of incoming human
  backchannels, not generating agent cues. Rime emphasizes prosodic placement
  and natural TTS; its article does not establish transcript-only accuracy.
- Transcript inactivity cannot prove silence or speech continuation. A useful
  prototype must measure audible timing and coverage, including starvation from
  strict revision checks, rather than count only harmless skips.

## Runtime and user clarification

- Inspected transcript-start requirements, STT signals/InputTurns, TTS request/
  output purposes, room playback routing, prepared opening cache, wait-sound
  player, speech playback and media frame contracts. Existing purpose values
  exclude backchannels; generic frames carry media visibility scope rather than
  conversational purpose. Cache/player primitives exist but carry opening/
  transfer-specific behavior.
- Initial wording about “taking the floor” was unclear. User clarified and then
  identified the actual feedback risk: cue playback could make ongoing human
  speech look like a barge-in. User selected listener mode and speaker mode for
  voice-agent participants. Listener mode includes audible cues; human input
  remains active in both modes. Cue-only overlap must not invoke interruption
  classification or create another conversational response.
- Chosen proposal keeps mode scoped to an activation and output purpose/identity
  scoped to each playback. Cue completion cannot toggle mode; main-response
  admission cancels cues through acknowledged settlement. This avoids late cue
  callbacks changing the mode of a new answer.

## Follow-up: endpoint transitions and shorter pauses

- User proposed switching to speaker mode at human turn completion and using
  incoming transcripts to find pauses shorter than turn-ending silence. Clarified
  that a confirmed endpoint closes cues immediately and response admission
  switches to speaker mode before generation/audio. No-response and pending
  decisions can remain listener with a closed cue window. Eager endpoints and
  unrelated speakers do not authorize that transition; speaker mode alone
  cannot establish audible overlap for incoming interruption classification.
- Read Deepgram's Flux API and eager-endpoint guide, Nova UtteranceEnd guide,
  and ElevenLabs realtime event/commit-strategy references. Exact links live in
  the design. Flux documents word/audio-window timing, but the current decoder
  drops words and window positions. Actual interim timing/cadence needs a trace
  prototype. Nova's word-gap event belongs to a different API.
- Scribe documents processed-audio keepalives, distinct from missing messages;
  their documented cadence does not establish a short-pause cue trigger. Current
  Scribe v2 configuration/ContinuousSTT uses an empty partial after a committed
  segment for settlement. Do not treat newer Scribe v3 capabilities as deployed.
- Separated cue content selection from playback timing. Permit an explicitly
  estimated transcript-gap condition in the prototype, measured against audio;
  rejected treating message gaps as confirmed silence or lowering the endpoint
  threshold to create cue opportunities. Optional provider timing needs source
  clock/freshness checks and cannot rely on audio merely sent to a provider.
- Expanded milestone checks for endpoint/no-response/eager/resume/generation
  transitions, stale pause evidence and false pause estimates during continuous
  speech with ASR buffering. No live capabilities or timing quality were measured.

## Deliverables and limitations

- Added a durable research/decision document and separate descriptive milestone,
  with a no-VAD prototype first, modes/purpose integration, configured calls and
  real audible acceptance. Recorded local design/dependency review separately
  from implementation progress; all implementation gates stay unchecked.
- Prepared voice-specific clips and a bounded transcript selector are hypotheses
  for prototype comparison. Proposed cadence/quality/latency gates are explicit
  and must be frozen before tuning. Outgoing-cue default-on is not inferred from
  the earlier incoming-classifier preference.
- No source code, provider credentials, model weights or audio assets were added.
  The prohibited live-provider environment file was not accessed. No paid API,
  runtime/Lean suite, browser test, native listening review or prototype was run.
- Added the milestone to the ordered index before container delivery/retention,
  updating counts to 65 total, 50 complete, 15 incomplete. The classifier design
  links to the separate cue policy and excludes cue-only overlap from its
  eligibility. Existing unrelated work and earlier planning evidence remain.
- Documentation verification passed: local link targets, Markdown fences and
  whitespace, `git diff --check`, contiguous index numbering/counts, prerequisite
  order, new milestone's unchecked implementation tasks and design-review link.
  Final status contains only the earlier and new documentation changes.
