# Remove description summaries

- Corrected the incomplete Description removal: the specialist canvas card still
  displayed its saved description after the participant forms were changed.
- Human canvas cards now show their name and icon, consistently with agent cards.
  The Entry card retains call direction and participant key.
- Removed participant descriptions from transfer destination summaries and the
  destination picker. Search now matches visible participant keys only.
- Existing source JSON remains intact. This is presentation cleanup, with no
  runtime or schema migration.
- Red: 2 focused regressions failed on the old description text; 20 tests passed.
- Green: 22 focused tests pass; all 554 Console frontend tests pass. TypeScript,
  ESLint, format, compile with warnings as errors, strict Credo and unused
  dependency checks pass.
- Chrome inspection: the default editor on port 6006 shows just the human icon and
  specialist key at 1440 × 1000 and 390 × 844. The desktop transfer list and picker
  omit saved descriptions; removing and re-adding specialist still works.
- Root tests run with `--max-failures 1` to stop each suite after its first failure.
  The call engine again encounters the existing Ortex native-library loading
  failure (`mis-aligned LINKEDIT string pool`). Stopped the remaining umbrella
  run after reproducing that known failure; this is not a passing full-suite run.
- Temporary evidence: `vxpipe-description-summaries-red.log`,
  `vxpipe-description-summaries-frontend.log`,
  `vxpipe-description-summaries-mix-test.log`, and browser captures with the
  `vxpipe-description-summaries-` prefix.
