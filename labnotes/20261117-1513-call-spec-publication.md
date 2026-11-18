# Call spec drafts and publications

- User requested milestone plus production backend/frontend implementation and an independent Astra xhigh review.
- Preserved existing preview work and header-slot regression test. User authorized committing and deploying this checkpoint on 2026-11-18.
- Design: separate publication numbers from immutable source save IDs. Existing internal IDs pin calls and authorize MCP preparation; mutating these would weaken those contracts. Source comparison owns saved unpublished-change state.
- Initial Astra review agrees with separate counters and recommends allocating the ledger and detecting idempotent publication inside the existing tenant publication transaction, preserving Telnyx/tenant lock order. Retain requested revision in no-op publish responses so editor request identity remains valid.
- Legacy migration can only backfill current known publication; earlier actual dates were overwritten. Preserve existing published number and historical call IDs rather than inventing history.

## Implementation and review checkpoints

- Added separate publication counter/ledger, source-based saved-change projection, bounded metadata history, migration of only known live publication, and additive HTTP/MCP/list metadata.
- Red tests established missing publication metadata and behavior before implementation. Persistence checks cover repeated saves, source reversion, no-op publication, route/counter rollback, tenant isolation, immutable snapshots, latest-three history, concurrent publishes and legacy migration up/down.
- Review found that using an error/rollback for unchanged publication poisoned outer provider-credential transactions. Reproduced with a focused failing nested transaction test, then replaced the rollback with a successful conditional Ecto.Multi. Nested Multi callbacks close over the selected rows.
- Shared production badge/dialog now drive both app and preview. Editor saves keep public versions stable; unsaved edits and request identity survive pending writes. List no longer displays internal save IDs.
- Review found missing modal focus restoration; placing the badge in DialogTrigger fixed Escape returning focus. The focused test and independent Chrome check pass.
- Widened the list table minimum to 760px and gave State 34% of its width. Independent 700px Chrome inspection confirmed local horizontal overflow and no overlap with Updated.
- Strengthened duplicate-publication concurrency checks to assert both task successes instead of silently filtering failed task results.
- Final Astra xhigh review: no remaining implementation blockers; 40 focused frontend tests passed and diff whitespace clean.

## Verification

- Focused persistence final: 11 tests, zero failures. Includes actual migration runner up/down, source snapshots and real concurrent transactions.
- Gateway HTTP/MCP/shared JSON: 17 tests pass. Frontend editor/list/API/route: 449 pass; final header/state: 30 pass.
- TypeScript and asset build pass. ESLint: zero errors, existing SetupDialog useEffect dependency warning. Root format, warnings-as-errors compile, strict Credo and unused-dependency checks pass.
- Real app browser fixture used a synthetic account, tenant and credentials, with no provider requests. Initial Google model fixture was not eligible for the current agent protocol; changed it to the verified OpenAI model and repeated save/publish successfully.
- The existing port 4001 server was an older release, so started this checkout locally on port 4101 to verify current code. Did not restart the unrelated existing server.
- Real editor confirmed saved revisions 4 and 5 both show public v1 with unpublished changes; publishing revision 5 creates v2 and repeating publish leaves the same v2 and publication timestamp/history. Reload and list agree.
- Chromium desktop/mobile checks covered the modal, short description, last-save date, latest publications, green Live and no action buttons. Light Storybook and dark app rendering inspected. Storybook remains bound to 0.0.0.0:6007.
- Removed the isolated browser account/tenant/credentials after verification.
- Root suite completed identity, MCP, providers, agent runtime, call engine, calls and gateway. STSTranscriptModesTest readiness-budget failure at line 474 passed on isolated same-seed rerun. After gateway's 880 passing tests the VM exited with :terminating before remaining apps; the combined root run is not green. No call-engine sources were changed.
- Ran remaining artifacts/persistence/Console suites separately: artifacts 20 pass. Existing sample-installation assertion expected identical source to replace the live revision; updated it to retain requested revision 2 but live/public version 1. Focused sample tests (11) and full persistence (546, 68 excluded) pass.
- Existing Console HTTP/MCP exact-shape assertions omitted the new additive publication field. Updated them to require read metadata equality and publication version 1/live revision 1/saved changes true, plus parity with the subsequent historical HTTP read. Focused endpoint file: 9 pass. Independent reviewer confirmed these test contract updates.
- Console full-suite final rerun: 573 tests pass, 122 excluded. Final format and strict Credo pass. This work does not claim a clean single-process umbrella run; the readiness timing failure and VM termination remain recorded verification limitations.

## Release preparation — 2026-11-18

- Confirmed changes were still uncommitted and absent from the running systemd-managed container. Release uses the existing Docker/systemd path, with packaged migrations before startup.
- Deployment will build production assets and the named release from the committed checkpoint, retain the previous image for recovery, and verify service health, migration state and deployed assets.
