# Standalone call header and quieter navigation

## Scope and decisions

- Follow the user's compact admin hierarchy and remove stacked horizontal rules
  across Tenants, Call definitions, Calls and Services. Keep active underlines and
  column-header separators; use quieter internal row separators and unboxed lists.
- Treat call details as a standalone inspection tab. The initial read-only context
  interpretation removed useful escape routes. The user clarified that the
  breadcrumb must match the other pages: use the shared Breadcrumbs component
  with working Tenants, tenant workspace and definition-filtered Calls links,
  alongside the brand, without adding sibling tabs or a terminal Call details label.
  Call ID/version, partial-history warning and live controls remain in the existing
  console toolbar. Preserve the same context in loading/error states and on mobile.
- Use native new-tab anchors with an accessible announcement and opener isolation.
  Storybook links load the full-journey fixture at the selected call, preserving theme;
  production links retain the approved directly loadable call route.
- Preserve concurrent credential-management changes, including overlapping files.

## Red / green checkpoint

- Updated focused page, journey and production-host contracts before implementation.
  Initial run: 10 failures, 38 passes. Expected failures included absent `_blank`
  targets, navigation still present on details, and missing read-only brand context.
- After implementation: 47/48 focused tests pass. The remaining credential journey
  assertion still expected the old provider identifier label and is unrelated to
  this navigation change. Updated that assertion to the actual named credential
  edit action; all 122 console tests then passed.
- Wrote the clarified breadcrumb/return-link tests before restoring links: five
  expected failures, then green. The full 122-test console suite remains green,
  including standalone call links and real breadcrumb destinations in Storybook.
- Console TypeScript, lint and CSS build pass. Shared package build and all 39
  core/React tests pass. Umbrella format, warning-free compilation and strict Credo
  pass. The full umbrella test run failed in two gateway tests and then exited;
  it is not a green umbrella run. Both affected files pass on focused retry
  (17 tests). No gateway implementation was changed for this UI work.
  Failing tests: RoomAudioIngressTest's actual Twilio decoder initialization
  (`{:error, :unavailable}`) and CallIngressTest's incoming retry identity
  (`{:error, :telephony_leg_unavailable}`). Root cause is not established.

## Verification notes

- Initial headless Chrome pass exposed stale packaged CSS overriding the shared
  source stylesheet in the already-running Storybook preview. Rebuilding packages
  and refreshing the admin CSS source invalidated that cached import; both the
  development preview and production Storybook build show the intended separators.
- Rendered dark desktop/mobile service and call directories, dark ongoing and
  partial-history details, and light ended details. Verified a real call-row click
  opens a separate tab and retains the source directory. Final breadcrumb clicks
  reached the tenant definitions page, the correctly filtered Calls page and the
  Tenants directory, including from the unavailable-call state. Inspected Tenants,
  definitions and the restored call header at 1440×900 and 390×844. No page overflow
  was introduced; existing wide ledgers retain their own horizontal scroll regions.
- User explicitly confirmed keeping the existing colorful provider-logo styling.
  No provider artwork was changed. The Inter detector warning was exempted only in
  the admin stylesheet because DESIGN.md prescribes that typography.
  A final direct stylesheet detector scan returns no findings; no provider-logo
  warnings were suppressed.
- Final format, warning-free compilation, strict Credo and unused-dependency checks
  pass. Console ExUnit passes 157 tests (one excluded); Storybook production rebuild
  and the final Console check/lint/CSS build pass.
- Concurrent calls-directory redesign started during final verification. Preserve
  its new column/lifecycle/filter changes; the green test counts above describe the
  completed header checkpoint, not an assurance about later in-progress edits.
