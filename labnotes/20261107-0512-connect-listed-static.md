# Connect listed static MCPs

- Builds on `5b42dfca` (trusted listing discovery) and `750e47dc` (accepted snapshot
  storage). Both checkpoints passed full umbrella checks and independent review.
- Reuse the existing connection probe and CRUD operations. New listed proposals
  resolve their reference on the backend; existing listed operations use the
  accepted snapshot read from their tenant record, without directory lookup.
- Static scope is explicit anonymous, bearer, Basic and one recipe-selected API-key
  header. Ignore browser endpoint/authentication overrides; only the API-key value
  is user-owned. Persist canonical static credentials for existing runtime readers.
- Plan a separate trusted `check_saved` probe callback so the browser cannot
  present a snapshot as server authority. Calls must load/authorize/check generation
  before invoking it, and must expose only the public snapshot in responses.
- Added Console probe behavior tests before implementation. OAuth template binding,
  locked forms and reconnect proposal UI remain later T6a/T6b work.

## Implementation and focused evidence

- Console's new listed probe resolves the reference within the existing bounded
  preflight runner, then projects the accepted recipe into the existing static
  probe. A separate saved-snapshot callback avoids any browser-controlled snapshot
  masquerading as authority. Calls loads and checks that saved record first.
- Four static recipes use the existing runtime credential format. The API-key
  recipe owns its header name even when the browser sends a different name. The
  listed dispatch clause precedes custom machine OAuth dispatch, so an overridden
  authentication method cannot divert credentials into another workflow.
- Calls binds the result to the original reference and rejects mismatched entries
  before persistence. Saved replacement can reuse existing canonical credentials;
  revoked reconnect requires fresh credentials and preserves the retained ID.
- Inventory joins the compound directory/entry identity, retaining saved matches
  when upstream endpoints change without matching another directory's same slug.
- Red evidence: three Console probe failures, three Calls lifecycle failures, one
  wrong-probe-identity failure and one inventory identity failure before their
  respective fixes. Green: five Console probe tests (seed 620243), twenty Calls
  tests (seed 358123) and ten inventory tests (seed 384278).
- The real-storage/session/CSRF HTTP lifecycle test passes (seed 346893): create,
  detail, replacement, catalog refresh, disconnect and retained-ID reconnect while
  the directory is offline, plus stale generation and cross-tenant rejection.
  Its protocol/directory fixtures make no external HTTP calls. No UI change or
  real-server interoperability is claimed by this backend checkpoint.
- Independent adversarial source review found no actionable blockers across
  recipe ownership, snapshot injection, generation/state checks, outage management,
  compound identity, credentials and cancellation ownership. A dedicated canceled
  listed-create regression was suggested as optional; existing runner/lifetime
  coverage supplies that ownership contract in this checkpoint.
- Combined Console focused run: sixteen tests, zero failures. Root formatting,
  warnings-as-errors compilation, strict Credo and unused-dependency checks pass.
  Full umbrella run passes: 4,914 tests, zero failures, 201 excluded, seed 780141.
  Independent exact-index review of the fifteen staged paths is clean. All five
  root gates pass. The separate listed-form checkpoint started afterward is not
  part of this backend commit.
