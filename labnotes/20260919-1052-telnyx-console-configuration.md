# Telnyx Console configuration

C3a joins the production credential form, configured-field metadata, and scoped
callback URLs. Application registration and published-number progress remain C3b;
legacy webhook removal and final acceptance remain D (latest user correction).

## Decisions and evidence

- The Console accepts the optional Telnyx verification key in the same complete
  encrypted payload as its API key. Updates replace the whole payload. The form
  explicitly explains that leaving a previously saved public key blank removes it.
- Directory reads decrypt only inside Persistence and return allowlisted field
  names. An unreadable tenant row reports unavailable with no configured fields;
  it never borrows the platform public-key flag.
- Gateway owns public-origin resolution and scope URL construction. Runtime reads
  allowlisted settings, preserves the explicit telephony override/path prefix,
  defaults a public APP_HOST to HTTPS, and exposes safe Console URL metadata.
  HTTP local origins are previews and do not enable live telephony ingress.
- A scoped outgoing service uses its retained credential owner for callback URLs.
  Legacy callback and media paths retain their existing contracts.
- Initial Gateway run: 19 tests, three expected failures (missing origin resolver
  and the legacy outgoing callback URL). The implementation passes all 19.
- Initial Console run: 17 tests, three expected failures (missing runtime origin
  metadata and rejected Telnyx public-key payload). A further directory-URL
  assertion failed as expected; all 17 subsequently pass.
- Persistence configured-field regression failed on the missing public-key flag.
  The final five focused tests pass, including unreadable tenant payload behavior.
  The corruption fixture initially violated the ciphertext-length constraint; it
  now flips a byte while preserving the valid storage shape.
- Running the Persistence child exposed an unintended dependency on Gateway in
  runtime configuration. Gateway/Console settings now run only when Gateway is
  available, preserving independent child-app test execution.
- Two production UI regressions failed on the missing webhook field, then passed.
  All 183 frontend tests, TypeScript and ESLint pass. Browser and final umbrella
  verification are still pending.

- Chrome at 1440×1000 and 390×844 verified platform public-key save/masked edit,
  inherited read-only details, tenant URL switching with empty override fields,
  rejected-key recovery, and clipboard success/failure feedback. A fresh server
  retained an API-only tenant override with no borrowed public-key placeholder.
  Removing it restored the platform URL. Storage was real encrypted PostgreSQL;
  provider validation was synthetic. No live upstream acceptance is claimed.
- A final optional second-tenant navigation overlapped fixture shutdown and was
  not completed; it is not included in this checkpoint's browser evidence. The
  owned browser, server, authentication state and disposable database were cleaned up.
- User correction during verification: remove legacy Telnyx webhook code instead
  of maintaining its transition path. Updated the main plan, binding decision and
  milestone index; route/caller removal will be a separate reviewed checkpoint.
- Root format, warnings-as-errors compile, strict Credo and unused dependency
  checks pass. The full serial umbrella run is in progress.

- First final umbrella run: 1,785 tests, one incoming CallIngress lifecycle failure,
  40 excluded; all other applications passed. It reproduced independently on the
  19th focused iteration. The separate incoming-leg test-isolation checkpoint
  gives each test its own service/ingress identity and passes 50 reruns.
- Code review found that URI.parse silently drops a malformed explicit port. A
  new regression failed with a normalized URL; validating URI.new first makes it
  pass without exposing the supplied configuration. Final umbrella rerun follows.

## Final review and acceptance

- Final combined umbrella: 1,786 tests, zero failures, 40 excluded, with seed 772211
  and max-cases 1. Root format, warnings-as-errors compilation, strict Credo and
  unused-dependency checks pass. Frontend: 183 tests, TypeScript, ESLint and assets pass.
- Reviewed credential replacement semantics, allowlisted metadata, operator/CSRF
  boundaries, shared origin/prefix handling, selected-owner callback generation,
  named-account URL exclusion and desktop/mobile recovery. No secret values are
  returned in directory responses or prefilled in saved forms.
- C3a is complete. C3b application/number-route setup and the approved legacy
  webhook deletion/final acceptance remain open. Existing legacy callbacks are
  unchanged in this checkpoint and will be removed in the next reviewed slice.
