# Platform MCP CIMD

## Scope and design

- Add inbound CIMD client identification alongside DCR. Outbound participant MCP
  behavior is unchanged. Reuse Boruta, consent and credential stores, and ExMCP's
  hardened metadata fetcher; no new library or background service.
- Root cause observed while connecting Codex: its public DCR metadata includes
  `application_type: native`, which the old strict profile rejected. Accept the
  native/web metadata field and preserve the public-client security profile.
- Keep UUID foreign keys; attach an exact CIMD URL and metadata expiry to client
  rows. OAuth input cannot substitute a CIMD row's internal UUID for its URL.
- Native loopback port matching is relaxed only at authorization. Code exchange
  still requires the selected exact URI. Return the configured issuer on both
  approval and denial, and advertise CIMD and issuer identification.
- Cache validated metadata on demand using HTTP cache policy and application
  defaults (300 seconds, maximum 3,600). Network I/O precedes transactions; row
  revisions fence stale concurrent results. Consent pins a metadata digest.
- The additive migration preserves existing clients/grants. Pending authorization
  requests created before this migration must restart because they have no digest.
- Design checked against the project's MCP 2025-11-25 profile, CIMD draft-00 and
  RFC 9207. Latest draft-03 was also reviewed; we do not claim private-key client
  authentication or full implementation of its newer lifecycle recommendations.
  Detailed contracts and alternatives are in
  `docs/en/development/platform-mcp-clients.md`.

## Evidence

- Red: identity tests reproduced native DCR rejection, URL client-ID rejection
  and absent loopback matching. Persistence tests reproduced rejected CIMD
  authorization. Gateway discovery and Console issuer/identity display tests
  failed before implementation.
- Real public Codex metadata includes both literal-loopback and localhost
  callbacks. CIMD retains supported callbacks; localhost remains unsupported.
- A focused concurrent-refresh test reproduced a slow response overwriting newer
  metadata; the observed-row comparison makes it pass.
- Initial token exchange exposed Boruta's own exact redirect check. Pass the
  already validated callback through request-local Boruta context so the adapter
  accepts the native port without changing the token's exact callback binding.
- 61 focused tests pass across Identity, Gateway, Persistence and Console.
- Root format, compilation with warnings as errors, strict Credo and unused
  dependency checks pass.
- Nine tagged OAuth browser/exchange/rate-limit transaction tests pass.
- The production metadata fetch path successfully retrieves and validates the
  published `https://chatgpt.com/oauth/codex/client.json` document. No user
  credentials or tokens are involved in that check.
- Rendered the actual consent component with existing assets in headless Chrome
  at 1280×900 and 390×844. The client ID is visible, buttons remain readable,
  mobile has no horizontal overflow and the browser reports no errors.
- Ran the website's existing documentation importer against canonical docs with
  its output isolated under the ignored local verification directory.
- Full umbrella run (seed 424456): 5,223 tests, two failures in unchanged
  `STSTransferRoomTest` and `STSMCPRoomTest`. The transfer failure returned `:held`
  before resume, matching the earlier QA checkpoint's intermittent failure. The
  readiness failure returned `:not_ready` before format availability. Both test
  files pass together on the same-seed rerun: 23 tests, zero failures. No speech
  implementation or tests were changed for this OAuth feature.
- All other application suites passed, including 508 persistence and 551 console
  tests. The complete umbrella run is recorded as having two intermittent
  failures, not as a wholly green run.
- No environment files were read. Work is on `main`; the running QA release has
  not yet been updated by this checkpoint.

## QA deployment

- Implementation `26b9bd31` is pushed to `main` and merged into `qa` as
  `0cde73de`. Built the production release in the QA checkout and rebuilt its
  existing local Docker image; existing compiled assets were unchanged.
- Restarted `vxpipe.service`. The packaged migration ran successfully before
  startup. Both Vxpipe and Caddy are active and enabled, public health returns
  `ok`, HTTP redirects to HTTPS with 308, and Docker still enforces 1 GiB memory.
- Live discovery advertises CIMD and issuer-bound authorization responses.
- Removed the temporary Codex pre-registration override from local configuration.
  Codex now automatically chooses `https://chatgpt.com/oauth/codex/client.json`
  and a dynamic literal-loopback port. The live authorization endpoint accepts
  that request and returns the browser-bound consent redirect (HTTP 302).
- The user's login/consent is still required before this assistant can list or
  invoke platform MCP tools. No authenticated connection is claimed by these
  discovery/authorization checks.
- The documentation publishing workflow for `26b9bd31` passed. Runtime
  environment files were loaded privately by the existing service; their
  contents were not inspected or changed.
