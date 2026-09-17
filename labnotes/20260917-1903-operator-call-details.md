# Operator call details

## Scope

Checkpoint 7 of `operator-login-and-admin-dashboard.md`: move Console call inspection from the
legacy tenant API-key browser session to the installation operator, connect the approved React call
details page, and retire the superseded LiveView UI.

## Decisions

- Added a Calls-owned `CallReadAccess` derived from the installation operator plus an explicit
  tenant key. Existing tenant `Principal` reads remain supported; Console does not fabricate one.
- The admin call-details endpoint returns the current tenant/definition context and the latest
  inspection snapshot. It has no cursor or `as_of` contract.
- Kept inspection JSON, call-details document, and recording resources, protected by the operator
  session. Old HTML routes redirect to the exact React destinations.
- Deleted the unreachable LiveView call console and tenant-API-key sign-in presentation modules.
- The React host owns fetching and strict response validation, then hands the snapshot to
  `@vxpipe/core` and renders `@vxpipe/react`.

## Red-green evidence

- Calls inspection initially rejected installation-operator access; the focused test failed until
  `CallReadAccess` was introduced and tenant containment was enforced.
- Missing-tenant admin call details initially returned 503; the new endpoint test failed until it
  mapped missing tenant and missing call to the same 404 response.
- A real persisted pre-current `CapabilitySelection` crashed the presenter because it stores its
  model under `options`. A focused presenter regression failed with `KeyError`, then passed after a
  backward-compatible model lookup.
- The real browser showed the embedded console without its package styling. Importing
  `@vxpipe/react/styles.css` into the admin stylesheet fixed desktop and mobile rendering.

## Verification

- Calls: 103 tests, 0 failures.
- Persistence: 151 tests, 0 failures, 11 integration exclusions.
- Console: 154 tests, 0 failures, 1 integration exclusion.
- Console assets: 115 tests, TypeScript check, and ESLint pass.
- `mix assets.build` passes.
- The final umbrella run passes 1,696 tests with zero failures and 39 exclusions. Formatting,
  warnings-as-errors compilation, strict Credo, unused-dependency checks and the Storybook production
  build also pass.
- Headless Chrome verified the real command-to-browser login, call-list navigation, historical call
  rendering, responsive layout, and mobile participant selection at 1440×900 and 390×844.
- GPT-6 Astra xhigh approved the slice after fixes for retained-resource HTTPS, obsolete-request
  session expiry, legacy-cookie removal and malformed authority handling.
