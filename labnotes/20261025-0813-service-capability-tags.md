# Service capability tags

- User requested that capabilities remain individual tags, rather than phrases
  separated by middle dots. The directory was the remaining affected surface;
  credential modals already used the existing tag styling.
- Reused the existing setup-tags markup and styling for all directory providers,
  with an 8px gap below the service name. Shared tenant/platform directory entries
  now match their credential dialogs, with wrapping tags on mobile.
- Presentation-only change: no added behavior test. Existing focused coverage
  passed (19 tests), along with TypeScript, ESLint and whitespace checks.
- Inspected rendered desktop (1440px) and mobile (390px) layouts in Chrome.
  Tags are individually bordered, wrap within each row and preserve Connect.
- Earlier full frontend and umbrella checks passed for this same checkpoint;
  this correction changes only directory markup and spacing.
- No design suppressions or backend changes. No commit requested.
