# Connect listed OAuth forms

## Plan

- Preserve the existing Console modal and field components. Fixed directory URL
  and authentication recipe; no URL/authentication-type/grant/advanced-parameter
  selectors for listed entries. Preregistered clients need an explicit actual
  client-authentication choice, ID and applicable secret/key, plus exact callback.
- Extend existing credentialless discovery with bounded listing references and
  verify the returned accepted entry. Saved management discovers the saved fixed
  endpoint without consulting the directory. Backend preparation remains authority.
- Select managed registration using live capabilities and the directory preference;
  unknown/partial/unsupported results block Connect with retry or issuer recovery.
  Preserve the backend's missing-resource Own-client fallback.
- Send only listing/revision/selected issuer and active required credentials;
  existing saved routes carry generation and no browser snapshot. Keep tab-local
  OAuth retry context public, bounded and scoped to actor/tenant/attempt. A restored
  listing cannot silently become an editable custom MCP proposal.
- Storybook uses in-memory fixtures; no provider HTTP. Inspect desktop/mobile
  managed, preregistered, missing/partial discovery, saved outage and return states
  in one bounded batch plus any required confirmation pass.

## Evidence

- Five initial production-dialog tests fail because listed OAuth is disabled and
  has no discovery/required fields yet. No implementation preceded these tests.
- Backend and test-only synchronization checkpoints are reviewed/committed
  separately. The listed forms now use fixed directory configuration, required
  client fields and tab-local public retry context. The initial focused 53-test
  group and TypeScript pass. A production return regression verifies denied listed
  consent restores the fixed form, revalidates its reference and excludes secrets.
- Inventory eligibility initially failed for the four browser OAuth recipes;
  the supported-recipe gate now accepts them while preserving authority, retired
  entry and existing-connection checks. All eleven inventory tests pass.
- Saved DCR selection exposed a necessary advisory contract: live metadata alone
  cannot tell the UI whether stored registration is still reusable. Two UI red
  regressions reproduce unnecessary registered-client fields when the registration
  endpoint disappears and discovery requests missing their saved generation.
  The hook/dialog now consume a bounded saved-connection discovery choice and
  omit both client fields and initial registration tokens when reusing DCR.
  All 23 focused discovery/dialog/return tests pass; backend implementation and
  verification follow below.

## Advisory discovery design review

Independent adversarial review confirmed that extending the existing discovery
operation is smaller and safer than a separate API or a reuse flag from GET.
Reuse depends on live issuer, supported auth, resource, scopes, exact callback and
stored secret expiry. Accept only connection ID, generation, draft revision and
optional issuer for saved discovery. Resolve the tenant-owned accepted snapshot;
never accept endpoint, listing, snapshot or credential overrides. Revoked records
must never decrypt old credentials. Missing/unreadable registration falls back to
fresh supported methods, using preparation's shared selection logic.

Return only the bound public discovery data and `{method, reusable}` advice.
Recheck authority, generation and installation after discovery; Connect revalidates
again. The checked installation must own both selection and returned client/callback
metadata. Outbound discovery remains credentialless, with no registration, token
exchange, connection or attempt write. Cover revoked/unreadable/expired clients,
scope growth, changed issuer/installation and held-discovery races before review.

## Frontend verification

- Full frontend suite: 1,030 tests pass across 136 files; TypeScript passes.
  ESLint reports only the existing SetupDialog initial-focus dependency warning.
- One bounded Chrome inspection batch at 1280×900 and 390×844 covers CIMD, DCR,
  explicit preregistered client authentication and masked secret entry, exact
  copyable callback, partial discovery/manual issuer recovery, multiple-issuer
  selection, missing-resource Own-client fallback and saved DCR reuse during a
  simulated directory outage. CIMD, preregistered and saved-reuse consent handoffs
  complete against the in-memory fixture. Controls remain contained and usable;
  no layout correction was required. The owned browser session is closed.
- The browser CLI does not support `find label ... select`; using the observed
  combobox reference with `select` completed the same inspection batch. No browser
  or provider HTTP submission was made by Storybook. Authenticated real-backend
  browser acceptance remains a separate open gate.
- Independent UI review found manual issuer recovery unmounted its input after
  the first character as discovery restarted. The regression failed after typing
  `h`; explicit recovery mode now preserves the same input and focus. All eight
  listed-dialog tests and TypeScript pass. The single rendered confirmation batch
  used a first key followed by keyboard typing, retained focus and reached ready
  discovery on desktop/mobile. Final frontend source review found no remaining
  issue, conditional on the agreed saved-discovery backend dependency.

## Saved discovery implementation

- Seven Calls boundary regressions initially rejected the new saved proposal.
  The existing route now validates its exact bounded input, refreshes current
  authority before secret resolution, loads trusted saved configuration and
  rechecks generation, lifecycle and installation after the bounded probe. Calls
  and reconnect share one loader for the permitted registration fields; revoked
  records never resolve credentials. The 42-test Calls group passes, including
  held-discovery authority/generation/installation changes and mismatched results.
- Four Console regressions initially failed because the saved port operation was
  absent. The new composition shares Connect-time method selection, returns only
  public method/reuse advice and binds callback metadata to the checked origin.
  Two fixture mistakes were corrected: the HTTP client's second argument is its
  pinned address, not headers, and browser OAuth requires the issuer-response
  capability. Fixtures now assert no private registration appears in HTTP settings.
- The encrypted-store/session/CSRF lifecycle test verifies reusable advice after
  the registration endpoint disappears and the directory becomes unavailable,
  stale/foreign proposals, malformed extras and fresh Own-client advice after
  revocation. Discovery performs no registration, token exchange or MCP check and
  leaves the stored generation unchanged. The four-test endpoint file passes.
- Backend adversarial review identified an optional-port compatibility gap: an
  existing adapter without `discover_saved/6` raised after registration resolution.
  The red regression reproduced it. Availability is now checked before repository
  or secret reads, returning the fixed discovery-unavailable result. Documentation
  review also removed two stale claims that listed OAuth forms were unavailable.
- Final independent backend source re-review is clean. Calls 43 / Console 37
  focused tests and all 1,031 frontend tests pass. TypeScript and ESLint pass with
  only the existing SetupDialog hook warning. All five root gates pass: 4,944
  umbrella tests, zero failures, 201 excluded (seed 426342). Independent review
  of all 33 staged paths is clean. Authenticated browser and retained-ID recovery
  remain separate open gates.
