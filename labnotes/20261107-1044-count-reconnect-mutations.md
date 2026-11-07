# Count reconnect mutation requests

The full frontend busy-feedback verification has one failure among 1,065 tests:
`McpConflict` expects one POST, but its debounced background discovery also uses
POST and produces a second request. This does not prove a second connection
mutation. The fixture explicitly handles discovery separately from conflicts.

Make the timing deterministic by observing the actual discovery request before
checking mutation count. Both relevant original assertions then fail (two failures,
ten passes), including the metadata-read retry case that had not failed in the
full run. Exclude only the exact discovery route from the POST mutation count;
continue counting every other POST, and preserve the explicit review, current
generation, credential-clearing and no-resubmission assertions. No runtime change.

The corrected focused file passes all 12 cases. Astra independently reproduced
both deterministic red assertions in a temporary copy (two failures/ten passes),
then verified the current file passes all 12. The review confirms every other POST
remains counted and no consent, generation, credential or retry assertion was
weakened. The full frontend rerun is in progress.

Final frontend verification passes all 1,065 tests across 139 files, TypeScript
and ESLint. Independent review/red-green proof and relevant rendered acceptance
are complete. The separately tracked full backend root gate remains pending.
