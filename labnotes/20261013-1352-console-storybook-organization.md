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
