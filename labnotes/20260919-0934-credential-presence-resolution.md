# Credential presence resolution

- User clarification supersedes the earlier explicit inherit/override/disabled policy:
  provider credentials exist at a scope or do not. Tenant presence wins; absence
  inherits platform; absence at both scopes is unavailable. No disabling control.
- Remove the independent policy table/workflow and dormant-credential interpretation.
  Restoring platform use deletes the tenant credential; re-adding it creates a new
  identity, so already prepared readers cannot silently rebind. Existing but unusable
  tenant records still fail closed. API-key revocation is a separate existing feature.
- New red tests cover a persisted tenant credential with no policy record and exact
  scoped deletion followed by inheritance/no-credential resolution. Implementation
  followed these red tests. Carrier C1 work is deferred until this correction lands.
- Red evidence: presence tests initially failed tenant selection and missing deletion;
  directory test then failed because it still chose platform. Operator deletion failed
  undefined; HTTP deletion failed 404; UI tests rejected policy-free metadata. Core,
  directory and authority tests are now green. The complete frontend suite passes
  181 tests after removing policy/disable controls.
- Directory payload drops policy and dormant tenant ID fields. Both scoped DELETE
  endpoints require the existing operator session and CSRF. Deletion holds owner/row
  locks and reports referenced legacy telephony credentials as in use.
- Migration preserves all credential rows, including previously dormant records.
  Presence makes these effective; remove them explicitly to inherit. Down recreates
  override policies for every tenant row; retired disable state is not reconstructed.
- Initial broader checks caught test fixture mistakes (wrong named Telnyx reference,
  ciphertext too short for database check, and unconsumed fake delete messages).
  Corrected the fixtures; no product workaround was required.
- Focused final evidence: Calls authority 3/3; persistence and real transaction group
  16/16 (integration lane explicitly included); Console endpoints/samples 17/17.
  TypeScript, ESLint, assets build and all four root static gates pass.
- Disposable migration exercise: seeded both scopes plus an old disabled tenant policy;
  upgrade and fresh VM select the existing tenant credential with identical IDs and
  ciphertext. Down seeds override policies; re-upgrade preserves both encrypted rows.
- Headless Chrome at 1440x1000 and 390x844: platform create, inherited read-only details,
  tenant override, removal back to inheritance, platform removal, visible 503 failure
  and retry. Screenshots inspected. Restart retains absence at both scopes (no hidden
  tenant row returns). Synthetic validator, real encrypted PostgreSQL/operator session;
  no live provider requests. Owned browser/server/database/auth-state file cleaned up.
- Local pre-commit review covered exact ownership, secret-safe directory projection,
  locks, legacy telephony FK errors, deletion identity, recovery and migration rollback.
  Removed unrelated formatter churn from OnboardingPage.
  Final umbrella run is in progress, including the previously failing native handoffs.
- Review then found malformed UUID deletion raised Ecto.Query.CastError. Added the
  smallest regression and observed the exception, then added storage-boundary UUID
  validation and HTTP 422 coverage. Stopped the in-progress umbrella run before
  completion so the final run can use the corrected source consistently.
- Final malformed-ID regression passes (3 presence tests); the corrected source passes
  format, warnings-as-errors compile, strict Credo and unused-dependency checks.
  Full root `mix test --max-cases 1 --seed 772211` passes **1,763 tests, 0 failures,
  40 excluded**: MCP 37, agent 95, engine 700, Calls 115, Gateway 445, artifacts 20,
  persistence 171 and Console 180. Previously failing native handoffs passed unchanged;
  no cause or native fix is inferred. B2/B3 umbrella acceptance can now close.
- Final staged review includes the malformed-ID fix, keeps legacy telephony deletion
  protected and contains no secret/runtime artifacts. Presence checkpoint is ready
  to commit; scoped Telnyx design work remains a separate next checkpoint.
