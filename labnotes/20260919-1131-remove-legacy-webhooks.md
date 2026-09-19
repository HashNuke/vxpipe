# Remove legacy webhooks

The user explicitly removed the legacy Telnyx webhook compatibility requirement.
D1 follows C3a and precedes C3b; application UI and final acceptance remain open.

- Red: 16 focused Gateway checks, two expected failures. A correctly signed old
  ingress-key URL dispatched, and an unscoped binding constructed a live client.
- Removed the old HTTP route/raw-body recognition, legacy Telnyx verifier selection,
  ingress alias registration and callback fallback. Twilio has an explicit separate
  selector; Telnyx retains scoped application/leg lookup and unchanged media paths.
- Gateway rejects unscoped Telnyx snapshots before client construction. No stored
  credentials or application records are deleted or silently reinterpreted.
- Updated fake repositories, protocol fixtures and encoded callback expectations to
  the primary scoped credential contract. Fifty focused tests pass. The incoming
  lifecycle group passes an initial run plus 50 repeats under the updated fixtures.
- The tagged encrypted PostgreSQL two-tenant/two-carrier signature test passes with
  distinct scoped Telnyx applications. The Telnyx call harness plus Twilio webhook
  and Telnyx media group passes 22 tests. Root format, warnings-as-errors compile,
  strict Credo and unused dependency checks pass.
- The first umbrella run found a Twilio transfer-recovery harness failure: missing
  source recovery speech after a cue-time disconnect. Investigate before acceptance;
  focused webhook success alone does not establish that the full suite is green.

## Final review and acceptance

- Review found an incomplete synthetic speech acknowledgement in the recovery
  fixture. Its separate checkpoint completes that earlier provider request while
  retaining the exact recovery, media and continued-conversation assertions. Both
  carrier harnesses pass 26 tests in six combined runs.
- Final serial umbrella (seed 772211, max-cases 1): 1,788 tests, zero failures,
  40 excluded. Root format, warnings-as-errors compile, strict Credo and unused
  dependency checks pass. The signed two-tenant/two-carrier PostgreSQL integration
  check also passes. Logs are under `tmp/scoped-services-checks/d1-*`.
- Reviewed all routing, callback generation, retained-owner selection and fixture
  changes. No production old-events URL remains; the only code occurrences are
  rejection tests. New live Telnyx clients fail before dialing an unscoped binding.
  Media URLs/tokens and Twilio behavior are preserved; no database records are deleted.
- Updated the main plan, binding decision, architecture, registration guide and
  milestone index. D1 is complete; C3b application/number setup and D2 final acceptance
  remain open. This checkpoint has no UI change or live-provider claim.
