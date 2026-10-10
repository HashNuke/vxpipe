# Editor control clarity

## Scope

- Review the workflow diagram and sidebar controls after user feedback: agent cards
  need name-only headings and counts of variables; secondary buttons and tabs need
  obvious click targets and active states.
- Preserve the existing dark/light Console theme and primary Publish emphasis.
- Use the existing checkout and Storybook server at port 6006. Earlier editor JSON
  and model changes remain in the worktree; no commits requested.

## Focused design review

- Secondary buttons have no border and share a low-contrast neutral fill with other
  surfaces. Outline buttons have a faint border and a 30% translucent fill. These
  weaken action discovery in the header, toolbar and sidebar.
- Button/tab computed cursor is `default`, supplying no pointer feedback.
- Active line tabs render their underline at bottom -5px, outside the tab bar's
  overflow container. The indicator is clipped, leaving only a text-weight/color cue.
- Agent cards project description or prompt into the subtitle. That duplicates the
  inspector content and competes with the participant name while scanning transfers.
- Variable badge currently counts permission-section keys, including read-only and
  stale grants. Count declared top-level variables in writable sections; nested
  object properties belong to their top-level variable and count once.

## Verification plan

- Red/green tests for projected agent card content and visible badge wording.
- Render dark/light desktop and phone views, checking button contrast, active tabs,
  keyboard focus, hover, disabled state, card counts and overflow.
- Run frontend suite/typecheck/lint and required umbrella checks. The prior root
  suite hit a local Ortex NIF loading failure; record any repeated limitation.

## Implementation and feedback

- Removed agent prompt/description previews from graph cards. Count top-level
  properties in declared writable sections and label the badge variable/variables.
  Exclude read-only, missing and empty sections; preserve human/entry subtitles.
- Gave secondary and outline actions a visible shared control border, hover fill
  and pointer cursor. Participant JSON uses the same outline button treatment.
- Initial outlined tabs looked like separate buttons and wrapped awkwardly. User
  rejected that treatment and requested the linked shadcn Tabs styling. Restored
  the shared Tabs component and used its default segmented variant in inspectors.
- User then identified uneven tab spacing: `min-w-full` stretched the list and
  inherited `flex-1` stretched triggers. Removed the minimum width and used
  `flex-none` on inspector triggers. Labels now keep equal standard padding;
  the single tab row scrolls horizontally when necessary.
- Kept the existing checkout and port 6006. No commits made; preserved unrelated
  package-lock.json, .codex/hooks.json and vxpipe-docs changes.

## Verification evidence

- Red: five focused failures for the old subtitle and section-count behavior.
  Green: eight layout/card tests after implementation.
- Full frontend suite: 529 tests across 69 files passed. Final focused inspector
  and graph suite: 35 tests across five files passed.
- Typecheck initially caught a union-tuple `.includes` argument restriction;
  changed the permission predicate to `.some`. Typecheck and ESLint passed.
- Storybook production build passed; existing large-chunk advisory remains.
- Rendered Chrome inspection covered dark/light themes, desktop and phone widths,
  agent cards, settings/participant tabs, secondary controls and focus/hover states.
  Final desktop tab measurements show 9px from each label to each outer edge
  (8px padding plus 1px border), with `flex: 0 0 auto` throughout. ArrowRight
  switched Direction to Defaults and updated the visible panel. At 390px, the
  sheet and page both fit the viewport; End selected Media and scrolled the tab
  row into view. Mobile labels retained the same measured padding as desktop.
- Root format, compile with warnings as errors, strict Credo and unused-lock
  checks passed. Root tests encountered the existing Ortex native-loader failure
  (`mis-aligned LINKEDIT string pool`) in speech tests. Stopped the continuing
  umbrella run after confirming that blocker; the full root suite is not green.
- No speech-state-machine or source-cutover implementation changes; Lean lane
  does not apply.
