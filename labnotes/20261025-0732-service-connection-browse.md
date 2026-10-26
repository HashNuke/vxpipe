# Service connection browse

## Request and scope

- User reported AI credential modal spacing regression with a Google AI Studio
  screenshot, and requested service discovery outside the modal.
- Services remains the connected inventory. Connect a service opens a directory
  page with desktop category sidebar, mobile category dropdown and search.
- User clarified directory entries should never check whether already connected.
  All entries always have Connect; connection status belongs to the inventory.
- Continued Storybook-only scope. No production components, routes, backend,
  dependencies or lockfiles changed. No commit requested.

## Review and implementation

- Fresh independent Impeccable review confirmed the screenshot's cause:
  prototype CSS set every SetupDialog to zero padding, while the reused legacy
  ServiceSetupModal depended on dialog-root padding. MCP forms already supplied
  their own padded scroll body and footer.
- Replaced the modal picker with isolated ServiceDirectory. Included all 13
  existing setupProviders, six MCP presets and Custom MCP; preserving provider
  reachability after removing the legacy dropdown.
- Added fixed-provider ProviderCredentialsDialog for AI and telephony. Reused
  SetupDialog, Button, ServiceLogo, fields, tokens and pure credential validation.
  Testing/saving remain local simulations. MCP authentication controls retain
  their previous design; removed their in-modal All services navigation.
- Directory category/search state survives modal dismissal. Removed the parent
  close handler's forced focus to the inventory trigger; SetupDialog restores
  focus to the service-specific Connect button.
- No design suppressions added. Incumbent product/system design files preserved.

## Evidence

- Red-first: five directory/fixed-provider contracts failed against the previous
  modal flow. After implementation, all 12 focused prototype tests pass.
- TypeScript and ESLint pass. Full frontend: 829 tests across 106 files pass.
  Static Storybook build passes with the existing large-chunk advisory.
- All root completion checks pass: format, compile with warnings-as-errors,
  strict Credo, full umbrella tests, and unused-dependency check. Combined command
  exited zero. Gateway was the long lane (376 seconds, 868 tests, zero failures).
- Headless Chrome inspection at 1440×1000, 1024×768 and 390×844; dark/light
  directory, filtered and empty results, Google/Deepgram credentials, longer
  Telnyx form, and retained Cal.com connection form. Captures live under ignored
  `.impeccable/review/` with directory-* and *-credentials-* filenames.
- Actual mobile interaction: selected AI services, searched deepgram, opened
  credentials, pressed Escape; query remained and active element was Connect
  Deepgram. Document scroll width equaled viewport width (390px).
- Fresh full review of the corrected flow returned `ship`, with no required
  material fixes after inspecting all 15 captures and source. Scope is the
  Storybook UI, not real integrations. Browser inspection session closed; the
  existing Storybook server remains running on port 6006.
- Documenter returned `ship`: workflow documentation matches the build, existing
  product/design files need no changes, and imports remain confined to stories
  and tests. Pre-existing design-document drift was not repaired.

## Remaining scope

The prototype does not implement service registration, credential persistence,
OAuth requests, or real provider connectivity. The existing backend and shared
production credential modal remain unchanged pending workflow review.
