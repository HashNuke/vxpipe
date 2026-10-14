# Console authentication and user management

Status: engineering implementation and acceptance complete, 2026-10-13.
User UI review is deferred by request and is not a gate on the authorized implementation.
Requested 2026-10-13. The user explicitly requested component and composed-page
Storybooks for review before backend implementation.
Prerequisites: completed [Operator login and admin dashboard](operator-login-and-admin-dashboard.md),
[Tenant Call Specs and API-key administration](tenant-call-specs-and-api-keys.md),
[Call spec editor](call-spec-editor.md), and the accepted scoped-services follow-up in
[Platform and tenant services](platform-and-tenant-services.md).
The unfinished parent bootstrap/demo and Getting Started milestones are not blockers;
authentication setup must not require a demo tenant. The index places this before delivery.

Sources: [Authentication and authorization decision](../../docs/console-authentication-and-authorization.md),
[Gateway/Console boundary](../../docs/gateway-console-boundary.md),
[Operator API-key authoring](../../docs/operator-api-key-authoring.md),
[Demo binding](../../docs/demo-tenant-binding.md), and
[Tenant control plane](../../docs/tenant-control-plane.md).

## Runnable outcome and requested contracts

First load on a fresh installation asks for a Superadmin email and password.
Creation atomically records completed setup and logs that Superadmin in. Later visits
use email/password login. Superadmin and Admin are protected built-in roles; ordinary
roles are configurable permission bundles. Both built-ins can manage ordinary roles.

| Role | Platform services | Tenants | Can create/manage users |
| --- | --- | --- | --- |
| Superadmin | ReadWrite | ReadWrite all | Superadmins, Admins and ordinary users |
| Admin | ReadWrite | ReadWrite all | Ordinary users only |
| Tenant Manager template | None | ReadWrite calls, call specs, services, API keys and telephony applications in assigned tenants | None |
| Tenant Member template | None | Read calls and call specs in assigned tenants | None |

`calls.read/write`, `call_specs.read/write`, `tenant_services.read/write` and
`tenant_api_keys.read/write` apply to tenant resources, selecting all tenants or
assigned tenants per grant. `platform_services.read/write` and
`users.read`, `users.members.write`, `users.admins.write` and `users.superadmins.write` apply at
installation scope. Admin has `users.read` and ordinary-user-only `users.members.write`;
Superadmin has all four. Only built-ins can hold account-write permissions. Match
keys exactly, with no prefix inheritance. Resolve the required write from the target's
protected kind; role changes require both current-kind and requested-kind permissions. This applies to
creation, promotion, credential resets and other account mutations, not just signup.
Admins can view Admins and Superadmins through `users.read` but cannot change either,
including password resets, tenant assignments or session revocation. Only Superadmins
can administer those accounts. Self-service password changes remain separate.
The former delegation/allowed-target-role design is superseded and needs no table.

Approved defaults: only Superadmins create/manage other Superadmins; protect the last
enabled Superadmin; optional `users.read` on ordinary roles exposes only a safe read-only
account directory and is absent from the initial templates. Self-service password/email
changes are separate. One role per user remains sufficient; the linked decision defines
permission prerequisites, membership caps and the complete protected route inventory.

## Browser pages

| URL | Purpose |
| --- | --- |
| `/auth/setup` | First Superadmin email/password/confirmation. |
| `/auth/login` | Email/password sign-in. |
| `/auth/recover` | Existing Superadmin password replacement with a local one-time proof. |
| `/admin/account` | Own email and password change (current password required). |
| `/admin/users` | User list with search, role filters and pagination. |
| `/admin/users/new` | Create a permitted account, with password/confirmation and role/tenant assignments. |
| `/admin/users/:user_id` | User details and authorized editing; privileged accounts are read-only for Admins. |
| `/admin/users/:user_id/reset-password` | Authorized administrator enters and confirms a replacement password. |
| `/admin/roles` | Role list; built-ins are protected. |
| `/admin/roles/new` | Create an ordinary permission-based role. |
| `/admin/roles/:role_id` | View/edit an ordinary role; view built-ins read-only. |

The [decision's route contract](../../docs/console-authentication-and-authorization.md#console-pages-and-urls)
defines per-page access. IDs are public UUIDs. Logout uses `POST /auth/logout`.
Email is only the login identifier. No email verification, invitations, magic links,
forgot-password pages or mailed reset tokens. Creation/reset uses administrator-entered
password and confirmation; the chosen password works immediately. No temporary-password
or mandatory first-change flow. Existing Console workspace URLs retain their paths.

## Checkpoint P — Components, pages and interactive Storybook review

This checkpoint precedes A–D. It is UI work only: deterministic fixtures,
injected actions and local in-memory state. The user deferred UI review and
authorized backend implementation on 2026-10-13. Frontend permission behavior is
an interaction preview and never substitutes for server-side authorization.

- [x] Build reusable password/confirmation fields, role badges and selection, tenant
  assignment editor, and permission editor with isolated interactive stories.
- [x] Compose all eleven page URLs above from those components, including protected/read-only
  accounts, mixed/all/assigned tenant access, role filters, empty/loading/unavailable,
  confirmation/validation, save failure and pending states in both themes.
- [x] Connect a mock journey: setup/login, create/edit users and roles, tenant assignments,
  directory filters and no-email resets, preserving the acting identity. Use public
  hash URLs inside Storybook, with ordinary back/forward behavior and synthetic accounts.
- [x] Verify focused behavior through red-green tests, frontend/root checks and a bounded
  rendered desktop/phone pass using `agent-browser`. Record the concrete story links,
  test/build evidence and limitations in the implementation labnote/review guide.
- [ ] User reviews the Storybook UI/functionality (deferred; backend authorized to proceed).

Stories: `Vxpipe / Console / Authentication / Full journey`, `Components`, and `Pages`.
See the [review guide](../../docs/development/authentication-storybook.md).
Evidence: [UI implementation labnote](../20261013-0423-authentication-storybook-ui.md).
All five root gates, 610 frontend tests, TypeScript, lint and both builds pass.
The original UI checkpoint evidence above is historical. Final backend acceptance and
independent review evidence is recorded in the [backend labnote](../20261013-0454-console-auth-backend.md).
The engineering gates have passed; the deferred user UI review remains separate.

## Checkpoint A — First Superadmin, login and safe cutover

Exit: a fresh install reaches Superadmin setup and then the existing Console; an upgraded
install requires trusted local setup proof; both use named, revocable user sessions.
Only Superadmins are provisionable until B enforces Admin/ordinary-role boundaries.

- [x] Inventory protected HTTP, JSON, LiveView, diagnostics, sample-call and streaming
  entry points, plus the existing `InstallationOperator` workflows. Start with
  `apps/vxpipe_console/lib/vxpipe/console/router.ex`, `installation_operator_session.ex`,
  `apps/vxpipe_calls/lib/vxpipe/calls/call_spec_authoring.ex`, and
  `apps/vxpipe_persistence/lib/vxpipe/persistence/schema/installation_setup.ex`.
  Record an action/owner mapping before replacing guards.
- [x] Red-test initial setup, normalized-email uniqueness, atomic completion/session
  creation, competing setup submissions, rollback, retry after lost response, restart,
  fail-closed missing state, login, expiry and logout replay at owning boundaries.
- [x] Add `vxpipe_identity`, its ports and password-library dependency; Persistence
  migrations/adapters for users, both protected built-in roles, sessions, authentication
  singleton and access events.
  Preserve the separate demo-setup record and existing machine credentials.
- [x] Implement the first-Superadmin vertical flow, database-backed 12-hour sessions, safe
  cookies, CSRF, origin/TLS checks, redaction and bounded clustered login/setup throttling.
  Fix concrete limits and failure behavior in the contract and tests before exposure.
- [x] Add password policy/change and trusted local Superadmin recovery. For upgrades, test
  trusted setup-proof consumption in the same transaction; invalidate old sessions,
  old challenges and legacy full-authority login routes at cutover. Document how
  `mix vxpipe.login` changes instead of retaining an undocumented bypass.
- [x] Test the migration against empty and populated pre-auth databases, including
  tenant-only installs and existing operator-key/demo records. Verify an enabled
  Superadmin remains after recovery and setup cannot reopen by disabling users.
- [x] Render setup/login/errors/logout with headless Chrome through `agent-browser`
  at desktop and phone sizes; verify keyboard, autofill and password-manager support.
- [x] Run focused tests and all relevant root gates; update account setup/recovery
  documentation and record evidence before moving to lower-role provisioning.

## Checkpoint B — Enforced roles and tenant access

Exit: fixture/provisioning workflows can exercise both built-ins and ordinary templates/
custom permission bundles; every existing Console resource and action respects
server-side permissions, including direct requests.

- [x] Red-test the role × action × resource matrix and user-management target-role
  rules, including unknown actions, anonymous/disabled users and forged authority.
- [x] Add the permission catalog, protected system kinds, ordinary roles/grants,
  memberships, constraints and explicit user principals. Seed Tenant Manager and
  Tenant Member as the two ordinary templates. Validate action/scope combinations and permission prerequisites, reject
  unknown/reserved grants and keep new permissions absent from existing ordinary roles.
  Use the four installation-scoped user permission keys above and tenant-scoped
  `calls.read/write`, `call_specs.read/write`, `tenant_services.read/write` and
  `tenant_api_keys.read/write`.
  Wire Identity through Console and Calls without reverse dependencies.
- [x] Red-test custom-role permissions independent of names, both built-in definitions,
  Read/ReadWrite membership caps, tenant versus installation scope and all three reserved
  user-write keys. Prove no wildcard/prefix implication, and require both current and
  requested target-kind permissions for promotions/demotions, including bulk operations.
  Admins cannot create/promote/reset/disable Admins or Superadmins. Ordinary users cannot
  create/manage any user or edit roles, even with every delegable operational permission.
  Check direct API calls, forged grants/system kinds and target promotion during a stale edit.
- [x] Replace installation-wide browser assumptions throughout the entry-point inventory.
  Recheck writes in owning domain/persistence boundaries; filter tenant directories,
  pagination, counts, lookups, calls, specs, artifacts and streams by authorized scope.
- [x] Preserve service-authoring restrictions (the separate `call_specs.use_platform_services` grant was merged into `platform_services.read` by the [October 14 Console review](console-sidebar-and-dashboard.md#merge-shared-service-authoring-into-platform-services-read)):
  seed it for Managers; members write tenant-owned references only. Test custom roles,
  full-spec save/publish, inherited services, platform-backed read/run access and zero allocated revisions on denial.
- [x] Test member A=Read/B=ReadWrite/C=unassigned, empty memberships, unknown/foreign
  call/spec identifiers, future-tenant access for all-tenant custom roles, and concealment of foreign data.
- [x] Test service probes, sample creation, call start/control, publication, API-key
  issuance and diagnostics as distinct actions; members cannot acquire broader authority
  through a key, sample, service lookup or administrative endpoint.
- [x] Revoke sessions on password/status/user-role/membership and role-definition changes,
  and disconnect active inspection subscriptions. Test subsequent events/requests after
  removal, actor/target concurrent changes, explicit replacement memberships, definition changes clearing
  obsolete memberships, role-wide revocation and cross-node revocation.
- [x] Preserve independent platform/tenant API keys, admission tokens, webhooks and
  already admitted calls; run relevant Gateway and Calls regression suites.

## Checkpoint C — User management and role-aware Console

Exit: Superadmins and Admins can define ordinary roles and manage exactly the accounts
allowed by the built-in actor/target policy. Assigned-tenant users can read
or edit permitted resources with clear UI affordances.

- [x] Red-test authorized account creation/update/disable/reset, transactional membership
  replacement, last-enabled-Superadmin protection and concurrent attempts to remove both
  Superadmins. An Admin cannot mutate a privileged target through reset, email change,
  demotion or an ordinary-user edit submitted after the target was promoted. Verify
  Admins can read both privileged roles while every account-write path (including bulk
  actions and session revocation) rejects those targets. Cover self-service password
  change separately from Superadmin-only administrative reset of privileged accounts.
- [x] Add `/admin/users` with search, role filters, pagination, email, role, enabled/disabled status and
  tenant-access summary. Offer only role choices permitted for the acting built-in; show
  tenant assignments for roles with assigned-scope grants and distinguish any all-tenant grants explicitly.
- [x] Add the Tenant access section to user creation/details: a searchable Add
  tenants dialog, with selected tenant rows, Read only / Read & write and Remove
  kept visible on the form. Do not expand a scrollable picker inside the page. Default
  new assignments to Read only, cap choices by role permissions, show effective access
  and distinguish all-tenant/mixed/no-tenant roles. Keep changes pending until form save.
  Test selections across search pages, duplicate/deleted tenants, role changes, empty
  assignments, read-only viewers, failed saves and atomic assignment replacement. See
  the [interaction proposal](../../docs/console-authentication-and-authorization.md#tenant-access-on-the-user-form).
- [x] Red-test role filtering before pagination/counts, combined search, valid empty
  results and invalid filters. Include All roles, Superadmin, Admin and custom-role
  options using public role IDs. Provide minimal option metadata to `users.read`
  viewers, retain filters in the URL and reset pagination on changes. Admins can view
  privileged rows through every filter but have no mutation controls or API authority.
- [x] Add `/admin/roles` for Superadmins/Admins: list/create/edit ordinary roles,
  permission selection and valid resource scopes. Display both built-ins as protected
  and exclude all three reserved user-write permissions from ordinary role definitions.
  Show affected-user counts and effective-access changes before saving; changes are
  transactional, audited, revision-checked and invalidate affected sessions. Reject
  deletion of assigned/referenced roles and stale conflicting edits. Test these actions
  through direct requests as well as the UI.
- [x] Add create/edit/disable/enable/reset actions and safe audit records, using the page
  URLs above. Creation/reset asks the acting administrator for password and confirmation;
  do not send emails, generate temporary passwords or require a first-login change.
  Red-test confirmation mismatch and invalid password as no-ops; successful reset
  replaces the hash and revokes target sessions atomically. Preserve the actor's
  session unless resetting their own account; never switch identities or echo passwords.
- [x] Add `/admin/account` self-service with current-password confirmation for own
  email/password changes; no profile update may alter the user's own role.
  Gate directory reads by `users.read`, and account writes by the exact permission for
  each current/requested target kind. Test a read-only directory role cannot mutate any account. Built-ins
  get the appropriate target actions; ordinary templates get no directory grant by default.
- [x] Drive navigation/action visibility from server-derived capabilities. Render Calls
  and Call Specs read-only for Read members, including the editor. Show service-reference
  restrictions and permission-loss errors without discarding unsaved content into
  another tenant or retrying a forbidden write.
- [x] Reuse existing Console components and Storybook patterns; cover empty assignments,
  disabled account, duplicate email, invalid input, last-Superadmin conflict, loading,
  unavailable storage, role-definition changes and stale-session states.
- [x] Inspect both built-ins, all ordinary templates, a custom role, first-run, role-management and
  user-management journeys with `agent-browser`
  headless Chrome at desktop/phone sizes, including direct URLs, keyboard operation,
  sign-out/back navigation and session revocation in a second open browser context.
  Check role filters, refresh/back restoration and read-only privileged rows as an Admin.
  Exercise the direct creation/reset URLs, mismatched confirmations and successful reset
  without email. Verify the target can log in using the chosen password immediately.
  Inspect tenant selection and effective-access summaries with keyboard and phone layouts,
  including an all-tenant role and a role combining all-tenant and assigned grants.

## Checkpoint D — Acceptance and operational documentation

- [x] On a disposable fresh database, set the first Superadmin, observe automatic login,
  restart and verify normal login plus rejected setup replay. No demo tenant is needed.
- [x] On a populated pre-auth database, prove anonymous claiming is blocked, trusted
  setup preserves tenants/specs/credentials/keys, and old browser grants cannot authenticate.
- [x] Create both built-ins and the two ordinary templates; exercise positive and negative matrix cases through actual
  HTTP requests and rendered UI, including membership revocation while a stream is open.
- [x] Create a Calls-only custom role, rename it without changing authority, revise its
  permissions and verify immediate session revocation. Prove a ReadWrite assignment
  cannot supply an absent action, ordinary roles cannot obtain protected account authority,
  and a new catalog action is denied to existing ordinary roles until explicitly granted.
- [x] Verify database constraints, session expiry/revocation, audit redaction, last-Superadmin
  races and recovery with no plaintext secrets or token digests in public responses.
- [x] Update setup, login/recovery, deployment and role documentation. Describe the
  trusted-first-visitor boundary on fresh installs and independently issued API keys.
- [x] From owning children, run focused tests following red-green-refactor. From the
  umbrella root pass `mix format --check-formatted`, `mix compile --warnings-as-errors`,
  `mix credo --strict`, `mix test`, and `mix deps.unlock --check-unused`. Run frontend
  tests, typecheck, lint and production assets for affected UI; Lean only if scope
  expands into source-cutover or speech state machines. No live providers are needed.
- [x] Keep implementation, focused tests, lockfiles, docs and checkpoint labnotes together;
  synchronize this checklist and the index only after acceptance. Commit only when asked.

## Design review — separate from implementation

Local specification review, 2026-10-13: checked role/target restrictions, tenancy,
existing service-authoring policy, dependency direction and prerequisite order. Found
and addressed the demo-bound singleton mismatch, unrevocable legacy browser grants,
upgrade takeover risk, accidental creator impersonation, platform-key separation,
stream revocation and concurrent removal of the last privileged account. The existing implementation
supports all prerequisites; the new milestone does not depend on unfinished demo
onboarding or introduce mail delivery as a prerequisite.

Latest follow-up design review, 2026-10-13: protected Superadmin and Admin replace the
single built-in and ordinary-role delegation proposal. Calls/spec permissions are tenant-
scoped; platform service/user permissions are installation-scoped. Checked the creation
hierarchy against credential reset/demotion bypasses, reserved permission injection,
ordinary-role impersonation, first-Superadmin setup and last-Superadmin recovery. The
previous target-role relation/containment design is removed, including its UI/schema.
Role editing stays in C after B enforces both built-in boundaries; prerequisites and
implementation status do not change.

Subsequent clarification confirms that Admins may only view privileged accounts through
`users.read`; password resets and all other account mutations require Superadmin.
Added role filters to the directory, keeping read visibility independent of mutation
authority. Reviewed stable identifiers, server-side filtering/pagination and minimal
role metadata for read-only viewers; all acceptance remains pending implementation.

Latest permission-name clarification uses `users.members.write` for ordinary accounts,
`users.admins.write` for Admins and `users.superadmins.write` for Superadmins, with
`users.read` covering directory reads. The two built-in grant sets encode the existing
matrix; reserved keys cannot be assigned to custom roles. Reviewed no prefix inheritance
and both-kind checks on role changes; filters, self-service and recovery remain as specified.
`members` covers every ordinary/custom-role account, including the Manager templates;
it does not mean only the Tenant Member template or imply a tenant-scoped permission.
The category naming is consistent across all three writes, with no generic write alias.

No-email clarification: added the explicit ten-page URL inventory, administrator-entered
password/confirmation forms for creation/reset and current-password self-service.
Removed the earlier temporary-password flag and forced-change screen. Reviewed actor
versus target identity, reset failure rollback, atomic session revocation and direct
route authorization. Runtime and rendered evidence remain implementation gates.

Tenant-assignment proposal: an inline section after Role uses existing Console picker/
list patterns, with per-tenant access caps and a computed summary. Reviewed all-tenant
versus assigned scope, mixed grants, empty access, draft saves and permission loss.
Tenant count remains a sizing assumption; the proposal includes bounded lookup and
does not require bulk editing. No new route or database model is introduced.

UI checkpoint review, 2026-10-13: inserted P before backend A–D at the user's request.
Reviewed component composition, all ten routes, draft versus saved assignments, actor
preservation and protected-account controls. The connected mock has no storage or
transport dependency. Browser review covered desktop/phone and dark/light themes;
it found and corrected route scroll restoration and a clipped scope label. The
implementation labnote records tests, builds and limitations. The user subsequently deferred UI approval and explicitly authorized completion of A–D.

Proposed policy defaults are identified above and in the decision document. This is
the historical local design review. Independent backend/frontend reviews and acceptance
evidence are recorded below; they are separate from the user’s deferred UI review. Custom role definitions are in scope.
Deferred: multiple roles per user, role inheritance, direct per-user permission overrides,
independent per-resource membership levels, per-call-spec ACLs, SSO/MFA, public signup, email invitations/recovery and
user-bound API keys. No delivery/retention hold is released by this specification.

## Implementation review and acceptance evidence — 2026-10-13

Three independent review agents inspected Identity/Persistence, Calls/route authorization
and frontend behavior. Their findings led to fixes for exact target-category grants,
stale actor/target checks, role prerequisites, atomic revocation/audit, scoped lookups,
tenant-directory policy, custom mixed scopes, active diagnostics revocation and mount-log
redaction. Follow-up reviews reported no remaining concrete blocker in those changes.

Tenant Manager was confirmed to cover all operations in assigned tenants: calls, call
specs, tenant services, API keys and telephony applications. Tenant Member remains
call/spec read only. The Add tenants dialog and shared page width follow the user's UI
corrections; review is still theirs to perform later.

Automated acceptance spans the Identity policy suite, database-backed Persistence
workflows, actual Console endpoint tests, Calls authorization matrices and the frontend
suite. The disposable migration lane explicitly covers empty, tenant-only and populated
pre-auth databases, trusted proof, preservation and fresh-VM login/setup replay. Chrome
checks use both Storybook and a real Console backed by a disposable database, including
first setup, user creation, tenant assignment, password reset, replacement-password login
and session invalidation in another browser context.

See [backend labnotes](../20261013-0454-console-auth-backend.md),
[operational instructions](../../docs/development/console-authentication-operations.md),
and the [route inventory](../../docs/console-authentication-route-inventory.md).
Final evidence: the umbrella run exercised 3,749 tests across ten applications
(132 intentionally excluded integration/live cases). Its sole failure was an existing
transfer-test synchronization race, corrected without production speech changes; the
focused six-test file and final root `mix test --failed` both pass. All other umbrella
cases passed, including 58 Identity, 177 Calls, 270 Persistence and 285 Console tests.
The disposable migration/cross-BEAM lane adds four passing integration cases.
Frontend: 664 tests across 83 files, TypeScript and ESLint pass. Standard production
assets and Storybook build pass. Root formatting, warnings-as-errors compilation,
strict Credo, unused-dependency and diff checks pass. No live providers or Lean
source-state-machine verification was required. The initial Storybook checkpoint is committed separately. The user subsequently
requested a commit of the completed implementation and its verification evidence.
