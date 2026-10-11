# Agent model controls

## Scope and findings

- User requested a Models tab, one effective First message choice without a
  duplicate Default item, mutually exclusive STS versus LLM/TTS controls for agents,
  and STT only on human participants.
- Existing participant controls listed all five capabilities for every participant.
- Backend first-message defaults are wait-for-input for incoming agents and generated
  for the initial outgoing handler. Preserved that contract while simplifying the UI.
- Backend capability defaults inherit independently and cannot be disabled per agent.
  Mode changes therefore materialize only incompatible defaults on other agents before
  removing them. Existing explicit overrides and human STT stay intact.
- Checkout setup was already completed in this checkout during the sidebar task;
  Storybook remains on port 6006. No new worktree or dependency changes are needed.

## Checkpoint evidence

- Red: focused inspector tests failed in eight expected cases for the old label,
  duplicate first-message choice, missing model-type control, and unfiltered capabilities.
- Green: all 26 agent/human inspector tests pass, including source preservation on load,
  outgoing first-message overrides, both model-type transitions, inherited defaults,
  other participants' selections, and read-only controls.
- The initial section assertion also counted nested Options regions; narrowed it to
  capability regions so it tests the model choices rather than unrelated nested fields.
- Updated model stories and the editor guide/source contract documentation.
- Design hook reported the existing DESIGN.md/sidecar timestamp mismatch; this task
  follows the source design document and does not regenerate design metadata.
- Initial checkpoint: all 515 frontend tests, typecheck and lint passed before the
  follow-up JSON changes. Final verification evidence is recorded below.


## Follow-up simplification and JSON editing

- User requested side-by-side provider/model controls, removal of credential selectors
  and recommendation suffixes, and the Media tab label. Inherited model choices now
  show their effective provider/model directly, without "Participant override" copy.
- First compacted generic option rows, then removed that layout after user requested
  removing both Options and Provider options in favor of JSON editing. Restored the
  existing structured-value editor used by schema controls; those controls are unchanged.
- Added a participant JSON toggle in agent, human destination and entry headers. The
  full-source sheet is editable too. Apply validates and updates the local source;
  Save draft remains the persistence boundary. Existing advanced settings are preserved.
- Red: eight expected failures for the missing JSON workflows and remaining option UI.
  A second red pass exposed draft-review recovery cases; pending edits now survive
  selection changes and removed participants remain reviewable/discardable.
- Drafts retain their starting source to detect conflicting changes. Unapplied edits
  block saving and participate in leave protection. Large option integers stay exact.
- The milestone index referenced by AGENTS.md is absent in this checkout. Updated the
  existing editor guide and source-contract document for these focused UI changes.
- Design hook: no deterministic findings in changed model/editor components. Earlier
  findings in unchanged admin.css (including brand-logo colors) remain standing;
  no suppressions or unrelated style changes were introduced.


## Verification

- The final frontend suite passed 524 tests across 68 files. A final focused
  recovery check also covers Retry after a failed save: unapplied JSON must be
  reviewed before retrying. Its initial red test observed two save requests; after
  the fix all 21 full-editor tests passed.
- TypeScript check and ESLint passed after the final retry fix. Storybook production
  build passed; it retains the existing bundle-size warning.
- Rendered Chrome checks at 1440×1000 and 390×844 covered Models with side-by-side
  provider/model controls, Speech-to-Speech without LLM/TTS/STT fields, participant
  JSON, and full JSON. Verified a syntax error, discard and successful full-source
  Apply; the heading updated and the draft became saveable. No layout fixes needed.
- The first full-sheet phone capture caught its opening animation. A settled capture
  confirmed the sheet fills the phone viewport and all controls fit.
- Root format check, warnings-as-errors compile, strict Credo and unused-dependency
  check passed. Root mix test encountered the existing Ortex NIF load failure
  (macOS "mis-aligned LINKEDIT string pool") and cascading speech failures; stopped
  that run rather than claiming a completed green suite. No Elixir changes were made.
- Storybook is still running at localhost:6006; its port reservation reports 6006.
- No commits created. Existing package-lock changes and untracked vxpipe-docs remain
  untouched.
