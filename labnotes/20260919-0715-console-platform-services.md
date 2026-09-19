# Console platform services

- Started B1 after reviewed checkpoint A was committed. Added effective named binding
  directory data, preserving dormant tenant IDs and explicit disabled/missing policy
  states. No decrypted material crosses the directory boundary. Initial regression
  failed because the port did not exist; all four scoped persistence tests now pass.
- Added installation-authorized platform/tenant directory endpoints and platform
  replacement. Initial endpoint tests failed with missing routes; all nine endpoint
  tests pass, including actual CSRF enforcement for replacement.
- Added Rime credential input and a bounded authenticated dictionary coverage request,
  following https://docs.rime.ai/api-reference/other/oov. The public voice catalog
  explicitly needs no authentication and cannot validate a key. Coverage returns
  dictionary metadata without synthesizing audio; no live provider call was made.
  The validator and endpoint group passes 12 tests after its red run.
- Wrote three frontend journey tests and confirmed missing-route failures before
  wiring production routes. Platform save/reload/edit, tenant inherited readiness,
  named bindings, directory outage/retry and expired sessions now pass.
- User clarified service authoring access while this slice was in progress. Platform
  inheritance is not a tenant editing grant. Prioritized A2/A3 authorization and
  operator API-key writes; retained B1 work without committing or accepting it.
- A2 was reviewed and committed separately as `5a0b407`. Finished the already-started
  B1 Console slice using its existing operator browser session; A3 remains the next
  backend checkpoint. No API-key authentication is claimed by this Console work.
- The directory selects exact provider/name bindings, preserves dormant tenant IDs,
  and fails closed on unavailable storage or an oversized listing. Primary cards use
  provider-named bindings; alternate names remain explicit buttons, never an arbitrary
  first credential. Inherited details are read-only; B2 supplies policy mutations.
- Review found Rime missing from the older service inventory's backend/frontend
  allowlists. Both regressions failed before the compatibility fix and pass afterward
  (18 Calls administration tests and 14 frontend API tests). Rime storage/validation
  does not add a speech adapter or make Rime sufficient for voice-sample readiness.
- Chrome exercised the real operator login, PostgreSQL storage and encrypted reads
  against an owned disposable database. The fixture validator accepted synthetic
  keys only; no upstream provider request was made. Saved Google/Deepgram at platform
  scope, observed both tenants inherit readiness, rejected a replacement, successfully
  replaced it, then restarted the server and reloaded persisted state successfully.
  Inspected 1440px desktop and 390px mobile, including empty/connect, inherited details,
  saved masked inputs and validation recovery. Cleaned up the browser, server,
  authentication-state file and owned database afterward.
- Browser inspection caught a CSS output collision: importing setup CSS from the
  JavaScript entry caused esbuild to replace Tailwind's `admin.css`. Moved the import
  into the existing CSS entry and rebuilt; rendered desktop/mobile then matched the
  approved Console. The design hook flagged unchanged legacy CSS values when its entry
  was touched; this checkpoint changes only the stylesheet import, not those tokens.
- Production Telnyx public-key and webhook fields stay deferred to C, where they can
  actually be persisted and routed. Storybook retains those approved prototype fields.
- Final frontend suite: 173 tests, 29 files, zero failures. TypeScript, ESLint, CSS
  build, root format, compile with warnings as errors, strict Credo and unused
  dependency checks pass. Explicitly formatted changed child Elixir sources too.
- The preceding umbrella run completed 1,741 tests with three Gateway failures:
  two native WebRTC audio-pipeline waits and one five-participant WebRTC connection
  wait (40 exclusions). The subsequent serial-case run passes all 1,741 tests with
  40 exclusions (`--max-cases 1 --seed 772211`). This establishes a green full-suite
  run, not the cause of earlier intermittent failures.
- Final review found tagged tenant owners were accepted by the port but rejected by
  directory response validation. The focused regression failed as expected; a single
  normalization clause fixes it. Both focused cases and the full 114-test Calls suite
  pass afterward. Repeated root static checks pass. Reviewed exact staged changes
  before committing; scoped Telnyx callers and programmatic keys remain later slices.
