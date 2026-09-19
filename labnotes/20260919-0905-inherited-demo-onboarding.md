# Inherited demo onboarding

- B2 integration review found the older `/admin/onboarding` entry and sample installer
  still read tenant-only service inventory. This checkpoint uses the shared effective
  directory and routes credential management to the existing scoped setup page.
- Backend red tests reproduced inherited credentials being rejected and alternate
  names being accepted as prerequisites for samples that reference exact primary names.
  The effective-directory change passes all six sample installer tests, including
  disable/restore and idempotent installation. Existing edited samples remain protected.
- Frontend red tests reproduced ignored inherited services and missing disabled state.
  Follow-up red tests found inconsistent progress with an optional disabled provider
  and no recovery action after directory failure. Added Retry setup; readiness follows
  usable sample prerequisites. The production page never asks for inherited secrets.
- The initial UI run exposed one older mock still returning tenant-only inventory.
  Updated that fixture to the effective-directory contract; verification in progress.
- All 181 frontend tests (30 files), TypeScript, ESLint and the asset build pass.
  Focused backend checks pass: six installer tests and three onboarding endpoint tests.
  The full Console run initially found a second old tenant-inventory mock; changing
  it to the effective-directory contract restored the focused endpoint suite.
- Added explicit preservation evidence: after inherited installation, editing a sample
  creates revision 2; reinstall reports conflict without replacing that draft or the
  revision 1 publication. This existing behavior remains green.
- The first browser pass showed inherited service readiness at desktop size. Running
  the umbrella suite concurrently with the development server caused build-lock
  contention during reload; stopped only the owned waiting browser CLI processes.
  Complete browser submission/restart verification after the umbrella run releases it.
- Full serial umbrella run: 1,759 tests, one failure, 40 exclusions (seed 772211).
  Every owning service/Console suite passes, including all 180 Console tests. The
  unchanged native human-handoff `after_speech_adoption` case timed out waiting for
  `transfer.progress preparing` at line 2251. Earlier multi-listener failure did not
  recur in this run. Cause remains unresolved; root acceptance remains open.
- Chrome confirmed the inherited sample installation completed and disabled Deepgram
  removed sample readiness at 390×844. Restoring inheritance enabled idempotent
  installation again. A browser network-interception/restart overlap stalled the
  browser tool; reconnect after the owned server reports ready before further checks.
- After closing only the owned stuck browser daemon and opening a fresh named session,
  Chrome verified the restarted server retained the exact Demo identity, inherited
  services and all three revision-1 publications. Managed-service navigation and
  directory-read failure/retry passed using a temporary in-page fetch override, which
  was restored immediately. Desktop/mobile screenshots were inspected; no overflow.
  The old entry still refreshes sample labels via the explicit idempotent install
  action; effective service readiness is loaded from storage on every entry.
- Review covered exact-name readiness, tenant identity validation, installation-only
  authority, no inherited secret forms, cancelled/stale directory responses and edited
  sample preservation. Removed obsolete inline credential mutation code; scoped setup
  owns those writes. No remaining finding in this service integration; the native root
  failure above remains open. No media assertion or timeout changed.
