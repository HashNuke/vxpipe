# Message format milestone

## Scope and ownership

- User requested a dedicated milestone to implement the message format, after
  explicitly confirming retention of original assistant tool-call messages and
  their matching responses. Preserved all existing research changes and created
  disposable pre-extraction snapshots for source coverage review.
- Added the message-format milestone with three runnable checkpoints and 22
  pending tasks: attributed configured conversation, background tools with stable
  history, and validated replies/provider activation. Tests and configured/manual
  acceptance are grouped with each outcome; no runtime work performed.
- Extracted five generic tasks from the voice checklist and narrowed overlap
  tasks to consume the shared protocol. Voice retains 72 tasks and six exits.
  A coverage table maps all former generic concerns to the new owner.
- New message A supplies coarse attributed history for voice A; new message C
  supplies the protocol for voice C. The new milestone has no dependency on
  unfinished timing/classifier/cue work, avoiding a dependency cycle.
- Inserted the new entry ahead of voice in the index without renaming existing
  milestones. Totals are 65 active, 50 complete and 15 pending.

## Tool-call clarification

- Corrected the design's earlier ambiguous result-only wording: original native
  assistant call messages, IDs, arguments, accompanying content and provider
  metadata are retained, as are matching native responses.
- Read the completed background/shared-tool contracts. Preserve truthful one-time
  submission acknowledgments as immutable historical results; later async
  completion remains a distinct application observation, not a second native
  response. No fabricated completion or provider-specific execution branch.
- Only additional mutable pending inventories/snapshots are removed. Kept
  internal registry/admission, duplicate protection, tool lifetimes and valid
  later repeats. Refined design, classifier/TTS ownership links, delivery review
  and index to match the dedicated milestone.

## Verification

- Documentation checks passed for 19 changed Markdown files, 264 local links,
  49 heading anchors and five JSON examples. Task ownership checks confirm 22
  new-message tasks under A/B/C (7/7/8), and 72 voice tasks under A–F
  (11/4/17/12/17/11), all unchecked. Index has 65 unique ordered entries,
  50 complete and 15 pending, with message format before voice behavior.
- Historical Scribe evidence is verbatim unchanged; superseded feature files
  have no pending checklists. `git diff --check` passed.
- Independent Astra xhigh extraction review found no material findings. It
  confirmed original call/response retention, genuine submission acknowledgments,
  all generic task owners, configured-agent exits, acyclic dependencies and
  preserved provider/privacy/compaction/cache/latency gates.
- No code, dependencies, provider calls, runtime/browser acceptance or commits.
