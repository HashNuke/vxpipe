# Call spec drafts and publications

Status: implemented and independently reviewed on 2026-11-17. Feature acceptance passes; the combined umbrella-run limitation is recorded below.

## Runnable outcome

Operators repeatedly save one visible working draft without incrementing the published version. Publishing changed content creates the next published version. The editor and list show `v6 · Unpublished changes` or `v6 Published`; a never-published spec shows `Draft`. Unsaved browser edits remain distinct from saved unpublished changes.

## Prerequisites and design sources

- [Call spec editor](call-spec-editor.md): completed source authoring, validation and save/publish lifecycle.
- [Platform MCP endpoint](platform-mcp-endpoint.md): shared authorized product API and internal revision identities.
- [Tenant Call Specs and API-key administration](tenant-call-specs-and-api-keys.md): tenant isolation and persistence.
- [Approved preview and feedback](../20261117-1331-editor-publication-badges.md).
- [Publication architecture](../../docs/en/development/call-spec-publications.md).

## Approved contracts

- Published version numbers advance only on publication of changed content. Repeated publication of the same live content is idempotent and preserves routes, timestamps and version.
- The latest saved source is the single visible working draft. Immutable internal save revisions remain available to existing API consumers and pinned calls; they are not user-facing publication versions.
- Existing API `revision`, `latest_revision`, and `published_revision` retain their identities. Add authoritative publication metadata to shared reads/writes and list summaries.
- Saving content equal to the live source clears the saved unpublished-changes state, regardless of internal revision numbers. Unsaved edits do not count as saved changes.
- A publication transaction owns its counter, ledger, live pointer and route activation. Failed publication leaves them unchanged. Authorization remains tenant-scoped.
- Backfill only known current publications, retaining their existing number/date. Earlier publication dates were not durably retained; never invent history or renumber pinned revisions.
- Header badge is clickable and opens a reference-only modal: up to three most recent published versions with dates, a green Live badge on the current one, and one saved unpublished-changes row with its last-save date if present. No View or Continue editing buttons. Description: `Showing 3 recent published versions` (actual count for shorter histories).
- The list exposes the same published version and saved-change state, without an internal revision counter.
- Publish acts on the explicitly selected saved snapshot, including save-then-publish. Later browser edits remain unsaved. Historical source reads remain read-only.

## Tasks and acceptance

### Persistence and shared API

- [x] Add durable publication counter/history with reversible migration and truthful legacy backfill.
- [x] Atomically allocate versions and record publication dates; make unchanged publication a no-op.
- [x] Return bounded history, live version/revision, saved-change state and draft-save timestamp through shared API.
- [x] Project live version and source-based saved-change state into paginated lists.
- [x] Verify repeated saves, changed/unchanged publication, history limit, source reversion, tenant isolation, failed-publication rollback and immutable historical sources/routes.

### Product UI

- [x] Implement shared production publication badge and reference-only history dialog.
- [x] Wire reads/save/publish responses through editor state without leaking internal save IDs in badges or success messages.
- [x] Update call specs list status and remove redundant internal version column.
- [x] Use production components in Storybook; keep approved states and interaction examples.
- [x] Verify draft-only, published, saved changes, unsaved edits, repeated saves, publication, no-op publication and reload behavior.
- [x] Inspect real app and Storybook on desktop/mobile with dark/light themes.

### Documentation and completion

- [x] Update user/API documentation and checkpoint labnotes.
- [x] Run required root checks and focused suites; record combined-run limitations and verify remaining apps separately.
- [x] Request and resolve independent Astra xhigh implementation review.
- [x] Synchronize milestone/index with feature acceptance and recorded verification limitations.

## Design review (separate from implementation)

- [x] Local dependency/contract review: this supersedes the old editor milestone's visible save-revision model, not its immutable call identity contract.
- [x] Independent Astra xhigh design and implementation review; findings and resolution recorded in checkpoint labnotes.

## Evidence

- Focused persistence: 11 tests pass, including actual migration up/down, concurrent publication and nested no-op transactions. Shared gateway HTTP/MCP/JSON tests: 17 pass.
- Frontend editor/list/API/route pass: 449 tests; final header/state pass: 30 tests. Independent reviewer: 40 focused tests pass.
- TypeScript, asset build, format, warnings-as-errors compile, strict Credo and unused-dependency check pass. ESLint has zero errors and one pre-existing SetupDialog hook warning.
- Real Chromium app: draft-only, multiple saves retaining public v1, changed publication to v2, repeated publication retaining v2/history, reload, list metadata and reference-only modal verified. Desktop 1440×1000 and mobile 390×844 inspected; light/dark production components inspected in app/Storybook. Reviewer independently verified 700px list columns and keyboard focus restoration.
- Root run: one speech-to-speech readiness-budget failure passes on isolated seed-0 rerun; the VM then exited with :terminating after 880 gateway tests passed. Remaining apps run separately: artifacts 20 pass, persistence 546 pass (68 excluded); Console 573 pass (122 excluded). No claim of a clean single-process umbrella run.
- Astra xhigh review found no remaining blockers after fixes for nested no-op transaction rollback, modal focus restoration, narrow list width and explicit concurrency success assertions.
