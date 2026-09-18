# Demo tenant binding

The first-use Console creates one tenant named `DemoTenant` through
`Vxpipe.Calls.ensure_demo_tenant/2`. Its installation identity is the
`installation_setups.default` record, not the tenant's editable display name.

## Decision

- Calls owns the installation-operator workflow and generates a candidate tenant.
- Persistence atomically inserts the candidate and its singleton installation binding.
- Repeated requests return the bound tenant. A concurrent singleton conflict rolls back the
  losing candidate transaction and reads the winning binding.
- An unrelated tenant named `DemoTenant` is not adopted. Display names are not identity.
- This workflow does not issue a tenant API key. The authenticated installation operator already
  authorizes the narrow Console setup operation, and silently generating a plaintext key would
  create a secret with no safe recipient.

The operator-authenticated, CSRF-protected endpoint is
`POST /admin/api/onboarding/demo-tenant`. It returns only tenant metadata and reports storage
failure as `demo_tenant_unavailable`.

## Rejected alternatives

- Looking up by tenant name would break after rename and could adopt an unrelated tenant.
- An in-memory or browser flag would not survive restart and would duplicate tenants after state
  loss.
- Startup seeding would mutate installations that never entered onboarding and would compete with
  explicit setup.

## Verification

Focused Calls tests cover authority, first creation and retry. Persistence tests cover durable
retry and same-name isolation. Console endpoint tests cover operator authentication, CSRF,
metadata-only output and unavailable storage.
