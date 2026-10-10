# Header name editing

## Scope and implementation

- Removed the duplicate call spec name field from Call settings. The existing
  header name button remains the form entry point for renaming.
- Shortened the full-source header action from View JSON to JSON and updated
  its Storybook interaction and existing tests.
- Name validation formerly navigated to Direction. It now opens the header rename
  dialog, focuses the name input and exposes the validation reason with the shared
  accessible field control. Name issues no longer belong to the Direction tab.
- Updated existing save/retry/navigation tests to rename through the header.
  The pending-save route test edits a participant prompt because the header's
  rename action is disabled during saves; it still verifies later edits survive
  URL replacement after creation.
- Explained the distinct transcription roles from the compiler and speech guide:
  human speech_to_text versus agent output_speech_to_text for STS without native
  output transcripts. No capability semantics or defaults controls changed.

## Verification

- Red: six expected failures for duplicate settings field, old JSON action label
  and name-issue navigation. After implementation, the related tests passed.
- First full frontend run: 523 passed, seven route tests still depended on the
  removed settings field. Updated those interactions; all 30 route/editor tests
  passed in the focused rerun.
- Root format, compile with warnings as errors, strict Credo and unused-lock checks
  passed. The full root test suite remains blocked by the Ortex native-loader
  failure recorded in editor-control-clarity labnotes; no backend code changed.
- Storybook stays on port 6006 in the existing checkout. No commits requested.
- Final full frontend suite: 530 tests across 69 files passed. Typecheck and ESLint
  passed; git diff whitespace checks passed.
- Chrome rendered inspection at 1440px and 390px confirmed Call settings starts
  with direction controls, with no duplicate name field. Header rename updated
  the title, and the JSON action opened the full source editor. The mobile sheet
  fit the viewport with its tab strip scrolling locally.
