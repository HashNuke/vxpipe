# Review MCP storage

- Scope: connection repository port/private resolved value, tenant connection
  schema/migration/store and focused tests. Cipher foundation is committed.
  OAuth attempt/grant lifecycle and public authorization are separate checkpoints.
- Independent source review identified a later-checkpoint dependency in the
  catalog-preservation test: it calls OAuthGrantStore. Keep foundation coverage
  local to ConnectionStore and retain grant-claim integration with its own store.
- Review also found a SQL CHECK three-valued-logic gap: connected rows with a key
  ID but NULL ciphertext satisfy the constraint as UNKNOWN. Add an explicit
  non-NULL condition and a database regression. This is an integrity gap, not a
  demonstrated repository authorization bypass. Fixes are pending the current
  umbrella run so its Persistence inputs are not changed mid-run.
- Parent source inspection found a reconnect-flow question: revoked rows retain
  unique endpoint/directory identities, while get/resolve/list hide them and the
  public update path resolves first. Verify disconnect followed by a fresh connect
  and define how explicit reconnection preserves durable identity/generation.
- Reviewer confirmed that the store already permits explicit replacement of a
  revoked row with fresh secrets at the observed generation. Add that foundation
  regression; later Calls must expose authorized tombstone lookup/reconnect without
  resolving old secrets. Do not change uniqueness to active-only/new IDs silently.
- Additional source finding: stopped/missing Repo and checkout exits escape the
  store's narrow SQL-error rescue. Mirror the existing provider-store unavailable
  mapping and isolated outage/recovery test pattern while reraising programmer
  errors. Fixes remain pending.
- Red run: 13 focused storage tests produced exactly two failures: SQL accepted a
  NULL ciphertext update, and the stopped named Repo raised a registry RuntimeError.
  Restoration at the revoked generation already passed and required no runtime change.
- Added explicit non-NULL enforcement to the initial schema and a forward repair
  migration for already-applied preview checkouts. Applied the forward migration
  to the isolated test database without dropping records. The repair validates
  existing rows and fails if they violate the invariant rather than silently
  deleting or reviving them.
- Mirrored the existing provider store's narrow dependency exception/checkout-exit
  mapping. KeyError/programmer faults still propagate. Removed the OAuthGrantStore
  dependency from foundation tests; grant/catalog integration remains covered in
  the later grant-store suite.
- All 24 focused tests pass: 15 connection-store cases, seven grant-store cases
  including the relocated integration, and two tagged distinct-PostgreSQL-client
  races. Added wrong-tenant replacement preservation and full rollback when a
  later re-encryption row is unreadable. Multiple clients in one BEAM do not
  establish separate-node acceptance. Full Persistence/static checks and exact
  independent checkpoint re-review follow.
- Full Persistence suite: 473 tests, zero failures. Format, warnings-as-errors
  compile, strict Credo and unused-dependency checks pass. The correction's down
  step retains the invariant now defined by the initial migration, rather than
  weakening a fresh installation on rollback. A format check covers that final
  migration-only refinement; the applied up definition is unchanged.
- Exact 11-file staged adversarial re-review is clean. Public reconnect,
  separate-node acceptance and later OAuth lifecycle remain open milestone gates.
