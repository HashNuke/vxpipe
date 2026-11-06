# Review MCP OAuth

- Independent source review identified four protocol gaps before staging: raw token
  responses lose required token_type presence through a dependency default; token
  validation permits values the Bearer transport rejects; CIMD ignores explicitly
  incompatible client-auth metadata; and managed preparation does not validate
  protected token-endpoint query fields before registration.
- DCR additionally requests the global document's refresh grant even from an
  authorization-code-only issuer, sends no selected resource/challenge scopes, and
  does not inspect explicit returned grant/response-type changes. Fix requirements
  are recorded in the milestone; no fixes or red tests have run for this checkpoint.
- Inspected protocol ownership is coherent: PKCE, exact issuer callback checking,
  resource binding, active-credential exclusion, reserved parameters, signing key/
  algorithm matching and opaque structs. Source review found no confirmed I/O
  cancellation leak. Composed caller-owned registration/token deadlines remain an
  orchestration acceptance gate.
- Standards checked: approved MCP 2025-11-25 authorization profile, RFC 6750 bearer
  syntax and RFC 7591 client metadata/registration response. Registration responses
  may replace requested metadata, so the client must decide whether returned
  registration is usable. DCR scope is optional in the RFC; passing selected scopes
  here is an interoperability decision, not a claim that every DCR request requires
  a scope field. See https://www.rfc-editor.org/rfc/rfc7591.html#section-3.2.1 and
  https://www.rfc-editor.org/rfc/rfc6750.html#section-2.1.
- Next coherent scope: nine MCP protocol modules plus ten focused test files,
  including token assertions. Preparation and Own-client preparation belong
  together because they dispatch/construct each other's types. Runtime credential
  injection and Calls/Console OAuth orchestration remain separate checkpoints.
- Eight focused failures reproduced the reviewed gaps. Forty focused tests now
  pass. Token grants use ExMCP SecureHTTP directly so raw token_type presence is
  retained; access tokens reuse the project's Bearer transport validator and scope
  values obey OAuth syntax. Basic credentials remain form-encoded before Base64;
  private-key assertions and fixed PKCE/resource fields retain their existing path.
- CIMD requires advertised public-client authentication. An omitted methods field
  uses RFC 8414's client_secret_basic default, so it cannot imply public support.
  Preflight falls back to usable DCR or Own client consistently. Managed preparation
  validates protected token endpoint query fields before registration.
- DCR requests only the installation's grants advertised by the issuer (defaulting
  to authorization code), includes selected challenge/resource scopes, and omits
  empty scope. Explicit returned grant/response metadata must still allow code;
  returned scope must be syntactically valid and include the selected scope set.
  Missing grant/response fields use RFC 7591 defaults; missing scope is tolerated
  for compatibility, without expanding the actual authorization request. This is
  a compatibility decision, not a claim that incomplete registration responses
  conform to the RFC's metadata echo requirement.
- Static management committed independently as `e502cafb` after a clean staged
  review and 4,840-test root pass. Protocol fixes remain a separate checkpoint.
- Second review found unsupported token-auth methods still producing a browser
  suggestion, and DCR reuse ignoring changed scopes. Both regressions failed, then
  passed after capability selection required an implemented method and reuse
  required saved scopes covering the fresh selection. MCP now passes 163 tests.
- Calls reconnect's scope projection also failed a focused assertion; its fix and
  fixture remain in the separate orchestration checkpoint. Console's composed CIMD
  fixture omitted public-auth support and failed under the corrected policy; it now
  explicitly advertises none. These are working-tree compatibility updates, not
  dependencies of the protocol checkpoint.
- Source re-review is clean. Format, warnings-as-errors compilation, strict Credo
  and unused-dependency checks pass. Exact staged review and downstream composed
  tests follow before commit.
- Downstream Calls 310 and Console 481 tests pass after the projection/fixture
  updates. All ten tagged local HTTP/PostgreSQL OAuth cases pass, covering managed
  registration, Own-client code/machine grants, reconnect and refresh. This evidence
  exercises the working-tree orchestration; it does not claim that orchestration is
  part of this independently staged protocol slice. Logs: `vxpipe-oauth-mcp-suite.log`,
  `vxpipe-oauth-calls-suite.log`, `vxpipe-oauth-console-suite.log` and
  `vxpipe-oauth-protocol-integration.log`.
- Exact-index adversarial review of all 25 staged files is clean against `e502cafb`.
  Required helpers are committed and the dependency sources match the pinned
  version. Documentation and tests are included with the protocol implementation.
