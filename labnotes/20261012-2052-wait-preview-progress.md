# Wait preview progress

- Initial compact controls committed first as bd95bb3d at the user's request.
- Motion plan: highlight the active audio control in the existing primary blue;
  keep a circular remaining-audio indicator tied to media time updates. Pause
  preserves position and progress; resume uses the same player. No time labels.
- Keep routine color feedback at 150ms and progress interpolation at 200ms.
  Reduced motion removes ring interpolation and loader rotation. No new library.
- Explicit idle/loading/playing/paused states handle buffering, stale play
  promises, unknown duration, completion, source replacement, and cleanup.
- Red: focused tests rejected missing playback states, progress and pause/resume.
- Green: 21 focused tests and all 594 frontend tests pass. Desktop default editor
  and mobile Storybook inspected with real audio playback, pause/resume and
  decreasing progress. TypeScript and lint also pass.
- Full umbrella gates passed: format, warnings-as-errors compile, strict Credo,
  3,572 tests with zero failures, and unused dependencies. This run began for
  the initial checkpoint; the follow-up changes only frontend playback controls.
  No Lean changes are needed.
- Reduced-motion browser check: computed ring transition property is none while
  remaining progress continues to update. Final production esbuild passes.
- Commit the playback follow-up as a separate checkpoint at the user's request.
