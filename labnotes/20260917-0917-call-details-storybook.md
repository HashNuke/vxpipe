# Call details Storybook

## Scope

Implement checkpoint 4 of the operator-admin Storybook milestone. Compose the admin resource frame
around the existing `@vxpipe/react` CallConsole, supply deterministic inspection snapshots without
network or media access, and attach call selection in the linked review journey.

## Initial decisions

- Keep inspection state and controller construction outside the page component. The page owns only
  tenant/definition/call context, loading/error presentation, archive completeness, breadcrumbs,
  and the reusable console boundary.
- Reuse `@vxpipe/react` CSS and CallConsole directly. Do not copy console components or styles into
  the admin feature.
- Model malformed data separately from resource unavailability so Storybook can review both host
  failures without calling the inspection endpoint.

## Red-green-refactor evidence

- Host boundary tests were written first and failed because `CallDetailsPage` did not exist. The
  resulting page passes the injected controller, theme and bounded height to the real CallConsole
  and keeps loading, unavailable and malformed states outside it.
- The linked journey test was changed first to require Call details after call selection. It failed
  while the transitional Calls page remained mounted, then passed after the route composition used
  the selected call's definition-scoped fixture.
- Independent review found the first live adapter discarded composer submissions and reused
  connected-call events for calls that never started. Focused failing tests now require submitted
  text to enter the details store and require lifecycle-coherent timestamps, participant states,
  incarnation data and metrics.
- Individual-story and unknown-route breadcrumb tests were added after review found links that left
  the preview. Known resource links now record hash destinations; an unknown call retains only
  known tenant/call context and offers tenant recovery without a fabricated definition or revision.

## Rendered verification

- Chrome inspection covered ongoing, ended, partial archive, loading, unavailable and malformed
  states in dark mode, plus ended in light mode.
- At 390 px the page and console report matching client/scroll widths. The console remains bounded
  to 622 px in an 844 px viewport; its transcript owns vertical overflow while the composer stays
  in the console layout.
- Microphone state changes, Variables/Metrics/Participants tabs, tool details and composer submit
  work through the deterministic controller. Submitted text appears in the conversation.
- The ended story has no composer or live controls. Reduced-motion emulation disables skeleton
  animation. The complete journey reaches Call details, survives route reload, and returns through
  the definition breadcrumb and browser history without leaving the Storybook iframe.

## Automated verification

- `npm test`: 13 files, 54 tests passed.
- `npm run check`: passed.
- `npm run lint`: passed without warnings.
- `npm run build-storybook`: passed; only dependency directive and existing chunk-size warnings.
- `git diff --check`: passed.
- Independent GPT 6 Astra xhigh review cleared the checkpoint after the fixture lifecycle,
  composer, breadcrumb, unknown-call context and archive-copy corrections.

## Next checkpoint

Run the final full-journey acceptance pass across themes, widths, keyboard navigation, reduced
motion and long content, then present the linked Storybook flow for explicit user design approval.
