# Tenant phone configuration

C3b2 adds an inline application form and published-number progress to the established
tenant service setup surface. It inherits the Console's existing tokens and controls;
no new visual identity or credential policy is introduced.

- Four production UI regressions initially failed on missing application controls,
  phone routing and tenant verification-key guidance. All four now pass, together
  with the nine existing scoped-service tests.
- Create/edit carries CSRF and the canonical application ID, then reads durable
  metadata again. Failed writes preserve the form. Successful writes followed by a
  failed reload close the form and offer retry instead of duplicate submission.
- An API-only tenant override cannot borrow the platform verifier flag. Local
  applications remain visible; connection details lead to the existing credential
  form and scoped webhook URL. Published routes show revision and ambiguity, with
  explicit bounds and no claim of live calling readiness.
- TypeScript and ESLint pass. The design hook flagged a 13px literal outside the
  documented type ramp; corrected it to the existing 12px data size.
- Rendered desktop/mobile/restart checks and final review are complete; final
  combined umbrella acceptance is recorded separately under D2.
- Review added two focused regressions: stale save notices masked later reload
  failures, and successful saves left keyboard focus on the document body. Both
  failed for the expected reason, then passed after clearing notices on reload and
  restoring focus to the phone-routing heading after save/reload.
- All 187 frontend tests passed before these refinements; the four affected tests
  passed afterward. TypeScript, ESLint, formatting, CSS/esbuild and `mix assets.build`
  passed. Final frontend verification after rendered review is recorded below.
- C3b1's unrelated native handoff timeout did not recur in five unchanged isolated
  runs. No runtime fix or timeout adjustment is inferred from those passing runs.
- First rendered pass proved real persisted create/edit, tenant API-only public-key
  guidance, whole-payload credential replacement, duplicate application rejection
  with preserved input, and correction/save on desktop/mobile. The automation CLI
  stalled on some coordinate clicks/element waits; direct DOM clicks through
  agent-browser completed the same rendered forms. Operator state needed an explicit
  `state load` after browser startup. Product authentication was unchanged.
- The disposable route-publication fixture omitted Google's explicit credential name
  and failed closed against the absent `default` binding. Its cleanup removed that
  owned database. Corrected the fixture to name `google` and resumed browser/restart
  acceptance on a fresh owned database seeded through the same application APIs.
- The visual correction batch removes a duplicate section divider and lets the
  Add application button wrap below its heading on narrow screens without splitting
  its label. Final 1440px desktop and 390px mobile captures pass independent finish
  review with disposition `ship` and no material findings. The documenter confirms
  this local extension adds no durable design-system rule; no DESIGN.md change.
- The corrected disposable fixture publishes a real call spec for each tenant:
  platform inheritance and tenant override each show their own application, number,
  published revision and caller participant. A simulated directory request failure
  offers retry and recovers without another write. Neither viewport overflows.
- Restart and encryption-key rotation retain both application identities and
  published routes. Fresh rendered navigation after rotation shows the correct
  credential source for each tenant. The owned browser/server/database are closed
  and removed after acceptance; no live Telnyx call was attempted.
- Final frontend verification: all 187 tests across 31 files pass, plus TypeScript,
  ESLint and Prettier. Local source review checked request cancellation, recovery,
  bounded metadata parsing, immutable edit fields, keyboard focus and scope guidance.
