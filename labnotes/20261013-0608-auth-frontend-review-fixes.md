# Auth frontend review fixes (2026-10-13)

## Scope
- Frontend only: `apps/vxpipe_console/assets/src/`. No Elixir/config/docs edits. No commit.
- Task: fix production auth React review findings; preserve root lint fixes (useMemo import/ref/unused init).
- Coordination: `src/App.test.tsx` is owned by the concurrent App.test-migration
  lane (session mocks + heading updates) — NOT edited here. Other lanes are
  actively editing this worktree (UsersPage heading, CallSpecEditor, Identity);
  test files observed changing mid-session.

## Baseline
- `npm run lint`: clean. `npm run check`: clean.
- `npm run test`: 642 passed, 10 failed — all in `src/App.test.tsx` operational routes.
  Cause: `RoutedApp` now fetches `/admin/api/session` for principal-derived
  gating, but legacy operational mocks use `vi.fn(() => response(...))` with
  `mockImplementationOnce` ordering that assumes the first fetch is the tenant
  call. Owned by the migration lane; left untouched.
- Already fixed in worktree (verified, not regressed):
  - `RolesRoute` uses authoritative `GET /admin/api/roles/:id affected_users`;
    list shows `Users: see details` when missing; no user-directory paging.
  - `AuthenticationApi.tenantOptions()` follows all server pages (unbounded);
    tests cover 12 pages.
  - `OperationalAccountLinks` + `AccessFrame` gate Account/Users/Roles.
  - Empty directory stays put for zero-assignment members (`canCreateTenants` gate).
  - `PermissionEditor` preserves mixed read/write scopes via dual selects
    (plus `mixed-scopes` Storybook variant).
  - `TenantAccessEditor` labels persisted `read_write` as `read & write`.
  - `AccountRoute` redirects to `/auth/login` with notice after password change;
    `updateAccount` sends `password_confirmation`.

## Changes made (this lane)
1. `src/App.tsx` — principal-null gating in `RoutedApp` (red-green, new
   `src/App.principal.test.tsx` with 3 tests, confirmed red before fix):
   - `headerActions` fallback shows only Sign out (was: Platform services link).
   - `canCreate` is `!!principal && canCreateCallSpecs(...)` (was: default true).
   - `canConnect` is `principal ? ... : false` (was: default true).
   - `workspaceDestinations` fallback is `gatedDestinations ?? []` (was: full
     list); removed the now-unused full-list const.
2. `src/admin/authentication/authenticationApi.ts` — removed dead single-page
   `tenants()` helper (unused; only `tenantOptions()` is called). Prevents any
   future caller silently treating page 1 as the full directory.
3. `src/App.principal.test.tsx` — new; 3 tests for loading-principal hiding
   of Platform services / Account links / New call spec / Services destination
   / Connect controls.

## Verification evidence
- Red: `App.principal.test.tsx` 3/3 failed before the `App.tsx` fix (privileged
  UI rendered with pending session); green after.
- `npx vitest run src/App.principal.test.tsx src/App.auth.test.tsx
  src/admin/authentication/`: 10 files, 61 tests, all pass (includes 2 new
  `local Superadmin recovery` App.auth tests added concurrently by another lane).
- `npm run lint`: clean. `npm run check` (tsc --noEmit): clean. Root
  `useMemo`/`useLocation`/`shouldInterceptNavigation` imports preserved.
- Full frontend suite excluding `App.test.tsx`: 628 passed + 3 failed in a
  211s run under heavy concurrent load; all 3 (App.auth recovery,
  CallSpecEditorRoute history-back, flow-editor agent-prompt) pass in isolation
  and live in files being actively edited by other lanes — flakiness from
  concurrent worktree mutation, not this change. Full suite incl. App.test was
  not re-run to completion here (migration lane owns those 10 reds).
- No visual Storybook/browser inspection possible in this environment (no
  browser tooling); rendered checks are DOM-assertion based. `storybook-static/`
  predates this change. Stories compile via tsc; `mixed-scopes`/`mixed`
  variants cover the PermissionEditor/TenantAccessEditor findings.
- Contract gaps reported in `vxpipe-auth-frontend-contract-notes.txt (temporary review output)`.
