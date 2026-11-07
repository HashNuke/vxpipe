# Check MCP duplicates before authentication

## Proposed checkpoint

- Existing static create finds duplicates only after its authentication/MCP probe;
  browser OAuth finds them during callback persistence. A changed listed recipe
  can fail before exposing a retained record, and DCR can register an unused client.
- Resolve a trusted canonical target before either authentication path. Extend the
  existing Console probe/preparation ports with required target resolution; both
  implementations delegate to one Console resolver. A custom URL is normalized
  without HTTP. A listed reference uses the existing bounded/coalesced directory
  cache, without contacting the MCP or authorization server. Validate an explicit
  issuer before directory access, preserving existing malformed-issuer behavior.
- Calls verifies target/reference binding, refreshes current write authority,
  checks the tenant's existing identity, and refreshes authority again even for a
  conflict result. Return only the existing connected-ID or retained-ID/generation
  proposal. No new public endpoint, record store or credential reader.
- Add repository `find_identity` using the exact existing endpoint-identity OR
  directory-identity query and deterministic internal-ID order, including revoked
  records. Read metadata without decryption. Existing transactional create remains
  the final guard against a duplicate appearing after the advisory lookup.
- For a fresh target, add explicit `check_target` / `prepare_target` continuations
  to the existing ports. Compose the existing checks with the accepted entry,
  without resolving the directory twice. Preserve the single PreflightRunner
  admission around new listed static/OAuth protocol work; calling static
  `check_saved` directly would accidentally drop its existing admission bound.
  Target resolution uses the already bounded directory cache rather than a second
  PreflightRunner admission, which would hit the same tenant's 500ms rate limit.
  Bind checked/prepared endpoint and snapshot back to the accepted target. Existing
  saved replacement/reconnect paths remain authoritative.
- Make capability absence a fixed unavailable error before network, credential or
  protocol work; do not silently fall back to the old ordering. Update repo-owned
  adapters and fixtures to the required contract. Preserve protocol error mapping.

## Verification plan

- Red-first repository lookup: tenant separation, canonical endpoint/directory
  matching, no-key reads, revoked records and competing identities choose exactly
  the same record as transactional create.
- Red-first Calls boundaries: static and browser duplicates return before protocol
  work; lost authority during target resolution/lookup suppresses metadata; missing
  adapter capability does not invoke protocol; mismatched target/protocol results
  cannot persist; a duplicate appearing after lookup still uses atomic-create guard.
- Real session/CSRF and encrypted-store endpoints: changed listed endpoint/recipe
  whose new authentication fails still finds the accepted retained identity; OAuth
  connected/revoked conflicts do not register, exchange, create attempts or perform
  MCP checks; explicit reconnect preserves accepted config and namespace.
- Existing focused suites, root gates and independent adversarial review. Existing
  retained UI consumes these unchanged proposals; no UI redesign is needed.

## Status

Required contracts were recommended by the independent retained-read review. The
preceding retained recovery and separate audio correction checkpoints passed their
full root run and were committed as `e48f84b0` and `1cceb9de`. This checkpoint has
its own implementation, evidence and review; stage exact paths only.

Sixteen new focused Calls regressions failed before implementation: both static and
OAuth paths authenticate before finding connected/revoked identities, do not bind
an accepted target, and do not refresh authority around its lookup. Tests also
require callback availability before resolution, credentialless resolver input,
tenant-bound duplicate metadata and an explicit continuation for a fresh target.
Required target resolution and continuation ports now precede authentication in
static, machine and browser OAuth creation. Lookup and atomic creation share the
same tenant-scoped deterministic query. The accepted target binds all continuation
results, while existing saved reconnect/replacement operations remain unchanged.

## Implementation and verification

- Sixteen Calls red cases now pass. Two new storage tests failed on the absent
  operation, then pass with tenant/keyless/revoked and competing-identity coverage.
  Four Console adapter tests failed on absent target callbacks, then pass with one
  directory read, preserved protocol admission and issuer validation before reads.
- The OAuth endpoint regression first returned 503 for a duplicate. It now returns
  the same bounded connected/reconnect 409 payloads as static create, before any
  preparation or attempt persistence. Existing production UI handles both paths.
- Real encrypted-store session/CSRF cases replace listing endpoint and recipe with
  a configuration that cannot authenticate, then recover connected/revoked
  identities without keys or protocol work. Two OAuth attempts started before
  either callback exercise the final create race guard: only the first saves, the
  second fails without replacing its credentials or identity, and both states
  remain single-use.
- Real-cache cancellation cases kill static/OAuth callers during the shared fetch.
  Another caller receives the completed public page; the dead connection request
  never looks up tenant identity or enters protocol work. No private cache-state
  mutation or artificial production deadline change is used.
- Boundary coverage also rejects full-snapshot recipe changes and malformed
  non-map OAuth proposals. The latter first raised BadMapError at the new target
  boundary; proposal validation now returns the existing fixed validation error.
- Broader verification exposed two fixture assumptions. Machine-acquisition
  authority tests now revoke explicitly during the probe, since authority is also
  refreshed before it. The completion deadline fixture's 75 ms budget sometimes
  expired before DNS-stage entry; the test-only budget is now 1,000 ms with a
  2,000 ms result wait, preserving held-stage and monitor/termination assertions.
  Independent review approved this narrow correction; production stays at 15 s.
  Removed one existing unused import in the exercised endpoint lane.
- Full Calls passes 356 tests; the Console MCP lane passes 83; storage passes 22.
  All five root gates pass: format, warnings-as-errors compilation, strict Credo,
  unused-dependency check and 4,984 umbrella tests with zero failures (201 excluded,
  seed 472487). Independent adversarial source and exact-index reviews report no
  remaining checkpoint findings. No frontend source or styling changed;
  authenticated browser acceptance remains a separate open gate. No source-cutover
  or speech state machine changed in this checkpoint, so Lean is not applicable.
- The next saved-admission checkpoint has a separate untracked planning note and
  unstaged red Gateway test. Those are excluded from this commit and its evidence;
  the root run had already compiled Gateway before that new test was added.

## Independent design review

The review found four contract details to include before implementation:

- OAuth controller handoff currently maps duplicate tuples to 503. Add the same
  bounded 409 payloads used by static create, with connected/revoked endpoint tests.
- Reference matching is insufficient: bind the exact accepted recipe/snapshot,
  canonical endpoint/resource and endpoint identity, compound directory identity,
  and request revision. Custom results cannot introduce directory configuration.
- Resolution input must be credentialless: pass only endpoint/listing and optional
  issuer, never credentials or initial registration tokens. Validate availability
  of resolver, continuation and repository callbacks before resolver work starts.
- State the phase bounds: directory-cache caller limit 15 seconds, loader timeout
  12 seconds, followed by the separate 15-second protocol runner deadline. A shared
  public fetch may outlive a cancelled caller; no repository/protocol continuation
  may run afterward. Test real-cache caller cancellation. This differs from the
  former single listed-operation deadline and must be recorded in durable docs.

No additional architectural blocker was found. Calls already depends on MCP, so
custom target binding can reuse StaticConfiguration.endpoint rather than adding
another URL normalization algorithm.
