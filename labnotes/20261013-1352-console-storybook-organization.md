# Console Storybook organization

## First checkpoint: remove the sidebar hint

- Removed the unrequested tenant-selection hint and its unused CSS from the shared
  sidebar. Updated the sidebar contract to omit empty navigation groups silently.
- The focused regression was red before the removal and passes afterward.
- Reviewed the diff and rendered the tenant directory in desktop and phone Chrome.
  The hint is absent; the tenant picker remains available.
- Root formatting, compilation with warnings as errors, strict Credo and unused
  dependency checks pass. The complete frontend suite passes (711 tests).
- The first umbrella test process received SIGTERM before completion; rerunning
  the full suite. Section-based Storybook organization remains the next checkpoint.

## Second checkpoint: group editor components

- Kept Call spec editor as its own Console section and placed its eight component
  groups under `components`. The standalone editor Page stories retain their IDs.
- Reviewed the mechanical title-only diff. TypeScript, ESLint and Storybook build
  pass; the live index contains the new groups and editor page renders at desktop
  and phone sizes without a sidebar.
