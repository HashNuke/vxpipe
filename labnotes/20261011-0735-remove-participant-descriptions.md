# Remove participant descriptions

## Decision

- Follow the user's correction: remove Description from agent, human destination
  and Entry forms. This supersedes the earlier decision to retain those controls.
- Existing optional description values are preserved in source JSON. The runtime
  can still include them in transfer-tool schemas; no data migration is needed.
- Transfer instructions can live in the agent prompt and refer to participant
  keys. A separate description input is unnecessary for this workflow.
- Description validation issues now use the issue list rather than linking to a
  removed field. Updated the editor guide and source documentation accordingly.

## Verification

- Red: focused inspector and issue-location tests failed on visible Description
  controls and stale links to those controls (4 failures, 78 passes).
- Green: all 82 focused tests pass. Full Console frontend suite: 553 tests across
  71 files pass; TypeScript and ESLint pass.
- Chrome review in Storybook on port 6006: agent Prompt, human Connection and
  Entry Connection forms inspected at 1440 × 1000 and 390 × 844. Description is
  absent in all three forms, with the remaining fields laid out correctly.
- Root format, compile with warnings as errors, strict Credo and unused dependency
  checks pass.
- Root `mix test` rerun reproduced the existing Ortex macOS native-library error
  (`mis-aligned LINKEDIT string pool`). Stopped this rerun after the known failures
  appeared; it is not a passing or complete umbrella run. The preceding completed
  run is recorded in the compact voice filter labnotes. No Elixir files changed.
- Logs: `vxpipe-description-red.log`, `vxpipe-description-green.log`,
  `vxpipe-description-frontend.log` and `vxpipe-description-mix-test.log` in the
  temporary verification directory. Browser screenshots use the
  `vxpipe-description-` prefix there.
