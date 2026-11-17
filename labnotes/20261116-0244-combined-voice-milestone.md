# Combined voice milestone

## Scope and source preservation

- User requested one combined milestone with all specification tasks assigned
  to meaningful checkpoints, then explicitly requested an independent Astra
  xhigh review against the specs. Existing research changes were preserved.
- Created this file with `bin/create-labnotes combined-voice-milestone` and saved
  disposable snapshots of all three previous task lists before consolidation.
  The existing setup run covers this documentation-only work.
- Added `labnotes/milestones/voice-agent-turns-and-listening.md` as the sole
  pending checklist. Six checkpoints deliver ElevenLabs transcript/history,
  Rime support, semantic interruption/modes, CPU filtering, audible cues, and
  telephone/language/resource coverage. Experiments/component work remain tasks
  inside useful call outcomes; E's experiment may start before its runtime gate.
- Replaced old task lists with mapping/reference documents, preserved their
  filenames and the completed Scribe section verbatim, updated specification
  ownership and the delivery review. The index now has one combined entry in
  place of three: 64 active milestones, 50 complete and 14 incomplete.

## Independent review and fixes

- Spawned the requested separate `gpt-6-astra` agent at `xhigh`, read-only, with
  the combined milestone, all four design sources and saved old task lists.
- First review audited 80 former entries: 76 pending and four completed Scribe
  checks. All groups had checkpoint owners; no new implementation was falsely
  marked complete. Five P2 acceptance gaps remained.
- Added explicit structured-input construction/tests separating runtime metadata
  from untrusted text, generated text from played prefix, and tool context from
  tool execution (C).
- Added distinct tests for late original overlap versus new substantive speech
  after playback ends, including a prior classifier-accepted acknowledgment (C/D).
- Restored cue byte/duration, credit/drain/backpressure and failed-clear-ack tests
  with sink recovery and no overlapping outputs/cue-induced call failure (E).
- Assigned optional timing for interrupted cue evidence to E/F, preserving
  estimated/unavailable cutoffs and excluding ordinary assistant exchanges.
- Separated service failure fallback for authorized current input from retirement
  on source/activation replacement, with no stale LLM request/admission (D).
- Tightened native-control work to expose and verify the missing controls through
  a reviewed binding revision/extension, rather than just inspect existing ones.
- Requested final review of fixes and the completed consolidation before closing
  this planning task. No runtime or provider acceptance follows from design review.

## Verification and final review

- Independent Astra xhigh re-review found no material findings remaining. It
  confirmed all five fixes, native-control wording, complete prior-task ownership,
  consistent checkpoint dependencies and optional timing/classifier capabilities.
- Documentation checks passed for 14 changed Markdown files, 237 local file
  links, 47 heading anchors and two JSON examples, with balanced fences and no
  trailing whitespace.
  All 72 implementation tasks are unchecked and inside A–F; superseded files
  have no pending tasks. The index has 64 unique ordered entries, 50 complete and
  14 pending. The completed Scribe section matches its saved source verbatim.
- `git diff --check` passed. This was documentation-only work; no runtime, browser,
  live-provider, Lean or umbrella-test acceptance is claimed. No commit created.

## Follow-up inspection of current model input

- User requested the current transcript format and explicitly requested delivery
  through pushnotify. Traced configured AgentRuntime admission, RequestRunner,
  ReqLLM RequestProjection, model context and tool completion continuations.
- Current input uses role/content messages; human text is appended as a user
  message. Optional call variables, transfer reason and pending invocations are
  serialized as runtime-state JSON in system content. The provider projection
  does not expose internal caller/engine origin as a field; tool completion
  continuations use user-role content with a textual engine-observation label.
- Sent two successful pushnotify messages with synthetic examples and current
  limitations. Distinguished current behavior from the proposed speech envelope
  and two-field interruption result. No transcript-format implementation changed.
