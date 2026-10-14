# Call-spec primary keys

## Decision and progress

- User requested removing the separate public identifier including API references.
- Keep decimal primary keys as strings; reserve a sequence ID before validation and atomically insert spec/revision/routes. Gaps are acceptable; empty specs are not.
- Red: new persistence contract failed on UUID parsing. Green: all six CallSpecStore tests passed after implementation and test migration.
- Existing relational IDs remain. Historical execution snapshots/digests remain immutable. Deploy after draining calls and update external references.
- Updated fixtures and authoring/API/CLI assertions to use primary keys. Persistence suite: 279 tests, zero failures (two excluded integration cases).
- Verified the actual up migration against an isolated temporary schema containing an old-style spec and a referencing revision. Primary key 42, tenant 7, revision FK and JSON source survived; information_schema confirmed public_id was removed. Temporary schema was dropped afterward.
- Applied the migration to local test and development databases.
- Formatting, warning-free compilation and strict Credo passed. Root formatter does not discover child apps without their own formatter config, so formatted changed Elixir files explicitly too.
- Corrected old documentation that mandated separate UUIDs; current API remains server-assigned, POST creates and PUT only appends.
- Full umbrella run exercised 3,791 tests. See the corrections and reruns below; the initial run was not entirely green.
- Full umbrella run found three Console sample-installer failures: it still supplied catalog slugs as spec IDs. Fixed creation to allocate a primary key; reinstallation locates the immutable original name and refuses ambiguous or edited matches. Recipe catalog keys remain UI recipe keys, with the real call_spec_id returned separately. Seven focused sample tests and all 303 Console tests now pass, including concurrent install and customized-sample protection.
- The first umbrella run also had one Gateway transfer.active timeout. The affected generated transfer group passed on rerun: 20 tests, zero failures (49 excluded). No runtime/media code was changed.
- Final static gates (format, warnings-as-errors compile, strict Credo and unused dependencies) passed after the installer correction.

- Final review: tenant-scoped PK comparisons, string projections and migration preservation checked. UI checkpoint was already committed as `91192732`; this checkpoint owns the backend identity cutover.
