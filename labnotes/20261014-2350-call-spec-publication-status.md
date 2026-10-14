
## Implementation
- User requested only Draft/Published badges, with a subordinate indicator for
  saved edits newer than the published revision.
- Kept Published green and Draft amber. Unpublished changes appears below the
  Published badge in smaller muted text; hover retains exact revision details.
- The table regression failed before implementation (only one Published badge)
  and all nine focused table tests passed afterward. TypeScript and ESLint passed.

Rendered Chrome verification: desktop and 390px table with horizontal scrolling
show the Published badge and subordinate text correctly. CSS build passed.
Root checks were already running for the navigation changes: all 312 Console
tests passed; the umbrella had one unrelated speech deadline timing failure
whose 14-test file passed on rerun. No backend behavior changed for these labels.
