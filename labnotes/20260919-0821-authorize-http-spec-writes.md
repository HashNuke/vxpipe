# Authorize HTTP spec writes

- Started after reviewed operator-key lifecycle/status commit `c6b83d9`.
- Added Gateway red tests for operator/tenant create, immutable update and publish,
  exact principal propagation, key/scope rejection, body option injection rejection,
  and safe 403 responses for platform-only service references.
- All four initial tests failed with missing routes. Added a thin Gateway adapter
  to Calls' principal-aware save/publish boundary, explicit operator/tenant paths,
  strict request fields, metadata-only responses and default-disabled embedding.
- A further red regression showed an escaping backend exception; the HTTP boundary
  now maps unavailable/failed collaborators to 503 without exposing their messages.
  The complete 41-test Gateway status/authoring/mount/endpoint/admission group passes.
- Actual HTTP against an owned disposable PostgreSQL database proved operator
  shared-service create/update/publish; tenant create/edit/publish each returned 403
  until tenant credentials existed. Rejected writes consumed no revision. Tenant
  publication then succeeded and revision numbering continued after a fresh-process
  restart. Key replacement/revocation and scope rejection also passed. No upstream
  provider was contacted. Removed the owned server, database and private key files.
- Root format, warnings-as-errors compile, strict Credo and unused-dependency checks
  pass. The combined A3 umbrella run passes 1,754 tests, zero failures, 40 exclusions
  with `--max-cases 1 --seed 772211`.
- Pre-commit review checked route-selected authority, strict request fields, the
  principal-aware Calls boundary, complete resulting-spec ownership checks, safe
  error projection, default-disabled embedding and hosted runtime configuration.
  Requests cannot inject repository options or select their own authority. No
  remaining finding in this checkpoint; positive scoped carrier authoring remains C.
