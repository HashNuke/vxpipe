# Personal settings pages

## Scope and decisions

- User identified the tenant/main sidebar on the connection-management preview;
  personal pages belong under Settings → For you as Your account and Your
  connections. Remove the preview's main-sidebar My account shortcut.
- Both destinations remain available to signed-in users with no administrative
  grants. The same Settings entry falls back to /account for those users.
- Keep the existing self-account form and password validation, separately from
  the connections list. Reuse the shared SetupDialog for named revoke confirmation.
- The user requested a new implementation milestone covering recent CIMD/DCR and
  authentication work. Added personal-settings-and-mcp-consent, unchecked in the
  index; metadata/protocol/routing acceptance is distinct from Storybook evidence.
- Keep the production route/sidebar cutover in that milestone. Story harnesses
  explicitly enable previewPersonalSettings; shared revocation confirmation also
  improves the existing production embedded list. No OAuth backend changes.
- Incumbent Operator's Bench, existing form/navigation/dialog components; no new
  visual identity, assets or dependencies. Setup was already completed in this checkout.

## Implementation evidence

- New focused tests initially failed 9 cases for missing settings personal links,
  missing confirmations, old title/link copy and embedded account connections.
- After implementation, all 19 focused tests across four files pass. Tests cover
  cancellation with no request, success/failure, focused account details, member
  navigation and the link from consent through confirmation to revoke success.
- An initial frontend command ran from the umbrella root and matched no files;
  reran correctly from Console assets before implementation to establish red.

## Verification

- Existing story navigation tests needed to follow Back to tenants before opening
  a tenant; the main-app sidebar now exposes Settings rather than My account.
- Two additional red tests found divergent preview save behavior: the account
  harness signed out on email-only edits; the navigation harness discarded edits.
  Both now retain email edits and sign out after password changes, matching the
  existing production distinction. The expanded relevant suite passes 147 tests
  across 26 files; 21 production account/authentication regression tests also pass.
- TypeScript, changed-file ESLint and the final Storybook build pass. Root format,
  warnings-as-errors compilation, strict Credo and unused-dependency checks pass.
- Headless Chrome inspected desktop 1440 and mobile 390 layouts, Settings/admin
  and member-only groups, account password fields, mobile drawer navigation,
  cancel/focus return, success removal/status focus and error/retry confirmation.
  Dark and light confirmations fit without horizontal overflow; no browser errors.
  One transient blank success capture was discarded and replaced after settlement.
- Impeccable detector returned no findings. Fresh finish reviewer returned ship,
  no material fixes, for the preview/shared-confirmation scope; production
  implementation remains pending. The standalone shared sidebar story was also
  aligned with the preview navigation and checked in the browser.
- New milestone links resolve; index numbering is sequential. Counted checkboxes
  rather than copying its stale summary: 60 total, 47 complete, 13 pending.
- Independent documentation review passed after clarifying that client_name
  remains required by the existing profile; only website/logo are optional.
  No design-system artifacts changed.
- Full root `mix test` passed: 5,226 tests, zero failures, 376 exclusions. All
  five root completion checks pass. Storybook remains available on port 6006.
