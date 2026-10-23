# Simplify media settings

## Scope and decision

- Calls have an entry caller or callee plus one other participant at a time. The user approved removing source-to-recipient routing controls from ordinary Media settings.
- Keep only Record audio and Save transcripts in call settings and participant/entry inspectors, using the same responsive rows throughout.
- Retain existing `audio_routes` and `transcript_routes` in saved documents, including explicit empty restrictions. Backend routing semantics and JSON support remain unchanged.
- The existing policy edit path clones the entire policy before changing a storage permission, so this needs no backend migration or runtime changes.
- Updated the editor guide to describe the two storage controls in all Media tabs and the preservation of existing routing rules.

## Verification

- Updated focused tests first to cover the two-control UI and preservation of populated/empty route maps while changing or clearing storage permissions at call, entry, AI-agent, and human-participant scope.
- Red: the updated settings-panel suite failed four cases because participant Media still exposed routing selectors and source rows.
- Green: all 53 tests across settings panels, agent inspectors, human/entry inspectors, and call settings passed after removing the routing UI.
- Browser inspection with headless Chrome covered call settings, AI-agent, human-participant, and outgoing-entry Media at 1440 × 1000 and 390 × 844, across dark and light themes. Each tab exposes two storage controls; desktop rows align and mobile fields stack without horizontal overflow. The human story's existing transcript routing remained visible in participant JSON.
- TypeScript, ESLint, CSS build, root format check, warnings-as-errors compilation, strict Credo, unused dependency-lock check, and `git diff --check` passed. The Impeccable layout scan found no issues; no suppressions or further design changes were needed.
- The first full frontend run passed 771 tests with one intermittent save/unload-guard failure outside Media. Its 28-test file passed when rerun unchanged; the complete rerun with two workers passed all 98 files and 772 tests. No unrelated code was changed.
- The complete root `mix test` run passed: 3,811 reported tests, zero failures, 134 excluded. It ran against a task-owned temporary database, which was removed successfully after completion.
