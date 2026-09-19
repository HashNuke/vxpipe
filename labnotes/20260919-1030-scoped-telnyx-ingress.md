# Scoped Telnyx ingress

- Start C2 after reviewed C1 commit `4007074`. Read the parent plan and binding
  decision, existing raw-body verification, retained leg lookup and Phoenix mount.
- Design review: URL selects exactly one primary credential scope. Unsigned body
  identifiers may locate an already initialized owner only in that scope. Fresh
  application lookup follows successful raw-body authentication; compare effective
  owner, credential ID/version and application identity before dispatch. Legacy exact-ID
  bindings remain outside the new application directory.
- Red-green: the scoped application lookup was absent; its persistence test now passes.
  New HTTP tests initially failed unsupported verifier configuration. Both mounted
  routes now pass signature, scope, raw-body, unknown application, origin and key checks.
- Red-green: initialized incoming/outgoing owners were not discoverable by scoped
  provider-leg identity. They now register scoped aliases alongside legacy aliases;
  duplicates reuse the incoming owner and later callbacks can avoid storage. Failed
  multi-key registration releases keys acquired by that attempt; media-bind failure
  releases all added aliases through the existing rollback path.
- A Phoenix endpoint test with real encrypted PostgreSQL credentials verifies two
  inheriting tenants, override, wrong-key/cross-tenant rejection and deletion restoring
  platform use. No upstream network request or live Telnyx acceptance is claimed.
- Review caught a freshness regression: the new scope-level 300-second verification
  window skipped a stricter application setting. A focused test failed with 200 rather
  than 401; post-mapping verification now also enforces the selected application's
  window. Initialized calls keep their original verifier and configured window. No
  current-key or cross-scope retry follows an initialized owner's signature failure.
- Scoped webhook telemetry initially classified requests as unknown; its regression
  now passes with the bounded telephony_webhook operation and no request identifiers.
- Final focused Gateway pass: 47 tests. Root format, compile, strict Credo and unused
  dependency checks pass. The full serial umbrella suite is running before C2 commit.
- Final umbrella: 1,781 tests, zero failures, 40 excluded, seed 772211, max-cases 1.
  Gateway has 455 passing tests, Persistence 177 and Console 181. No UI changed;
  HTTP verification uses both the prefixed Gateway mount and production Phoenix mount.
  Final local review checked raw-body ordering, no cross-scope verifier selection,
  owner/ID/version comparisons, exact retained-owner dispatch, registration rollback,
  bounded telemetry, legacy ingress and test cleanup before staging the checkpoint.
- Next Console slice is split into C3a credentials/URLs and C3b applications/routes.
  Dependency review moves the common public origin and outgoing scope URL from D into
  C3a so the UI does not ship a conflicting callback location. Remaining D acceptance
  is unchanged and still open.
