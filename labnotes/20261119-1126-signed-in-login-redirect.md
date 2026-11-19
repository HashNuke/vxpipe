# Signed-in login redirect

- Investigated a reported anonymous admin call-page access concern. The admin route passes through RequireUser and checks tenant calls.read access. The login page previously rendered without validating an existing session, explaining why a signed-in browser could still display the login form.
- Added a login action that validates the session through UserSession and redirects authenticated users to the existing dashboard destination `/`. Anonymous or invalid sessions retain the login page.
- Red: focused user-auth tests reported 33 tests, one expected failure because authenticated login-page navigation returned HTTP 200 rather than a redirect.
- Green: user-auth endpoint, RequireUser and legacy operator route tests passed: 41 tests, zero failures. Includes a regression confirming anonymous call-detail navigation redirects to login. Changed-file formatting and diff whitespace checks passed.
- Production access is not confirmed: anonymous requests from this environment received HTTP 403 at the edge for both URLs. This is not evidence of application authentication behavior.
- Rendered browser verification was attempted using an isolated local endpoint with dummy identity fixtures. Chrome could not launch because its sandbox is unavailable on this host; rendered inspection remains unverified. No production session or provider was used.
- No deployment performed. Full-suite verification remains deferred until milestone implementation is complete, per user instruction.
