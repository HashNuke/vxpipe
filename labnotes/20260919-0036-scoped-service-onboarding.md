# Scoped service onboarding

## Scope and decisions

- User requested a plan for platform/tenant services and then explicitly requested
  Storybook implementation now. Production scope resolution, persistence and webhook
  handling remain a documented follow-up. No real credentials or provider calls used.
- Rechecked the user's branch change: working branch is now main at e6b6fdb; relevant
  source files were unchanged. No other user changes were overwritten or staged.
- Added platform service navigation, shared setup grids, inherited-service details,
  whole-credential tenant overrides, explicit disable and return-to-platform actions.
  Effective services drive readiness, recipes and the tenant directory. Only tenant
  overrides/policies are retained in each tenant's prototype state.
- Telnyx connect/edit show a read-only scoped URL and Copy action. Inherited details
  show the platform URL; starting an override changes to the tenant URL. A tenant save
  cannot inherit the platform public-key-configured flag. Saving API-only credentials
  to an existing same-scope Telnyx connection retains that scope's configured flag.
- Storybook reads APP_HOST, PORT and VXPIPE_DEV_TLS in Node and injects only the derived
  public origin. Local default is http://localhost:4000. No use of the Storybook origin
  and no environment map exposed to the browser. Tests supply explicit origins.
- Detailed source review found tenant-only credential ownership/constraints and public
  keys attached to telephony-service records. The plan covers scoped storage/encryption,
  named bindings, verification before routing, application ownership, old URL migration,
  media/initialized-client contracts and operator authority; no backend gate is marked done.

## Verification and barriers

- Red: seven scope/browser-contract tests failed for missing webhook fields, missing
  platform state and missing inheritance behavior; origin tests failed on the missing
  helper. The first implementation passed all 38 focused tests across four files.
- An added keyboard-focus assertion failed after opening an override from inherited
  details. Depending focus on the override transition fixed it.
- Full Console frontend suite: 165 tests across 27 files pass. TypeScript and ESLint
  pass, including the final run after the wrapping URL field change.
- Chrome inspected dark desktop/mobile platform connection, inherited details, tenant
  override entry/save and light platform grids/edit. Verified both URL scopes, optional
  public key, Copy feedback and the saved override's Public key needed state. A platform
  connection still retained its configured public key after the tenant-only save.
- Initial single-line URL clipped the path on mobile. Changed to a wrapping read-only
  textarea with a labelled Copy button and included textarea in the dialog focus trap.
  Final screenshots show the full URL; mobile viewport checks confirm no horizontal overflow.
- Reused the requested modal styling. Persisted a file-scoped design-check exception
  for the existing 50-percent black backdrop; no visual-system drift was repaired.
- Restarted only the owned Storybook process for environment/story-index changes. It
  exited after SIGTERM before a later kill attempt. Storybook remains on port 6006;
  bin/dev was untouched. The scoped-services browser session is closed.
- Storybook production build passes (existing chunk-size advisories). Documentation
  checks resolve all 120 relative links; whitespace checks pass. Root format, compile
  with warnings-as-errors and strict Credo pass. The full umbrella suite and
  mix deps.unlock --check-unused also pass (combined root command exits 0).

Evidence is under ignored tmp/onboarding-storybook/scoped-*. Logs include initial
red, focus red, frontend final and server output. No commits or staging performed.
