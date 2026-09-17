# Definition calls Storybook

## Scope

Implement checkpoint 3 of the operator-admin Storybook milestone: render calls scoped to a selected
definition across its revisions, and extend the linked review journey through call selection. This
checkpoint remains deterministic frontend work and adds no endpoint or production route.

## Source findings and decisions

- The Calls read model exposes UUID call ID, tenant/definition identity, immutable definition
  revision, lifecycle state, created/started/ended timestamps, optional terminal reason, and latest
  variable revision.
- Lifecycle states are `prepared`, `admitting`, `running`, `ended`, and `failed`. The UI labels
  `running` as **Ongoing** while preserving the typed source state.
- Archive completeness is a separate Calls contract with `complete`, `incomplete`, and
  `unconfirmed`. The UI labels these **Complete**, **Partial**, and **Unconfirmed** and never infers
  archive success from lifecycle completion.
- Call rows use the approved tenant-scoped link
  `/admin/tenants/:tenant_key/calls/:call_id`. Definition revision, local started time, terminal
  reason, derived ended-call duration, and archive state remain visible without exposing call
  payloads.
- The list view model includes archive state even though today's bounded `CallSummary` list query
  does not. The later production checkpoint must deliberately provide that safe summary rather than
  fabricate it in React.
- **Admin / Full journey** now renders Tenants → Tenant definitions → Definition calls. Selecting a
  call records the future call-details path and keeps the calls page mounted until checkpoint 4
  supplies the actual console host.

## Red-green-refactor evidence

- Page contracts were written first and failed because `DefinitionCallsPage` did not exist.
- Story pagination and reload-safe call/breadcrumb destination tests were written first and failed
  because `DefinitionCallsStory` did not exist.
- The existing linked-journey test was changed first to expect the Calls page after definition
  selection and a safe call-details destination after call selection. It failed while the route
  still rendered definitions, then passed after the route model and composition were extended.
- Green contracts cover tenant/definition breadcrumbs, real call links, lifecycle/archive states,
  definition revision, duration, terminal reason, empty versus unavailable states, valid
  pagination, loading action removal, and reload-safe mocked navigation.
- A final red-first contract prevents prepared/admitting `created_at` from being shown under the
  Started column. Compact rows label that fallback explicitly as Created; the desktop Started cell
  stays unavailable until `started_at` exists.
- Independent review found that the first journey fixture reused Delivery calls after selecting a
  different definition. Definition-keyed call fixtures and a call-ID lookup now preserve the
  selected definition and its valid revisions through selection and reload. Unknown call IDs show
  an unavailable state instead of silently substituting another definition.
- Independent review also found that paginated fixtures overwrote nullable start times without
  shifting end times. A red-first regression now keeps null starts null and shifts every existing
  timestamp by the same offset, preserving ended-call durations.

## Rendered verification

- Dark and light desktop views render ongoing, ended, failed, admitting, and prepared calls. Error
  color appears only on the failed lifecycle badge; partial archive uses amber and ordinary rows
  remain neutral.
- The 390 px long-content view keeps call identity, lifecycle, archive, and open affordance inside
  each row with no horizontal overflow. The 768 px compact and 1024 px full-column layouts likewise
  report row scroll width equal to client width. Shared fixed tracks align the State and Archive
  headers with their cells at all three widths.
- Loading, empty, unavailable, populated, long-content, paginated, narrow, dark, and light states
  were inspected in Chrome. Pagination reaches page 3 and disables Next.
- Reduced-motion emulation disables the loading skeleton animation.
- The full journey reaches calls, records a tenant call-details URL on selection, survives reload,
  and returns through browser history to the definition calls route.

## Automated verification

- `npm test`: 11 files, 48 tests passed after the fixture corrections.
- `npm run check`: passed.
- `npm run lint`: passed without warnings.
- `git diff --check`: passed.

## Next checkpoint

Build the admin call-details host around the real `@vxpipe/react` console and its existing
inspection fixtures, then replace the transitional call-selection behavior in Full journey with
that host page.
