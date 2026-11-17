# TTS playback transcripts

## Scope and starting state

- User requested common timing data from the integrated TTS providers, preserving
  a full generated answer while the spoken transcript contains only the played
  prefix after interruption. Clarified that this applies when the provider
  supplies timing; unsupported providers must remain usable. Planning only.
- Created this file with `bin/create-labnotes tts-playback-transcripts`.
  Existing classifier/backchannel research changes were preserved. Setup already
  ran in this checkout earlier in the conversation; no dependencies changed.

## Findings and decisions

- Inspected ElevenLabs/Rime TTS decoders, Speech.Event/Descriptor, AgentOutput,
  SpokenHistory, generated/delivered archive projections and policy, runtime
  RequestRunner/Conversation, Coordinator interruption/history, and Gateway local
  playback plus remote clear/mark acknowledgments.
- Generated text is already a distinct archive event, subject to configured
  archive availability and transcript retention. Completed model responses enter
  mutable session history; interruption can discard exchanges. An unfinished
  sentence may still be only in the streaming buffer. Full immutable archival
  retention across interruption is therefore not already established.
- Completed speech segments append whole text to spoken history. Interrupted
  partial words are not reconciled. Current ElevenLabs TTS ignores alignment and
  Rime explicitly ignores timestamp events. Gateway's played count describes
  local paced delivery, not a remote listener's exact speaker position.
- Rechecked primary ElevenLabs TTS/multi-context and Rime legacy/new-WebSocket
  timing references; exact links are in the design. Rime legacy timings are
  estimates, with language-dependent availability. Newer Coda alignment arrives
  at completion; its existence does not upgrade the currently integrated path.
- Proposed an optional typed timed-span event normalized at the integration
  boundary, preserving units/clock, rendered text, identity, quality and coverage.
  Call Engine owns playback projection; AgentRuntime owns ordered conversation
  replacement. Generated output remains separate under existing retention policy.
- Missing alignment or playback data produces explicit unknown delivery; known
  zero is an empty prefix. No proportional truncation or extra alignment wait.
  Rime-derived prefixes retain estimated status. Tool facts and human input must
  survive projection, including transfer/compaction/recovery.

## Deliverables and verification

- Added `docs/design/tts-playback-transcripts.md`, linked from the classifier and
  outgoing-cue designs and existing contextual-barge-in milestone. Added scoped
  unchecked tasks and acceptance cases, and a separate local design review.
- No new milestone/index order change. No code, weights, dependencies, generated
  audio, paid API calls, commits or runtime/Lean tests. The prohibited provider
  environment file was not accessed. Live timing accuracy remains unmeasured.
- Verification passed for all five documents changed in this follow-up: 45 local
  link targets, two JSON examples, balanced fences, whitespace and
  `git diff --check`. Reviewed milestone diff and final worktree status; all new
  implementation tasks remain unchecked and changes are documentation only.
