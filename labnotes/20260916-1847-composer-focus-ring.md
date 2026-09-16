# Composer focus ring

## Decision

The composer form already communicates focus by changing its border to the
focus color through `:focus-within`. The shared console focus rule was more
specific than the textarea's base `outline: none`, so focusing the textarea
also drew a second blue outline inside the form.

Keep the form-level focus treatment and suppress the textarea's own visible
outline only when it is inside the composer. Other console controls retain the
shared keyboard focus ring.

## Verification

- Storybook conversation story inspected in Chrome at 1440 × 1000 with the
  composer textarea focused. Its computed outline style was `none`, the form
  matched `:focus-within`, and the form retained its focus-color border.
- The focused composer was also inspected at 390 × 844; only the outer focus
  border is visible in the mobile layout.
- `npm test -- --run` from `packages/react`: 29 tests passed.
- `npm run check` from the workspace root: package builds and TypeScript checks
  passed.
