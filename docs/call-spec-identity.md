# Call-spec identity

Call specs use `call_specs.id`, the PostgreSQL primary key, for relations, API
references and Console routes. JSON encodes `call_spec_id` as a decimal string
(for example `"123"`), avoiding JavaScript bigint precision loss. There is no
separate public ID or editable slug. Names remain non-unique display labels.

## Allocation and authorization

The persistence adapter reserves a sequence value before compiling the first
revision. The Calls workflow inserts the spec, revision and routes atomically.
Validation failures can leave sequence gaps but cannot leave empty specs. Edits
reuse the same key. The in-memory test adapter implements the allocation port.
Every external lookup remains tenant-scoped. Numeric keys grant no permission.
Invalid or out-of-range references match no row. External authors cannot choose
creation IDs or append revisions to a missing/foreign spec.

## Migration and compatibility

Migration `20261014000400` removes `call_specs.public_id` and its uniqueness index.
Existing primary keys, revisions, calls, routes and publication pointers remain.
External API references and bookmarks must switch to the primary key. There is
no alias table or fallback resolver. Export any needed old/new ID mapping before
migration. Deploy schema and application together with traffic paused; mixed
versions are incompatible.

Historical resolved call plans and digests remain immutable execution snapshots;
the migration does not rewrite their embedded historical references. Current call
projections use the relational primary key. Drain active calls before deployment.
Rollback recreates the column with primary-key strings, not original UUIDs/slugs;
restoring original values requires a database backup.

## Alternatives rejected

- A second UUID/slug adds allocation, indexing and lookup machinery without a
  required user or API capability.
- JSON numbers risk bigint precision loss in clients.
- Inserting a spec before validation leaves empty rows on failed creation.

## Verification

The persistence contract test first failed on UUID allocation, then passed with
a direct primary-key lookup. Focused tests cover tenant isolation, revisions,
publication, routes, search and call projections. Run evidence is tracked in the
checkpoint labnotes and Console milestone.

Sample catalog keys identify recipes, not stored call specs. Installation returns
`call_spec_id` separately. Reinstallation matches the immutable first revision's
name, then verifies the current source digest before republishing; ambiguous or
edited matches are conflicts. This retains edited-sample protection without a
second stored identifier.
