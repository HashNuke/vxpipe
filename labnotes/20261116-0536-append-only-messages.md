# Append-only model messages

## User correction and evidence

- User rejected latest-message pending snapshots because moving the field changes
  earlier prompt content. Requested no pending-call context and only appended
  tool responses. Continued documentation work, preserving all existing changes.
- Re-read RequestProjection and RequestRunner. Pending state is currently added
  to system content; tool submission immediately commits a native call plus a
  running acknowledgment before later semantic completion. Removing a field alone
  does not satisfy the new behavior.
- Checked primary provider docs: exact-prefix cache reuse also requires compatible
  request settings; changing a suffix does not invalidate every earlier prefix.
  Claude requires adjacent native tool-call/result blocks. Neither append-only
  application messages nor cache goals justify breaking native tool protocol.

## Design changes

- Superseded latest-only snapshots in the separate message design and classifier
  example. No pending inventory, empty list, running/queued application-status
  message or system-level projection is sent to ordinary or interruption models.
- Terminal tool results append once. Runtime keeps admission, deadlines, duplicate
  protection and side-effect ownership; legitimate later repeated operations stay
  possible. Explicit provider acceptance covers native pairing and conversation
  during background work, without fake results or orphan calls.
- Preserve serialized old-message prefixes; append genuine permitted state
  changes instead of rewriting dynamic system content. Document explicit context
  boundaries for compaction, privacy, configuration and provider changes.
- Reconcile TTS with immutable model history: settle before committing spoken
  text; archive/UI corrections may revise those projections, while later model
  corrections append rather than editing earlier content.
- Updated A/C/F, source coverage, delivery review and index; 77 tasks remain open
  in six checkpoints. Earlier clean review is historical; this amendment needs
  a new independent review. No runtime or live-provider change performed.

## Verification

- Documentation checks passed: 17 Markdown files, 247 local links, 48 anchors,
  five JSON examples; model examples have no pending/turn/event/version fields,
  and the output still has exactly two fields. All 77 implementation tasks are
  unchecked inside A–F; superseded files have no pending lists. Index remains
  64 active milestones, 50 complete and 14 pending. Scribe evidence is unchanged.
- `git diff --check` passed. Independent Astra xhigh review found no material
  findings, including tool protocol gates, TTS settlement, context-reset boundaries
  and complete implementation ownership. Provider feasibility and cache usage
  measurements remain pending implementation acceptance, not research results.
- No runtime, live-provider or browser tests were run for documentation changes.
  No commit created.
