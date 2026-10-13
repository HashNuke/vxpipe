# Console account operations

The Console uses named email/password accounts and database-backed, revocable browser
sessions. Email is an identifier only; there is no email delivery or reset link.
The [authorization contract](../console-authentication-and-authorization.md) describes
permissions, tenant scopes and the protected account categories.

## First installation and upgrades

Run the normal database migrations before serving the Console. On an empty installation,
open `/auth/setup`, enter the first Superadmin email and a password with confirmation.
Setup commits the account, authentication singleton and initial session atomically;
it does not require a demo tenant. Protect the installation's network exposure until
this trusted first visitor completes setup. Subsequent visitors use `/auth/login`.

A populated installation cannot be claimed anonymously. From a trusted shell using the
same deployment database configuration, run `mix vxpipe.login`. Enter its one-time
setup proof at `/auth/setup` with the initial Superadmin credentials. The proof expires
after 15 minutes and is consumed in the setup transaction. This command no longer
issues a full-authority browser login link and refuses once setup is complete.
Existing tenant data, independent API keys and the separate demo-setup record remain
intact. Historical browser sessions and login-challenge routes no longer grant access.

Migrations seed exactly four roles: Superadmin, Admin, Tenant Manager and Tenant Member.
The first two are protected. Tenant Manager includes calls, call specs, services,
API keys and telephony applications within assigned tenants. Tenant Member reads calls
and call specs within assigned tenants. Ordinary templates can be edited; their names
do not confer authority. Each assignment defaults to Read only and caps assigned grants.

Migration `20261013000400` converts existing installation-scoped tenant-service/key
grants to all-tenant scope. It expands the untouched Tenant Manager starter template
with assigned service/key permissions and platform-service authoring; customized roles
are preserved. Its rollback deliberately raises before changing data: reconstructing
custom grants automatically would be lossy. Use a reviewed forward migration for a
policy correction, or restore a coordinated database/application backup.

## Passwords and recovery

Passwords accept 15–128 characters, including spaces; they are hashed with Argon2.
Users can change their own email/password at `/admin/account` by confirming their
current password. Account changes invalidate existing sessions.

Admins can create, edit, disable and reset ordinary accounts. Only Superadmins can
perform those administrative operations on Admin or Superadmin accounts. Both roles
can view the user directory and define ordinary permission-based roles. Password reset
asks the acting administrator for a new password and confirmation; the chosen password
works immediately. Resetting another user preserves the administrator's identity.

If all Superadmin passwords are unavailable, run `mix vxpipe.recover` from the trusted
installation shell. Open `/auth/recover`, enter the one-time proof, an existing
Superadmin email, the new password and confirmation. The proof expires in 15 minutes;
it cannot be used for initial setup or to reset an ordinary account. Successful
recovery re-enables the Superadmin, revokes old sessions and starts a new named session.
Treat the printed proof as a credential. Do not paste it into logs or tickets.

The final enabled Superadmin cannot be disabled or demoted. Setup completion is a
persistent singleton, independent of enabled-user counts; disabling accounts never
reopens first-run claiming.

## Sessions and access changes

Sessions expire after 12 hours. The browser carries an opaque token in the signed,
HttpOnly, SameSite=Lax cookie; HTTPS adds Secure. Only a digest is stored in the database.
Password, status, role and membership changes revoke affected sessions. Role-definition
changes invalidate sessions for every assigned user. Logout revokes the database
session; a storage failure reports an error rather than claiming successful logout.

Login/setup/recovery failures use database-backed throttling: 10 attempts per account
and 30 per client address within 10 minutes. Limits expire without permanent account
lockout. Authentication and authorization fail closed when required storage is unavailable.
CSRF and the existing Console transport/origin boundary remain in force.

Browser identities do not replace machine API keys, call admission tokens or carrier
webhooks, and account revocation does not terminate already admitted calls. User/role
mutations record safe audit events without passwords, hashes, raw tokens or proofs.
