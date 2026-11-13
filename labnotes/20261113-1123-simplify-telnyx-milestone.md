# Simplify Telnyx milestone

## Scope

- User asked to review the milestone again and avoid overengineering. This review
  changes the milestone, design note and index only; existing code edits remain.
- Read the current plan, design, planning/implementation records, application
  migration/store, route-store boundaries and existing focused-test output.
- Retain the user's no-legacy-fallback instruction recorded in the implementation
  goal: migrate data as needed rather than maintain parallel runtime contracts.

## Findings and changes

- Reduced three checkpoints from 12 tasks to nine: persist configuration, route
  shared calls, then connect/verify the production modal. Kept independent section
  resets, atomic saves, existing permissions and masking as observable contracts.
- Corrected a substantive overreach: the scoped application unique index need not
  be removed. It covers explicit IDs, while inheriting tenants store null. Shared
  default resolution must change; explicit application uniqueness can remain.
- Keep dedicated overrides separate from the shared platform application through
  ordinary validation. No application modes, account discovery, endpoint families,
  revision-token scheme, or new routing/deduplication subsystem is prescribed.
- Removed old platform-delivery compatibility requirements. Migration and the one
  selected webhook rule own the transition.
- Retained signature verification, number conflicts and duplicate admission checks
  because shared routing changes real tenant/call boundaries. Conflict checks also
  apply when saving settings changes an effective application.
- The recorded user response requested a concrete URL consequence before deciding.
  The implementation labnote assumed application-based URLs, but there is no
  recorded explicit answer. Kept this as a recommendation and included the Acme /
  Bravo example instead of describing it as an approved decision.
- Corrected stale "implementation not started" language: application-default work
  exists, but none of the complete checkpoints has passed acceptance.

## Verification

- Rechecked first-party Telnyx application and webhook references. Application
  configuration controls the default incoming webhook; command overrides do not
  by themselves split initial incoming events for tenants sharing an application.
- Read existing focused logs: application-default regression has 23 tests and zero
  failures; the aggregate save test has three failures because its API module is
  not implemented yet. These are previous runs, not new checks in this review.
- Documentation checks passed: relative links, balanced code fences, three
  checkpoints, nine unchecked tasks, the review anchor, and 62 ordered index
  entries (48 complete, 14 incomplete). `git diff --check` passed.
- No runtime or browser tests were run for this documentation-only change. No
  implementation task is checked off; the implementation goal remains incomplete.
