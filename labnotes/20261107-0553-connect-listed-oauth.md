# Connect listed OAuth MCPs

## Checkpoint plan

- Reuse existing directory lookup, bounded preflight/preparation, encrypted OAuth
  attempt storage and callback completion. New proposals re-resolve the listing;
  saved reconnect and in-flight callbacks use accepted snapshots without a public
  directory dependency. Carry the snapshot inside the authenticated encrypted
  attempt payload and project it into public connection configuration on success.
- Ignore listed browser URL/authentication overrides and reject arbitrary
  snapshot, endpoint/scope/request-parameter/header overrides. Directory scopes
  remain display hints; existing resource/challenge scope selection owns requests.
- Resolve recipe preferences against live advertised browser-grant capabilities.
  Managed CIMD has no extra fields; DCR accepts only its optional initial access
  token. Preregistered clients need client ID and their actual registered client
  authentication method/secret/key, constrained by live supported capabilities.
  Authorization-server supported methods alone do not identify that client's
  registration, so do not silently guess a method from the presence of a secret.
- Reuse compatible existing DCR registration before issuing a fresh registration.
  Prefer the existing protocol composition; a bounded credentialless capability
  read followed by ordinary Connect-time protocol revalidation is acceptable if
  it avoids introducing a second discovery/registration implementation. Revalidate
  selected capabilities before credential side effects if metadata changes.
- Verify exact draft/reference/accepted snapshot/resource binding in Calls, and
  generation/tenant/state before reconnect credential use. Completion must retain
  accepted directory identity/name and reject a mismatched port result.
- Tests must be written and fail before implementation. Cover every registration
  recipe, unsupported/changed capabilities, overrides, outages during callback and
  management, registration reuse, authority loss and stale generations. Listed
  machine grants remain outside the published V1 directory recipe; custom machine
  support is already implemented separately.

## Source and design review

- Rechecked the approved [MCP 2025-11-25 authorization profile](https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization).
  Its registration priority uses existing preregistered information, then supported
  CIMD, DCR fallback and user-entered client information. Directory preferences
  cannot establish server capability. Current backend protocol modules already
  enforce capability, PKCE, callback/resource and issuer checks.
- The attempt repository already encrypts/authenticates the full private payload;
  adding accepted configuration there does not require another table or store.
- Independent adversarial design/code review is recorded below, separately from
  implementation and acceptance evidence.

## Implementation and verification in progress

- Preparation's four initial red tests failed as expected before listed input and
  accepted-snapshot support. The DCR fixture initially asserted the original URL;
  SecureHTTP correctly supplies a pinned address, so the assertion now checks the
  registration path. Preparation and existing completion tests pass together.
- Five Calls regressions reproduced missing proposed-entry/draft validation,
  browser override handling, saved-snapshot preparation and callback identity
  checks. Two Console callback regressions reproduced dropped directory identity
  and redemption before resource/recipe binding. After implementation, 28 focused
  Calls tests and 16 Console tests pass.
- The existing encrypted attempt payload carries the accepted snapshot. Callback
  completion copies it into public configuration and removes it from saved
  credentials. New proposals use the existing directory cache; saved preparation
  takes a server-owned snapshot through a distinct port operation.
- Independent adversarial review found that missing resource metadata plus an
  explicit issuer must retain Preflight's Own-client fallback. Managed capability
  hints alone cannot select CIMD/DCR on that path. The red regression reproduced
  rejection of valid client credentials; new and saved preparation now use the
  existing Own-client path. A second review finding reproduced malformed issuers
  returning HTTP 503; validation now returns 422 before directory/protocol work.
  Both fixes and capability-loss verification are tracked in the milestone.
- Direct two-pass metadata tests verify loss of CIMD or S256 prevents registration
  and handoff. Session/CSRF endpoint tests with real encrypted repositories verify
  create, single-use callback during directory outage, connected DCR reuse, refresh,
  revocation and fresh retained-ID registration, namespace/snapshot preservation,
  stale generations and cross-tenant rejection. The endpoint fixture initially
  conflicted with Phoenix's imported response/2; renamed its local helper.
- Final focused Console group: 32 tests, zero failures. Root format, compilation
  with warnings as errors, strict Credo and unused-dependency checks pass. Full
  umbrella suite subsequently passes all 4,931 tests (201 excluded, seed 181095),
  following two independently reviewed test-only synchronization corrections.
  The first run failed the outgoing admission monitor race; the second was stopped
  after the terminal speech-overflow fixture race. Both exact assertions remain
  intact, and the third full run is clean. Final adversarial source and exact-index
  checkpoint review found no remaining issue. No UI change
  or authenticated rendered-browser acceptance is claimed by this backend checkpoint.
