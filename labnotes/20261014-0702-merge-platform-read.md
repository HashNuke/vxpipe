# Merge platform read

## Approved contract

The user requested merging the confusing shared-service authoring grant into
Platform Services read. Tenant Call Specs read/write continues to gate editor
lookups and save/publish respectively. Platform read permits listing and using
shared telephony/model/voice services; platform write controls configuration.
The shared helper already feeds editor lookups, provider catalog, number listings
and call-spec authoring, so changing its grant keeps these boundaries consistent.

## Migration

Convert old authoring grants to installation-scoped Platform Services read, keep
existing reads, bump affected role revisions and remove the retired permission.
This intentionally grants metadata read to former authors, including Tenant Manager;
no configuration writes are added. Rollback cannot distinguish the origins of
merged grants and is therefore rejected. Dev and test migrations applied.

## Red-green evidence

- Updated Calls tests failed in six places before implementation: platform-owned
  telephony/apps/numbers, shared model credentials and authoring authorization.
- UI test failed while the old authoring checkbox remained.
- Disposable-database migration test failed with only one of two roles having
  Platform Services read, before the migration was added.
- Updated implementation: focused Calls tests pass (39), including tenant boundaries
  and denial of save/publish without Call Specs write or configuration mutation
  without Platform Services write.

- Migration integration passed (one selected test, five excluded), including roles
  with and without an existing Platform Services read grant and no added writes.
- Frontend run initially found two tests waiting on the now-removed Roles subtitle
  and one expecting Tenant Manager to lack the platform navigation group. Replaced
  subtitle waits with the Roles heading and updated the navigation assertion for
  the approved read grant. All 730 frontend tests, typecheck and lint then passed.
- Browser: create-role desktop/mobile showed Platform Services Read as the sole
  control for shared-service reads/use; the separate checkbox is absent.

## Final verification and layout refinement

The user replaced the separate scope rows with one row per action:
`[checkbox] Read [scope]` and `[checkbox] Write [scope]`. Both dropdowns remain
compact, aligned beside their labels on desktop and mobile. Existing scope tests
were updated first and failed on the old single-selector accessible names, then
passed with the new action-row layout. The full frontend suite again passed 730
tests, followed by TypeScript and ESLint. Browser inspection covered the requested
role-details page at desktop and 390px widths.

All five root checks ran. Formatting, warnings-as-errors compilation and strict
Credo passed. The 3,788-test umbrella run had one obsolete persistence assertion
that rejected every platform grant for Tenant Manager. Updated it to reject
platform writes, consistent with the exact expected read grants above it. The
complete persistence suite then passed (278 tests, zero failures, 18 excluded);
all other applications passed in the full run. Unused-dependency and whitespace
checks passed. The integration migration test passed separately.
