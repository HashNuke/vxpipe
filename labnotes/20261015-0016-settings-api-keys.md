# Settings API-key management

User approved UI and backend together after inspection found the current API-key
page was Storybook-only. Separate management grants approved. Existing
tenant_api_keys.write actually controls provider credentials, so preserve that
contract and introduce access_keys read/write plus platform_api_keys read/write.
Full platform writes remain Superadmin-only. Key issuance cannot exceed issuer
operational access. Scope/architecture recorded in docs/api-key-access.md.

## Implementation checkpoints

- Added separate tenant `access_keys.read/write` and installation
  `platform_api_keys.read/write`. Tenant membership caps and issuance ceilings
  are enforced server-side; custom roles must explicitly opt into new grants.
- Preserved provider credential permissions under their existing internal name;
  renamed the UI label to Provider credentials. Platform key writes are reserved
  to Superadmins. Existing trusted operator keys retain their original behavior.
- Added hash-only persistent issuance, scoped metadata/search, revocation, and
  platform-key authentication through existing machine APIs. Applied migration
  to local development and test databases. Legacy suffixes remain unknown.
- Added Settings inventory/create routes, remote tenant selection, separate
  Tenant column, one-time secret reveal and permission-specific Storybook states.
- Initial domain, storage, UI and HTTP contract runs failed at the intended new
  boundaries. Storage testing caught a PostgreSQL varchar-array comparison issue;
  binding the scope array as a typed Ecto parameter resolved it. UI testing caught
  cmdk's accessible input label; set its Command label explicitly.
- The full frontend suite exposed a navigation search race: reloading navigation
  for every directory query remounted search results. Restricting that query
  dependency to the legacy `/my-tenants` redirect preserves pagination/search.

## Verification

- Focused domain: 2 tests; persistence: 2 tests; Console navigation/HTTP: 17 tests,
  all passing. Covers cross-tenant denial, issuance ceilings, platform restriction,
  one-time response shape and revocation authentication.
- Full frontend: 97 files / 753 tests passed. Final affected UI pass: 29 tests.
  TypeScript, ESLint and production CSS build passed.
- Root formatting, compilation with warnings as errors and strict Credo passed.
- Headless Chrome at 1440x1000 and 390x844: checked inventory, tenant-only Settings,
  searchable tenant selection, creation/reveal/Done, revoke confirmation, platform
  form and role permission rows. Storybook data is intentionally nonfunctional;
  persistence and HTTP tests verify the real backend boundaries.
- Full umbrella: 3,808 tests, zero failures (including 314 Console and 281
  persistence tests). Unused-dependency check passed. All five root gates passed.
