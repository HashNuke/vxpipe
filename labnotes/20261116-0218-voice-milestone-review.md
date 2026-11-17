# Voice milestone review

## Scope and starting state

- User requested review of classifier, outgoing cues and TTS timing requirements
  to find combinations that permit smaller useful implementation iterations.
  Preserved all existing uncommitted research and historical completion evidence.
- Created this file with `bin/create-labnotes voice-milestone-review`. Setup had
  already run in this checkout. No runtime/dependency or deployment work.

## Findings and decisions

- The work existed as three design areas but only two milestone files: TTS timing
  tasks were embedded inside contextual barge-in. That checkpoint mixed protocol
  metadata, history reconciliation, semantic decisions and classifier serving.
- Keep three feature milestones, with four usable iterations: interrupted spoken
  transcripts; semantic interruption/modes; CPU filtering; configured listening
  cues. The standalone cue experiment can start on existing foundations.
- Combine TTS normalization, qualified playback, archives and ordinary model
  history in the first provider checkpoint. Otherwise timestamps or UI text
  alone would not satisfy the `x y z` -> `x y` requirement. ElevenLabs first;
  Rime estimates reuse the same contract in a subsequent checkpoint.
- Share modes/purpose admission in semantic interruption; outgoing cues consume
  that tested boundary. The CPU service is a separate incremental optimization
  requiring the structured fallback, not a prerequisite for listening cues.
- Preserve provider/language expansion and broader one-second acceptance as
  open obligations. First-profile exits do not complete whole milestones.
  Keep model-build smoke within classifier delivery without depending on general
  distribution or committing weights. Preserve the deferred Models-tab UI note.

## Deliverables and verification

- Added a durable delivery review and a separate TTS milestone, and revised the
  existing contextual/cue checkpoints around complete configured-call outcomes.
  The index remains the ordering authority; no milestone file was renamed and
  no implementation checkbox was completed by this planning review.
- Documentation checks passed across the full current research worktree: 12
  Markdown files, local link targets, two JSON examples, balanced fences,
  whitespace and `git diff --check`. Index validation confirms 66 unique,
  consecutive entries, 50 complete and 16 incomplete. No old checkpoint-anchor
  references were found for the revised headings. Checked existing implementation
  evidence remains unchanged; all added tasks remain open.
- Reviewed final diffs/status. No source code, model assets, secrets, runtime
  tests, browser/live calls or commits were involved. No independent-agent review
  is claimed; this is a local architecture and dependency review.
