# Console authentication and authorization

Status: implemented contract, 2026-10-13; acceptance is tracked in the
[authentication milestone](../labnotes/milestones/console-authentication-and-user-management.md).
This supersedes the historical Console-only installation-operator browser grant. Existing API-key contracts remain independent.

## Roles and resource permissions

Use protected built-in **Superadmin** and **Admin** roles, plus configurable ordinary
roles. Both built-ins have full platform and tenant operational access. Superadmin
alone can manage privileged accounts; Admin can manage ordinary accounts. The first
account created during setup is a Superadmin, so the installation has an authority
able to create Admins immediately.

| Role | Platform services | Tenant resources | Can create/manage accounts |
| --- | --- | --- | --- |
| Superadmin (built-in) | ReadWrite | ReadWrite, all tenants | Superadmins, Admins and ordinary users |
| Admin (built-in) | ReadWrite | ReadWrite, all tenants | Ordinary users only |
| Tenant Manager (editable template) | None | ReadWrite calls, call specs, tenant services, API keys and telephony applications in assigned tenants | None |
| Tenant Member (editable template) | None | Read calls and call specs in assigned tenants | None |

The two initial ordinary templates keep authority inside assigned tenants. Tenant
creation and platform service configuration remain built-in operations. Ordinary
roles cannot create or manage users. One role per user remains sufficient initially; multiple-role
unions and direct per-user permission overrides are deferred. Template names do not
control authorization; registered grants and resource scopes do.

### Permission catalog and scopes

Use the requested `resource.read` / `resource.write` naming, including the symmetric
read/write operations for calls and call specs:

| Permission | Resource scope | Meaning |
| --- | --- | --- |
| `calls.read` | Tenant | Inspect calls and permitted history, transcripts and recordings. |
| `calls.write` | Tenant | Start/control calls through existing operations. |
| `call_specs.read` | Tenant | List/read source and revisions. |
| `call_specs.write` | Tenant | Create/edit/publish call specs. |
| `platform_services.read` | Installation | Inspect platform service metadata, never secret values. |
| `platform_services.write` | Installation | Configure/test platform services. |
| `users.read` | Installation | Read the safe account directory/profile projection. |
| `users.members.write` | Installation, built-ins only | Create/manage ordinary user accounts only. |
| `users.admins.write` | Installation, Superadmin only | Create/manage Admin accounts. |
| `users.superadmins.write` | Installation, Superadmin only | Create/manage Superadmin accounts, retaining one enabled Superadmin. |

`members` means every account assigned an ordinary/custom role, including Tenant
Manager and Tenant Member. It is an account category, not a tenant
membership check or a match against the Tenant Member role name. There is no generic
user-write alias; use the three explicit category permissions above.

Calls and call specs always belong to a tenant. `all_tenants` and `assigned_tenants`
are selectors within that tenant scope, not global ownership of a call/spec. Every
request must still resolve and check the resource's actual tenant. A role can grant
`calls.read` for all tenants and `call_specs.write` for assigned tenants independently.
Platform services and users are installation resources, so tenant membership does not
confer access to them.

A role grant pairs a registered permission with `installation`, `all_tenants` or
`assigned_tenants`, limited to scopes valid for that action. Tenant assignments cap
assigned-scope grants: Read permits read actions; ReadWrite permits both. They never
add capabilities missing from the role. For example, `calls.read` plus a ReadWrite
assignment to tenant A still cannot write calls or read specs. The original member
preset grants both resource families; custom roles can separate them. Zero assignments
means no assigned-scope access; all-tenant grants cover future tenants without rows.

Each catalog entry declares its resource kind, valid scopes, prerequisites, whether
it mutates state, and whether it is restricted to built-ins. Ordinary role editing
rejects unknown keys and reserved grants, including all three user-write permissions.
A stored string cannot create a capability. Disallow overlapping scopes for the same role/action.
Write grants require the corresponding read grant covering the same tenants; the
editor includes it explicitly and the backend validates it. New permissions default
to absent from ordinary roles. All three account-write permissions require `users.read`;
there are no separate `users.admins.read` or `users.superadmins.read` prerequisites.
Built-ins cover new registered operational actions, while privileged account rules
remain explicit. Unknown actions deny for everyone.

The route inventory also needs `tenant_services.read/write` and `tenant_api_keys.write`
with tenant scopes (`all_tenants` or `assigned_tenants`), plus installation-scoped
`tenants.read/write`, `diagnostics.read` and the existing platform-service authoring
modifier described below; the ten rows above are not an implicit grant to other
surfaces. Map resource actions explicitly. Tenant Manager includes assigned-tenant
service/key and telephony application management; Tenant Member does not. Diagnostics remain
built-in-only initially. Granting `users.read` to a custom role is an optional
read-only directory capability, not permission to create/edit users. Seed no ordinary
role with it by default; the projection excludes credentials, hashes and session data.
Self-service profile/password changes use their own authenticated workflow and do not
require directory or account-administration permissions.

### Built-in account-management rules

| Actor | Ordinary target | Admin target | Superadmin target |
| --- | --- | --- | --- |
| Superadmin | Create/manage | Create/manage | Create/manage, retain at least one enabled Superadmin |
| Admin | Create/manage | View only through `users.read` | View only through `users.read` |
| Ordinary role | Deny | Deny | Deny |

Encode this matrix with exact permission keys:

| Built-in | Account permissions |
| --- | --- |
| Admin | `users.read`, `users.members.write` |
| Superadmin | `users.read`, `users.members.write`, `users.admins.write`, `users.superadmins.write` |

These keys are independent; dots express namespacing, not inheritance. `users.members.write`
never matches `users.admins.write` or `users.superadmins.write`, and neither privileged
write implies the other or ordinary-user writes. Do not use prefix/wildcard matching.
Keep all three writes unavailable to ordinary roles, preserving the user's rule that
only the two built-ins can create/manage accounts. Ordinary `users.read` remains a
separate read-only capability. New privileged account permissions need explicit
built-in grants rather than an operational wildcard.

Choose the required write permission from the target's protected system kind, never
its display label. Creation checks the requested kind; a normal update/reset checks
the current kind; a role change requires permissions for both current and requested
kinds. Thus ordinary-to-Admin promotion requires `users.members.write` and `users.admins.write`,
while Admin-to-Superadmin requires both privileged write keys. Resolve actor grants
and target kind inside the transaction, including each target of a bulk operation.
No ordinary role can acquire these writes through edits, API requests or forged
permission records. These checks apply to promotion, role reassignment, credential
reset, email change, enable/disable and
all other account-administration writes; otherwise an Admin could take over a peer
without creating one. Check both current and requested target roles inside the
transaction. An Admin cannot promote an ordinary user to Admin/Superadmin, or demote
an Admin and then edit them. Changing one's own password/email is a separate workflow
requiring the current password; self-service never changes role.

Only Superadmins can perform an administrative password reset for an Admin or
Superadmin. An Admin's `users.read` still permits listing and viewing those accounts,
but all administrative mutations are denied: profile/email/password changes, role
or tenant-assignment changes, enable/disable, removal and session revocation. This
includes bulk endpoints and the actor's own row in the administration screen. An
Admin can change their own password through authenticated self-service, using their
current password; that is not an administrative reset. Hide mutation controls on
privileged rows for Admin viewers, and enforce the same denial on direct API calls.

Superadmins and Admins can create/edit ordinary role definitions. Both built-in role
identities and policies are immutable through these endpoints. Ordinary roles cannot
contain any user-write permission, role-definition management or built-in-equivalent wildcard
grants. Labels cannot impersonate system identity: protected kinds are seeded and
cannot be set by custom-role requests. An ordinary role with every delegable operational
permission remains ordinary and cannot manage accounts or roles.

Account lifecycle: Superadmins may create other Superadmins; protect the last enabled
Superadmin under concurrent demotion/disable; accounts are disabled rather than
hard-deleted. A separate last-Admin invariant is unnecessary because Superadmin can
create an Admin. These defaults and applying the creation hierarchy to all account
writes make recovery and the no-peer-management rule coherent.

This replaces the previous allowed-target-role/delegation design. No delegation table,
grant-containment calculation or numeric role hierarchy is needed for user management.

### User directory and role filters

`/admin/users` supports search, role filtering and stable pagination. Default to
**All roles**, with options for Superadmin, Admin and every ordinary role. Use stable
public role IDs for filter values, with current display names as labels. Users with
`users.read` can obtain the minimal role ID/name options without permission to edit
role definitions. Admins can filter for and view Admins/Superadmins; filtering must
not reduce the directory to accounts they may modify.

Apply the role filter and search on the server before pagination and counts; combine
them rather than silently dropping either condition. Keep the selected filter in the
URL so refresh/back navigation restores it, and reset pagination when filters change.
Unknown or malformed role filters return a validation error instead of falling back
to all users. Show a truthful empty result for a valid role with no matching accounts.
Permission checks still apply to every read and mutation regardless of the filter.

### Console pages and URLs

These are the browser routes for this milestone; user/role IDs are public UUIDs.
Existing tenant, call, call-spec and service pages retain their URLs and gain the
permission checks described above.

| URL | Page and fields | Access |
| --- | --- | --- |
| `/auth/setup` | First Superadmin: email, password, confirm password. | Pending installation only; upgrades additionally need trusted setup proof. |
| `/auth/login` | Sign in: email and password. | Unauthenticated visitors; redirects to setup only when safely pending. |
| `/auth/recover` | Enter a locally issued one-time recovery proof, existing Superadmin email, new password and confirmation. | Anyone holding the short-lived proof; no email delivery. |
| `/admin/account` | Own account: email; change password with current password, new password and confirmation. | Any signed-in user; current-password confirmation for account changes. |
| `/admin/users` | User directory: search, role filters and pagination. | `users.read`. |
| `/admin/users/new` | Create account: email, password, confirm password, permitted role and applicable tenant assignments. | Write permission for the selected account category. |
| `/admin/users/:user_id` | Account details; edit email, role, status and tenant assignments where permitted. Passwords are never populated or returned. | `users.read`; editing additionally checks current/requested category writes. Admins see privileged accounts read-only. |
| `/admin/users/:user_id/reset-password` | Set a replacement password: new password and confirm password; show target email as read-only context. | Write permission for the target category. Only Superadmins can reset Admin/Superadmin accounts. |
| `/admin/roles` | Role directory, including protected built-ins. | Superadmins and Admins. Directory-filter metadata remains separately available to `users.read`. |
| `/admin/roles/new` | Create an ordinary role: name, permissions and scopes. | Superadmins and Admins. |
| `/admin/roles/:role_id` | Role details/edit; built-ins are read-only. | Superadmins and Admins. |

Logout is a CSRF-protected `POST /auth/logout` action, not a separate page. Direct
loads/refreshes of the React `/admin` routes restore the page through the Console
mount, with authorization before any private data is returned. Disabled accounts or
users with no tenant assignments still have an appropriate login denial or empty
tenant state; there is no permission-free fallback to another tenant.

### Tenant access on the user form

Present one **Tenant access** section immediately after Role on
`/admin/users/new` and `/admin/users/:user_id`. Keep assigned tenants as compact rows
on the form. **Add tenants** opens a searchable modal dialog so a scrollable tenant
picker does not expand the page; no separate page or nested permission wizard is needed.

- For assigned-tenant grants, show **Add tenants** opening a dialog with search by
  tenant name/key and checkbox selection. Selected tenants appear on the form as rows with tenant name, public
  key, **Read only / Read & write** selector and **Remove**. New selections default to
  Read only. Preserve selections across search/result pages; exclude duplicate rows.
- Explain **The role defines available actions. Tenant access limits where those actions
  apply.** Summarize actual Calls/Call Specs access per selected tenant from the role
  and assignment together, including tenant services and API keys. Hide the Read & write choice when no assigned-scope write
  is available; a read-only role must never appear to acquire a write from this control.
- For all-tenant-only roles, replace the picker with **All tenants — granted by role**
  and **Includes tenants created later**. No user-level toggle expands an assigned-
  tenant role to all tenants, and selecting every current tenant is not future access.
- For mixed grants, show all-tenant permissions separately (for example, Calls: Read,
  all tenants), then assignments for the remaining permissions (for example, Call Specs:
  Read & write, selected tenants). Removing an assignment does not remove an all-tenant
  grant; the effective-access summary must make that visible.
- If the role has no tenant permissions, show **This role has no tenant access**. If it
  has assigned grants but no assignments, show **No tenants assigned** with the Add
  tenants action; saving that state grants no assigned-tenant access. Users may still
  have independent installation permissions or all-tenant grants.
- Changes remain a draft until **Create user** or **Save changes**. Remove is reversible
  before save; save updates the assignment set atomically and revokes affected sessions.
  A role change displays the changed scope and requires explicit assignment review;
  never carry hidden memberships into a new role or silently turn selected into all.
- In view-only accounts, render the same access summary without add/remove/edit controls.
  On phones, stack each tenant's identity and access control. The picker, checkbox rows,
  selector and removal action need labels and keyboard support; preserve draft selection
  on lookup/save failure. A missing/deleted tenant or changed role fails save visibly
  rather than silently granting partial or broader access.

Use bounded server search/pagination so the picker works with large directories; assume
dozens of tenants for the initial presentation until scale is clarified. Separate bulk
permission editing is not required for the first slice. This is a proposed interaction,
not a rendered or user-approved UI implementation.

### Password creation and reset without email

Email is a login identifier, not a delivery channel or a verified identity claim.
The product has no SMTP dependency, invitation email, email confirmation, magic link,
forgot-password form or emailed reset-token route. Login can advise a locked-out user
to contact an administrator; local recovery remains available for a lost last-Superadmin
password.

The acting Superadmin (or Admin for a member target) types the new password and its
confirmation on the reset page. The account owner's current password is not needed
for this administrative reset. Validate both fields on the server; mismatch/invalid
input changes neither the hash nor sessions. Successful reset atomically replaces
the hash and revokes the target's sessions, then returns to account details with a
success message. The acting administrator stays signed in as themselves, except that
resetting their own account also revokes their own session and returns them to login.
Nothing is emailed, generated as a temporary password or echoed in the response.

Account creation uses the same administrator-entered password/confirmation convention.
The password works immediately; no mandatory first-login password-change screen is
part of this milestone. The administrator communicates credentials separately from
the application, and the user can subsequently change their password under Account.
Only first-installation Superadmin creation automatically logs in the created account.
All existing category checks apply to reset and creation; no public password reset.

### Service references in call specs

Keep the existing distinction between executing a published spec and authoring it.
Both built-ins and Tenant Manager may author specs using platform or tenant services:
Tenant Managers can select/read a platform service without modifying its configuration.
Seed `call_specs.use_platform_services` for Tenant Manager, independently of
platform configuration writes. Custom roles must hold it as well as scoped
`call_specs.write` to author platform-backed specs. Tenant Members are read-only;
custom authoring roles without that modifier can author only tenant-owned service
references. Validate the entire resulting spec on save and publish, including
unchanged references. A member can read and run an already published
platform-backed spec. Changing this historical restriction requires an explicit
product decision; membership must not accidentally bypass it.

## Database organization

All schemas, migrations and SQL adapters belong to `vxpipe_persistence`. Names below
are the proposed contract; use existing internal/public identifier conventions.

| Table | Fields and constraints |
| --- | --- |
| `users` | Internal primary key, unique public UUID, display email, unique normalized email, password hash, non-null role FK, `disabled_at`, timestamps. No plaintext password column. |
| `roles` | Internal ID, public UUID, unique stable slug, editable name, revision, timestamps. Protected system kind (`superadmin` or `admin`) for the two seeded built-ins, immutable through role editing; ordinary roles have no system kind. Ordinary names/grants remain editable. |
| `permissions` | Application-seeded permission key and catalog metadata (resource kind, valid scopes, read/mutating classification, prerequisites and allowed built-in kinds for reserved grants). No UI-created permission keys. |
| `role_permissions` | Role FK, permission FK, checked scope; unique `(role_id, permission_id)`. Scope validity and dependencies validated by the owning policy workflow. Built-ins use protected policies, not editable grants; reserved permissions cannot be inserted for ordinary roles. |
| `user_tenant_memberships` | User FK, tenant FK, checked `access_level` (`read` or `read_write`), timestamps; unique `(user_id, tenant_id)` and tenant lookup index. |
| `user_sessions` | User FK, unique token digest, issue/absolute-expiry/revocation times; indexes for token lookup and user-wide revocation. Never store the bearer token itself. |
| `authentication_installations` | Singleton checked key `default`, `bootstrap_mode` (`first_run` or `operator_required`), nullable `setup_completed_at` and `initial_superadmin_user_id` FK, timestamps. Completion time and initial-Superadmin reference are set together and never cleared through normal workflows. |
| `user_access_events` | Actor and target user/role IDs, action, safe grant/membership/account change summary, timestamp; append through authorized mutations, without password/hash/token or provider payloads. |

Normalize email consistently for login and writes (trim surrounding whitespace and
case-fold the supported email form), enforcing uniqueness in PostgreSQL rather than
only an Ecto validation. Passwords retain exact input bytes. Restrict role/access values
at both the domain and database boundaries through FKs and checks; never create atoms
from request values. Prevent deletion of roles assigned to users until a built-in
administrator explicitly reassigns those users. Built-in roles cannot be deleted.

Memberships apply to any role with assigned-tenant grants. Changing a user's role
requires an explicit replacement assignment set (empty for all-tenant-only roles),
never resurrection of historical access. Role edits removing all assigned-scope grants
clear affected memberships; later reintroducing them requires new assignments. Zero
assignments is valid and grants no assigned-scope access. Other explicit all-tenant
grants still apply. Use internal foreign keys; public APIs accept public identifiers. Deleting a
tenant, where supported, removes its memberships. Users are disabled rather than
hard-deleted, including the initial Superadmin referenced by the setup record.

Do not add a generic config key-value table for this. The existing
`installation_setups.default` row requires `demo_tenant_id` and represents demo identity,
not authentication state. A dedicated typed singleton keeps security invariants
independent of demo creation. Do not infer completion from the current user count,
a browser flag, or the existence of a demo tenant.

## First Superadmin and upgrade behavior

On a fresh installation, the app's first browser entry leads to `/auth/setup`, asking
for email, password and confirmation. Private application routes are unavailable
until setup completes. Static assets, health and separately authenticated machine or
carrier endpoints keep their own protocols.

1. The migration creates the singleton in the pending state. For a database already
   containing tenant, demo-setup, operator-key or operator-challenge records, persist
   `operator_required` instead of exposing anonymous first-admin claiming. Classify
   this once during migration; missing/corrupt state later fails closed.
2. Hash and validate the submitted password using the selected library. Inside a
   transaction, lock the singleton, require pending setup, create the Superadmin, set the
   completion marker/reference and create its session. No partially completed setup
   becomes visible. Failure rolls everything back.
3. Only after commit, rotate the browser session and set its new session cookie.
   Redirect to `/admin`, then offer existing onboarding as appropriate. A lost HTTP
   response after commit is recovered by ordinary login, never by repeating signup.
4. Simultaneous setup submissions produce exactly one initial Superadmin/session; a loser
   receives a setup-completed response and a login link. Do not log it into the winner.
5. Restart, account disable or demo deletion never reopen setup. A missing completion
   reference or no enabled Superadmin is an operational recovery case, not public registration.

First-run claiming intentionally trusts whoever reaches an unclaimed fresh install;
deployment instructions must complete setup before exposing it to untrusted visitors.
Setup uses CSRF protection, the configured allowed origin and HTTPS outside loopback.
For upgrades, reuse the trusted local challenge mechanism only as a short-lived,
single-use **setup proof**, consumed with the creation transaction; it cannot issue
the old installation-wide session. Existing anonymous browser grants are invalidated
at cutover. Run `mix vxpipe.recover` locally to issue a short-lived, single-use proof,
then enter it on `/auth/recover` with an existing Superadmin email and replacement
password. Recovery changes that account's password and revokes its prior sessions in
the same audited transaction; it does not reset the setup marker or create a new user.
The recovery endpoint accepts only a valid locally issued proof.

## Login, provisioning and session lifetime

- Normal login uses email/password. There is no public signup after setup. The initial
  Superadmin is automatically logged in; creating another user leaves the managing user's
  session unchanged. The new user signs in separately.
- Superadmins and Admins type a password and confirmation when creating or resetting
  permitted accounts. Passwords work immediately, with no generated temporary password,
  mandatory first-login change or email delivery. Email is not claimed to be verified.
- Use a maintained Argon2id password library, owned by the identity application, with
  measured deployment cost and parameters at least as strong as current guidance.
  Do not implement password cryptography. Follow
  [OWASP password storage guidance](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html).
- Proposed password policy: 15–128 characters, bounded UTF-8 byte length, spaces and
  password-manager paste allowed, no trimming, silent truncation or composition rules.
  Reject common compromised passwords using a locally available check; no external
  password-checking request. Never print credentials in tests, telemetry or errors.
- Use database-backed opaque random sessions with 12-hour absolute expiry and no
  remember-me option initially. Retain HttpOnly, SameSite=Lax, HTTPS Secure cookies,
  Phoenix CSRF protection, private/no-store pages and session rotation on login.
- Logout revokes the current session. Password resets/changes, disablement, user-role changes,
  role-definition edits and membership changes revoke all affected users' sessions.
  Commit definition revision and revocation atomically. Resolve current account
  status and permissions on each protected request. Disconnect active inspection/
  LiveView subscriptions on revocation; recheck before commands and further data delivery.
  Already admitted calls continue under their pinned authority; loss of browser access
  does not silently terminate participants or carrier sessions.
- Use generic login failure responses and bounded rate limiting by normalized account
  and trusted client address. Define/test cluster-wide attempt accounting, expiry and
  unavailable-store behavior before enabling password login; no permanent attacker-
  triggered account lockout. Database failures are unavailable, never authenticated.
- Self-service account changes require the current password. Built-in administrators
  may reset only permitted target accounts by entering and confirming a replacement
  password. Trusted local recovery handles the last Superadmin losing credentials.
  Email delivery, verified-email recovery, invitations, MFA and SSO are outside scope.

[Phoenix authentication tooling](https://phoenix.hexdocs.pm/Mix.Tasks.Phx.Gen.Auth.html)
is a reference for session/CSRF integration and supported password libraries. Do not
run its generator blindly into this umbrella: its current email-based registration
flow and generated ownership need adapting to first-Superadmin password setup and the
existing React Console.

## Application and authorization boundaries

Introduce a focused `vxpipe_identity` umbrella application (`Vxpipe.Identity`). It owns
accounts, password/session workflows, permission/role policy, typed user principals and
repository ports, without Ecto, Phoenix or call-engine dependencies. Keep Accounts,
Sessions, Bootstrap and Authorization as cohesive modules rather than one catch-all.

- Persistence depends on Identity and implements its ports. Identity never depends
  on Persistence; runtime composition supplies adapters.
- Console depends on Identity for browser authentication and user management; Calls
  depends on Identity's database-neutral authorization contract for user-authorized
  tenant workflows. Identity never depends on Calls. Gateway and engine retain their
  existing reusable dependency direction and machine/participant authentication.
- Model user authority explicitly, carrying user/session identity and current access.
  Never turn every signed-in user into `InstallationOperator`, fabricate a tenant API
  principal, or accept client-supplied role/permission claims as authority.
- Evaluate registered action grants with explicit resource scope and membership caps.
  Account writes resolve the exact required permission from current/requested target
  kinds; immutable built-in grants encode the actor/target matrix. Unknown
  actions deny even for built-ins; ordinary role names never substitute for a grant.
- Audit every Console browser/JSON/LiveView/debug/sample route and its Calls workflow.
  Authorize server-side before querying, returning data or doing side effects; filter
  tenant lists in SQL before pagination/counts. Scope child-resource queries to the
  authorized tenant and conceal inaccessible/foreign resources with consistent 404s.
  Authenticated disallowed actions on visible resources return 403; unauthenticated
  JSON returns 401. HTML redirects to login, or setup only when safely pending.
- Serialize security-sensitive account mutations and the last-Superadmin check on the
  singleton plus target rows in a consistent lock order. Recheck actor/target authority
  inside the transaction to avoid concurrent promotion or revocation bypasses. Role
  definition and assignment edits use the same serialization boundary.
- Recheck tenant-write authorization and service ownership within final persistence
  guards. Read requests admitted before revocation may finish; later requests and
  subsequent stream deliveries must not rely on cached grants.
- API keys are independent machine credentials. Browser logout/demotion does not
  revoke keys already issued legitimately. Tenant Members cannot issue them. Existing
  platform API keys do not become a user-management or user-session credential.

This follows [OWASP authorization guidance](https://cheatsheetseries.owasp.org/cheatsheets/Authorization_Cheat_Sheet.html)
on explicit denial and checking each request; the concrete role matrix is project policy.

## Alternatives and implications

- A generic settings table weakens typing and atomic setup invariants; a typed singleton
  is smaller and independent of the demo tenant's lifecycle.
- Global roles alone cannot express one member reading tenant A and writing tenant B;
  separate memberships can. Per-tenant copies of users would duplicate login identities.
- Fixed ordinary-role cases were the initial simplification, superseded by the user's
  permission-based-role clarification. Data-defined roles allow new combinations of
  existing actions without code changes; genuinely new operations still need code and
  a catalog migration. Role inheritance, multi-role unions and user-specific permission
  overrides remain deferred to keep effective permissions explainable.
- Cookie-only role claims cannot promptly revoke access. Persisted sessions add database
  dependence to Console requests, keeping that work outside the live media path.
- Keeping the local challenge as a permanent full-access browser login would bypass
  named-user policy. Limit it to one-time upgrade setup and explicit local recovery.
- Adding account lifecycle to Calls would mix human identity with call workflows.
  A small Identity application adds an enforced dependency boundary without moving
  existing machine credentials out of Calls in this milestone.

## Review and verification evidence

Design inspection on 2026-10-13 confirmed the current router gates most administration
with an installation-operator grant, the browser session has no user ID or persisted
revocation, call-spec authoring distinguishes installation and tenant authority, and
`installation_setups` requires a demo-tenant reference. Relevant files are linked by
the milestone's checkpoint inventory. External references above were checked that day.
This is specification evidence only; runtime, migrations and browser acceptance remain
unchecked in the milestone. The accompanying labnote records documentation checks.
The latest same-day review adopts protected Superadmin/Admin roles, tenant-scoped
call/spec grants and installation-scoped service/user grants. Checked reserved
account-write permissions, current/proposed target roles, last-Superadmin races, role-edit revocation
and first-Superadmin setup. It removes the superseded delegation schema and rules.
The subsequent permission-name clarification encodes privileged writes as
`users.admins.write` and `users.superadmins.write`. Reviewed exact matching, independent
grants and both-kind checks on promotions/demotions; the actor/target outcomes are unchanged.
The final naming refinement uses `users.members.write` for ordinary accounts, giving
all three write keys a consistent category segment without changing their grants.
The no-email clarification fixes the browser route inventory and replaces the earlier
temporary-password/forced-change proposal with directly entered passwords and
confirmation for creation/reset. Reviewed reset rollback, target-session revocation,
self-reset behavior and read-only privileged accounts. No mail-backed recovery is implied.

Operational instructions: [setup, upgrades and local recovery](development/console-authentication-operations.md).

### Services and credential read consolidation — 2026-10-14

`tenant_services.read` includes provider credential metadata and masked previews;
there is no separate API-key read permission. Credential creation, replacement and
deletion still require `tenant_api_keys.write`. Full secrets are never returned.
An all-tenant Services read grant can satisfy the read prerequisite for assigned
Services or API-key writes; write scope remains unchanged.

The migration merges existing credential-read grants into Services read, preserving
the wider read scope and incrementing affected role revisions. It does not broaden
write grants. Splitting those merged scopes on rollback is ambiguous, so that
migration is irreversible. Role descriptions are removed from storage and APIs;
rolling back the column migration cannot recover discarded descriptions.
