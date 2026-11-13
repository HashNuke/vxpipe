# Configured MCP services

## Scope and findings

- Replace platform MCP `list_providers` with `list_services`. Discovery previously
  enumerated installed adapters, so unconfigured providers appeared with an
  availability flag. Keep the installed catalog used by model pickers separate.
- List connected native bindings and saved tenant MCPs after exact tenant
  `call_specs.read` authorization. Inherited platform bindings additionally
  require `platform_services.read`; current grants and OAuth tenant delegation
  remain authoritative. Filter before pagination. No credentials, endpoint URLs,
  raw tool catalogs, or private IDs are projected.
- Native `service` remains the provider ID; `credential_name` disambiguates
  existing saved credential bindings. MCP `service` identifies the saved
  connection used by a tool's `integration` field. No old MCP tool alias remains.
- Telnyx application IDs/names were already outside the call-spec schema. The
  actual gap was that platform inheritance required an extra tenant routing row.
  First resolution of canonical `telnyx` now persists that internal identity
  from valid inherited settings, under the existing transaction and configuration
  locks. A unique tenant/name conflict reuses the winning row. This preserves
  existing route joins and pinned-call identity without a second routing path,
  a bulk tenant backfill, or application metadata in call specs.
- Tenant credentials cannot silently inherit a platform application. Missing
  settings still fail, and existing tenant application overrides take priority.
  Editor choices now include the canonical configured Telnyx connection before
  its internal routing identity exists.
- Connected integrations were already local. Directory-outage browsing only
  rendered built-ins even though saved MCP metadata was present. Reuse the same
  saved-MCP row projection in the fallback, preserving search/category filtering
  and existing management permissions.

## Verification

- Red: new configured-service tests failed on the missing facade; MCP boundary
  tests failed because discovery still exposed `list_providers`; outage inventory
  failed to include the saved MCP; inherited Telnyx save failed with unavailable
  credentials; editor lookup omitted the inherited canonical connection.
- Green focused lanes: Calls catalog/lookup tests (19), Gateway MCP discovery and
  invocation tests (10), Console directory inventory/endpoint tests (13),
  Persistence Telnyx routing/configuration/store tests (34), connection compiler
  tests (5), and React directory/phone-connection tests (18).
- One added negative test initially expected the repository's detailed error from
  the public facade. Corrected it to the facade's intentionally generic
  `provider_credential_unavailable`; all seven routing tests then passed.
- Format, compile with warnings as errors, strict Credo, unused-dependency check,
  TypeScript and changed-file ESLint passed. No dependencies or schema migration.
- Headless Chrome inspection at 1440×1000 and 390×844: directory outage shows both
  Telnyx and saved Team tools, its Manage dialog opens, and mobile has no horizontal
  overflow. Phone picker displays Telnyx, assigns the fixture number, and returns
  to the participant inspector. Storybook uses an environment-free preview copy.
- No full suite, paid calls, live telephony tests, or environment-file reads.

## Release

- Committed and pushed implementation `783f41b8` to QA, built production assets
  and the release, built the local container image, and restarted `vxpipe.service`.
- Public Vitrum health returned `ok`; app and Caddy services are active. The
  running image label matches `783f41b8` and its memory limit remains 1 GiB.
- The deployed release catalog contains `list_services` and excludes
  `list_providers`. The public fingerprinted admin bundle contains the updated
  fallback heading and notice. Existing MCP clients need to refresh their tool
  catalog (reconnect) to discover the renamed tool.
