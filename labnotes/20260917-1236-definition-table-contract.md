# Definition table contract

## Scope

- Review the paginated tenant Call definitions table against the platform's stored definition
  model.
- Keep this page as a directory into filtered Calls results; do not introduce a definition details
  page.
- Correct the visible table structure and terminology before application implementation begins.

## Platform evidence

- `Vxpipe.Calls.Definitions.save/3` creates immutable revisions with `published_at: nil`.
- `Vxpipe.Calls.Definitions.publish/4` validates and publishes a selected revision.
- `Vxpipe.Persistence.DefinitionStore.publish_revision/5` stores that selection in
  `call_definitions.published_revision_id`, clears older published routes and activates routes for
  the selected revision.
- Publication state is therefore a supported platform concept. `Published` means the latest saved
  version is selected, `Draft` means no version is selected, and `Draft changes` means a newer saved
  version exists than the selected published version.
- The current backend has no operator definition-list endpoint yet. Its future summary must count
  calls across every version for the tenant and definition. `updatedAt` should come from the latest
  revision activity rather than relying on the parent definition row's timestamp.

## Decisions

- Use a semantic table with `Name`, `ID`, `Version`, `Calls`, `State`, and `Updated` columns. The
  previous independent header and row grids visibly drifted and did not expose accessible column
  associations.
- `Version` shows the latest saved version as `v<n>`.
- The Calls cell is the row's explicit action. It links to
  `/admin/tenants/:tenant_key/calls?definition_id=:definition_id`; names do not suggest an
  unsupported definition details page.
- The table has a 900 px minimum width inside its own horizontal scroller so narrow screens retain
  readable columns without causing page-level overflow.

## Verification

- Red: the focused page test failed because the old grid exposed `Definition`, had no Calls column,
  and linked the entire row as `Open <definition>`.
- Green: the focused seven-test Tenant definitions suite passes with the new headers, all-version
  counts, filtered Calls URLs, publication states, pagination and navigation behavior.
- The shared directory totals match the linked Full journey fixtures: 5, 2, 1, and 1 calls. Journey
  assertions verify the first two filtered destinations render exactly their advertised totals.
- The complete Console suite passes with 76 tests. TypeScript and ESLint pass.
- The shared React Storybook production build passes from `packages/react`; Vite reports only its
  existing dependency-directive and bundle-size advisories.
- Chrome inspection at 1440 x 900 confirmed aligned columns and explicit blue call-count links.
  Inspection at 390 x 844 confirmed the wide table remains inside the bordered horizontal scroller
  without page-level overflow. Light-mode inspection at 1280 x 800 confirmed neutral table surfaces
  and distinct publication badges without error-colored row backgrounds.
- GPT-6 Astra xhigh reviewed the persistence semantics and table structure. It confirmed the
  publication model and recommended the semantic table and all-version count contract.
