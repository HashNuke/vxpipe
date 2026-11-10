---
title: Accounts, tenants and access
description: Set up accounts, tenant permissions and machine access.
sidebar:
  order: 5
---

## First account

After migrating an empty installation, open `/auth/setup`. Create the first
Superadmin and save the Installation URL. Keep initial setup reachable only by
the intended operator until this is complete. Subsequent visits use `/auth/login`.
Email identifies an account; Vxpipe does not send verification or password-reset
email.

For a populated installation that has no accounts yet, the trusted source-host
command `mix vxpipe.login` issues a one-time setup proof. Enter it at `/auth/setup`.
The proof expires after 15 minutes; this command refuses after setup is complete.

## Roles and tenant assignments

| Role | Access |
| --- | --- |
| Superadmin | All operational resources and all account categories. Retain at least one enabled Superadmin. |
| Admin | All operational resources; can manage ordinary accounts, but not Admins or Superadmins. |
| Tenant Manager template | Read/write operational resources within assigned tenants. |
| Tenant Member template | Read calls and call specs within assigned tenants. |

Ordinary roles can be edited. Authorization uses their registered permissions,
not their names. A Read or ReadWrite tenant assignment caps a role's assigned-
tenant grants; it never adds a missing permission. Calls and call specs always
belong to a tenant, even when a role can access every tenant.

Use the tenant directory to create tenants, then assign users the access they
need. Platform services are installation resources; tenant membership alone does
not authorize editing them.

## Passwords and recovery

Passwords accept 15–128 characters, including spaces. Users change their own
email/password at `/account` by confirming their current password. Administrators
can reset accounts only within the role rules above. There is no reset email.

If Superadmin passwords are unavailable, run `mix vxpipe.recover` from the trusted
source host with the installation's database configuration. At `/auth/recover`,
enter the one-time proof, an existing Superadmin email and a new password. The
proof expires after 15 minutes. Recovery re-enables that account and revokes its
old sessions. Treat the printed proof as a secret.

Browser sessions expire after 12 hours. Password, role, membership and status
changes invalidate affected sessions. Logout revokes the stored session.
Revoking account access does not terminate a call already admitted.

## API keys

Manage keys under **Settings → API Keys** (`/api-keys`):

- **Create & Join Calls:** one tenant's `calls` scope.
- **Full Tenant Access:** one tenant's independent `admin` and `calls` scopes.
- **Full Platform Access:** installation authority; issuance is Superadmin-only.

The secret is returned once. Save it in the integrating backend's secret store.
Listings show metadata and a masked suffix, never a recoverable secret. Issue a
replacement, move clients to it, then revoke the old key. Revocation rejects new
authentication; it does not undo existing calls or consume their join credentials.

Key management permissions do not themselves allow issuing more authority than
the actor possesses. Provider credentials are separate: they authorize Vxpipe to
call an external service. API keys authorize an external client to call Vxpipe.

Platform MCP uses browser OAuth consent, not static API keys. See
[HTTP API and platform MCP](api-and-mcp.md).
