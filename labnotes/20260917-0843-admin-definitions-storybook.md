# Admin definitions Storybook

## Scope

Implement checkpoint 2 of the operator-admin Storybook milestone: render a selected tenant's call
definitions and connect the first two pages of the review journey. This checkpoint remains entirely
inside deterministic Storybook state and does not add production routes, clients, or persistence.

## Source findings and decisions

- `CallDefinition` persists a tenant-scoped `public_id`, current published revision, and publication
  time. Immutable `DefinitionRevision` rows own revision number, source, validation errors, and
  insertion time.
- The definition source has an optional `name` (up to 256 characters). The UI therefore shows the
  source name when available and falls back to the public definition ID.
- Definition summaries distinguish three honest states: **Published** when the latest revision is
  published, **Draft** when no revision is published, and **Draft changes** when an older revision
  remains published while a newer draft exists.
- Real links use
  `/admin/tenants/:tenant_key/definitions/:definition_id`. Presentation components receive typed
  state and injected actions; fixtures and story navigation remain separate.
- Shared concerns were extracted rather than added to either page: breadcrumbs, modified-click
  detection, local date formatting, generic pagination labeling, route parsing, and the Storybook
  navigation hook each have one responsibility.
- **Admin / Full journey** is present from this checkpoint onward. It currently connects Tenants →
  Tenant definitions and back through the real page components. Later checkpoints extend the same
  route model and story.

## Red-green-refactor evidence

- The page contracts were written before `TenantDefinitionsPage` and initially failed because that
  module did not exist.
- Story pagination and reload-safe forward/back destination tests were added before
  `TenantDefinitionsStory` and initially failed because that module did not exist.
- The linked journey test was added before `AdminJourneyStory` and initially failed because that
  module did not exist.
- The green contracts cover tenant context and breadcrumbs, real definition links, all publication
  states, name fallback, empty versus unavailable results, valid pagination actions, stale-action
  removal during loading, reloadable story URLs, and tenant-directory navigation back and forth.
- A component/helper filename pair differing only by capitalization confused Vite on the default
  case-insensitive macOS filesystem. The status component and pure state helper now have distinct
  names (`DefinitionStatusBadge` and `getDefinitionStatus`).

## Rendered verification

- Dark and light desktop definition directories rendered with neutral surfaces and semantic green,
  amber, and blue state badges; no ordinary row uses an error-like pink/red background.
- The 390 × 844 narrow view and long-content fixture have no document overflow. Mobile rows keep
  definition, revision, state, and open affordance aligned on one row.
- Independent review found that the desktop columns activated at 640 px even though their minimum
  width required roughly 820 px, so the containing surface clipped Updated and the open arrow at
  768 px. The full column set now activates at 1024 px; 640 px and 768 px retain the compact layout.
- Review also found that the initial Full journey omitted the injected definition-selection action,
  so its real link left Storybook before the calls page existed. A red-first regression now keeps
  that selection in the hash route and the reloadable preview while retaining the definitions page;
  checkpoint 3 will attach the calls page to this already modeled route.
- Loading, empty, unavailable, populated, mixed publication, long-content, paginated, and narrow
  states were inspected in Chrome. Pagination reaches page 3 and disables Next.
- Browser back and forward traverse the linked Tenants ↔ Tenant definitions journey while retaining
  the selected tenant hash route and reloadable Storybook iframe URL.
- With reduced motion emulated, the loading skeleton's computed `animation-name` is `none`.

## Automated verification

- `npm test`: 10 files, 37 tests passed before final documentation changes.
- `npm run check`: passed.
- `npm run lint`: passed without warnings after separating the pure publication-state function from
  the React component module.
- `git diff --check`: passed.

## Next checkpoint

Build the definition-scoped calls page, extend the route model and Full journey through call
selection, and retain both tenant and definition context in breadcrumbs and page state.
