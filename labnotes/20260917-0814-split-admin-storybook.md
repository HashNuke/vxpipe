# Split operator admin Storybook milestone

## Goal

Move all operator admin UI design into a complete Storybook milestone that the user reviews before
any production application integration begins.

## Progress

- Added a dedicated Operator admin Storybook milestone before operator login/admin integration.
- Split the mocked journey into shell, tenants, tenant definitions, definition calls, call details
  and complete-journey checkpoints.
- Removed Storybook construction checkpoints from the production integration milestone.
- Renumbered the milestone index and synchronized the developer-experience delivery order.

## Decisions

- Login/auth pages remain Phoenix-rendered and are excluded from Storybook design work.
- Every `/admin` page is built from small React components into a complete mocked page.
- The full Storybook must be presented to the user for explicit design approval.
- No auth, persistence, query, endpoint or production route work starts before that approval.
- After approval, production proceeds as small vertical slices: auth, tenants, definitions,
  definition-scoped calls and call details.

## Verification

- Independent GPT 6 Astra xhigh review found no blocking or nonblocking issues.
- All four admin pages have matching Storybook and production integration checkpoints.
- The Storybook milestone excludes auth, backend, endpoint clients and production routes.
- The implementation milestone cannot begin until explicit user approval is recorded.
- The index contains 31 ordered milestones and the declared 22-complete/9-incomplete count.
- Local Markdown links resolve and `git diff --check` passes.
- No runtime code or schema changed; no runtime test was applicable.
