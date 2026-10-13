# Console authentication plan

Date: 2026-10-13. Scope: milestone planning and supporting architecture decision only.

## Findings and decisions

- Started with a clean worktree and read the milestone index, completed operator-login,
  tenant administration and editor prerequisites, accepted scoped-services follow-up,
  and related ownership/API-key/demo documents. Inspected current router, session,
  authoring and installation schema boundaries.
- Proposed Admin, Platform Manager, Tenant Manager and Tenant Member names. Initially
  chose fixed global roles plus per-tenant member Read/ReadWrite assignments; the user's
  follow-up below supersedes fixed non-admin roles with configurable permission bundles.
  Asked whether Tenant Managers should manage users; no response received during planning.
  Recorded no user management for that role as an explicit proposed default, along with
  a single assignment level covering both calls and call specs.
- The existing installation singleton requires a demo tenant, so reusing it directly
  would couple first-admin setup to demo onboarding. Chose a separate typed authentication
  singleton over a generic config store or user-count inference.
- Existing browser grants have no named user or persisted session revocation. Planned
  explicit cutover, upgrade-only setup proof, persistent sessions and stream revocation.
  Machine API keys retain independent lifecycles and existing service-authoring rules.
- Separated identity workflows into a proposed database-neutral Identity application;
  Persistence implements ports, Console handles browser flows, Calls checks user authority.
- Reviewed setup races, upgrade takeover, last-Admin concurrency, creator-session
  preservation and peer-role escalation. Added focused acceptance gates and safe defaults.
  Local design review is recorded separately from runtime progress in the milestone.

## Work and verification

- `bin/setup` completed dependency/assets setup and development/test database migrations.
  No live credentials or live services were used; the forbidden provider file was not read.
- Consulted official Phoenix auth and OWASP password-storage/authorization documentation;
  source links and limits of their application are in the decision document.
- Added the milestone before delivery, keeping all implementation/acceptance boxes open;
  updated index totals and linked the historical login milestone to its proposed successor.
- Final documentation verification passed for five changed/new documents and 174 local
  links, whitespace, consecutive index ordering, 45 milestones (34 complete/11 incomplete)
  and all 30 new implementation tasks remaining open. `git diff --check` passed.
  An initial checker guessed 32 tasks and failed that assertion; corrected the checker
  to count actual tasks and verify none were checked, then reran successfully.
  Runtime suites and rendered browser inspection are not applicable to this documentation-only
  change; the milestone explicitly requires them during implementation.

## Barriers and limits

- A guessed `docs/development/worktree-setup.md` reference did not exist; no new document
  depends on it. Used the actual setup script and existing milestone contracts.
- Initial combined document reads exceeded output limits; narrowed subsequent reads to
  relevant contract sections and concrete source files. No independent agent review was run.
- No authentication code, migrations or UI were implemented. No commit was requested or made.

## Follow-up — permission-based role definitions

- User questioned fixed roles and requested an extensible permission-based definition
  except for Admin. Revised the decision, milestone and index: Admin is protected;
  ordinary roles are editable database records seeded from the initial three templates.
- Added permission catalog, scoped role grants and allowed management-target relations.
  One role per user remains sufficient; assignments cap assigned-tenant grants rather
  than supplying capabilities. New actions default to absent from ordinary roles.
- Added Admin-only role-management UI and acceptance checks. Custom roles now belong
  to this milestone, with inheritance/multiple-role unions/user overrides deferred.
- Reviewed editable-role escalation: delegation requires an explicit allowlist plus
  current grant/scope containment. Non-admins cannot manage themselves, their own role,
  Admins or another user-managing role. Role edits revoke affected sessions; stale
  management targets and open forms cannot retain old authority.
- Existing setup verification from this checkout remains applicable; changes are
  documentation only. Rechecked links, whitespace, index totals and open implementation
  tasks after the revision; results are recorded below.
- Follow-up checks passed: five documents, 174 local links, 45 ordered milestones
  (34 complete/11 incomplete), all 33 implementation tasks open, and `git diff --check`.
  No runtime tests or browser checks were claimed for this documentation change.

## Follow-up — built-in administrators and tenant scope

- Latest user clarification introduces protected Superadmin and Admin roles. Only
  Superadmins add Admins; both built-ins add ordinary users. Ordinary roles retain
  configurable operational permissions but lose all account-management authority.
- Confirmed calls and call specs are tenant resources; all/assigned tenants are grant
  selectors. Platform services and user-directory permissions are installation-scoped.
  Adopted `users.read/write`, with `users.write` reserved to built-ins, plus symmetric
  `calls.read/write` and `call_specs.read/write` permission names.
- Proposed a first-Superadmin setup account, Superadmin-only creation of further
  Superadmins, and last-enabled-Superadmin protection. Extended the requested creation
  hierarchy to promotion/reset/demotion/disable to prevent privileged-account takeover.
- Both built-ins may edit ordinary role definitions; protected system kinds and reserved
  grants cannot be changed through those endpoints. Optional ordinary `users.read` is
  explicitly a read-only directory capability, absent from all initial templates.
- Removed the prior management-target relation, containment algorithm and delegation UI
  from the current specification. Earlier entries above describe superseded proposals.
  Updated schema, setup/recovery, checkpoints, design review and index consistently.
- Documentation-only follow-up; the checkout's completed setup remains valid. No runtime
  changes, commits or claims of browser/runtime acceptance.
- Verification passed: five documents, 174 local links, 45 ordered milestones with
  34 complete/11 incomplete, all 33 tasks open, stale schema/permission checks and
  `git diff --check`. An initial stale-text check matched the sentence explicitly
  rejecting a last-Admin invariant; narrowed that check and reran successfully.

## Follow-up — privileged resets and directory filters

- User confirmed Admins may view Admin/Superadmin accounts through `users.read` and
  cannot perform any administrative changes to them. Explicitly covered password
  resets, tenant assignments, session revocation and bulk mutations. Authenticated
  self-service password changes remain distinct from administrative resets.
- Added role filters to `/admin/users`: All roles, both built-ins and ordinary roles,
  stable public IDs, server-side filtering before pagination/counts, combined search,
  URL persistence, page reset and empty/invalid states. Read-only viewers receive
  minimal role metadata; Admins can still view protected accounts without edit controls.
- Updated focused acceptance and rendered checks plus the separate design-review record.
  This remains documentation only; implementation and index completion remain open.
- Verification passed: five documents, 174 local links, whitespace, unchanged index
  totals/order, all 34 implementation tasks open and `git diff --check`.

## Follow-up — explicit privileged-user permission keys

- User proposed `users.admins.write` and `users.superadmins.write` alongside
  `users.read` and `users.write`. Adopted exact independent keys: ordinary-user writes
  do not imply either privileged write, and the privileged keys do not imply each other.
- Admin holds the read and ordinary-write keys; Superadmin holds all four. Kept account
  writes reserved to built-ins per the earlier explicit restriction. Directory read
  remains independently grantable to ordinary roles.
- Target system kind selects the required write; creation checks requested kind,
  updates/resets check current kind, and role changes check both. Applied this to bulk
  operations and transactional rechecks, preventing promotion/demotion bypasses.
- Updated the decision, milestone and design-review record with exact-match and grant
  acceptance checks. No schema-table or index completion changes are needed.
- Documentation checks passed for five files, 174 local links, all four user permission
  keys, 34 open tasks and unchanged index totals/order; `git diff --check` passed.
  No runtime code or tests changed, and no commit was made.

## Follow-up — consistent user-category naming

- Renamed the ordinary-account permission to `users.members.write`, alongside
  `users.admins.write` and `users.superadmins.write`; `users.read` remains shared.
- Clarified that members includes all custom-role accounts, including both Manager
  templates. It is independent of tenant membership and the Tenant Member role name.
- Updated the current decision/milestone and preserved earlier proposals above as
  planning history. Grants, target checks and implementation scope are unchanged.
- Checks passed: five documents, 174 local links, consistent permission names,
  whitespace, index totals/order, 34 open tasks and `git diff --check`.

## Follow-up — Console URLs and no-email passwords

- User requested concrete Console page URLs and clarified there is no email delivery.
  Added ten routes covering setup/login, Account, user listing/creation/details/reset,
  and role listing/creation/details. IDs are public UUIDs; logout remains a POST action.
- Reset form asks the acting authorized administrator for new password and confirmation,
  with target email shown read-only. Creation similarly uses a chosen password and
  confirmation. Removed the previously proposed temporary-password flag and mandatory
  first-change flow to keep this interaction direct.
- Added server confirmation validation, failure rollback, atomic target-session
  revocation, self-reset logout and preservation of the acting user's identity.
  No email verification, invitations, magic links or public forgot-password flow.
- Updated decision/milestone acceptance and design-review evidence. Existing tenant/
  call/spec/service routes are unchanged; this is planning only, with no implementation.
- Checks passed: five documents, 175 local links, ten matching browser URLs, removal
  of the temporary-password schema flag, whitespace, index totals/order, 34 open tasks
  and `git diff --check`. No runtime tests or rendered UI acceptance are claimed.

## Follow-up — tenant assignment interaction

- Used the Impeccable planning/Operate guidance and existing Console design, TenantList
  and CallSpecCombobox patterns. Proposed an inline Tenant access section after Role,
  with tenant search, selected rows, Read only / Read & write and Remove.
- Role grants remain the capability ceiling; membership controls never create a
  missing permission. Added effective-access summaries and explicit handling for
  all-tenant, mixed, assigned-but-empty and no-tenant roles. Changes save with the form.
- Asked about typical tenant count; absent a reply, the initial presentation assumes
  dozens, with bounded server search/pagination and no separate bulk-edit requirement.
- Recorded keyboard/phone, stale role/deleted tenant, failed-save and selection-persistence
  acceptance. This is a proposed interaction only; no rendered UI or code changed.
- Design-context inspection reported an existing orphaned call-inspection surface brief
  and an available skill update; neither was modified as part of tenant-access planning.
- Documentation checks passed: five files, 176 local links, whitespace, unchanged
  index order/totals, 35 open tasks and `git diff --check`.
