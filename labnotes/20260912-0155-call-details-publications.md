# Call-details publications

## Goal

Implement milestone M21 as an outside-room workflow that projects permitted persisted call facts
into versioned immutable JSON objects. Keep projection, reporting-window policy, persistence, object
storage, scheduling, and operator retrieval as separate responsibilities.

## 2026-09-12 — checkpoint A started

- Verified the milestone and architecture contracts before implementation. The first checkpoint is
  intentionally pure: component readiness, the configurable reporting-window decision, canonical
  source projection, and immutable snapshot bytes/filename/checksum. Persistence and object-store
  orchestration remain later checkpoints.
- Component states are explicit. `pending` is unsettled; `failed` and `missing` are settled but make
  a publication incomplete. `prohibited`, `unconfigured`, and `not_produced` are intentional settled
  absences and therefore do not masquerade as missing data.
- The caller supplies both the call end timestamp and assessment timestamp. This makes the 60-second
  rule deterministic and testable without sleeping or retaining a room process.
- Snapshot JSON uses a small canonical encoder that delegates scalar escaping/encoding to Elixir's
  `JSON` implementation while sorting object keys. This gives retry-safe byte content and checksums
  without adding a dependency or relying on unspecified map construction order.

### Red evidence

`cd apps/vxpipe_calls && mix test test/vxpipe/calls/call_details_publication_test.exs` failed at
compile time because `Vxpipe.Calls.PublicationDecision` did not exist. This was the expected failure
for the new externally observable publication contract.

A boundary refinement then failed in two expected ways: an assessment exactly at `ended_at` was
rejected, and a non-UTC record timestamp was accepted. The reporting window now permits equality,
while snapshot construction rejects record timestamps with a nonzero UTC or standard offset.

A final boundary test supplied a PID inside component details and exposed an uncaught
`JSON.Encoder` protocol error. Component construction now converts that failure into
`{:error, :invalid_component}` rather than crashing its caller.

### Green evidence

- `cd apps/vxpipe_calls && mix test test/vxpipe/calls/call_details_publication_test.exs` — 6 tests,
  0 failures.
- `cd apps/vxpipe_calls && mix test` — 62 tests, 0 failures.
- Root `mix format --check-formatted`, `mix compile --warnings-as-errors`, and
  `mix deps.unlock --check-unused` passed.
- Root `mix credo --strict` checked 718 source files with no issues.
- Root `VXPIPE_TEST_DATABASE_URL=postgres://postgres:postgres@127.0.0.1:55433/vxpipe_test mix
  test` passed the complete umbrella suite (910 tests across all children, integration-tagged tests
  excluded by their existing default policy).
- The six production modules remain focused: component state, decision data, reporting-window
  policy, permitted source data, canonical JSON, and immutable snapshot construction. The largest
  is 107 lines; persistence, upload, worker lifecycle, and HTTP concerns are absent.

## 2026-09-12 — checkpoint B

### Decisions

- Persist the exact canonical JSON bytes while a revision is pending. This gives object-upload
  retries durable content and prevents storage adapters from re-encoding or silently changing a
  revision.
- Use two independent per-call unique keys: the schema-aware source digest for same-source retry,
  and the timestamp-derived filename for collision detection. A retry may propose a fresh ID and
  timestamp, but the repository returns the first persisted revision for that source.
- Advance the latest pointer only after a protected object receipt is stored. A reserved row is not
  yet a readable object. The call row lock serializes pointer decisions, and record timestamps—not
  upload completion time—prevent a late older upload from regressing the head.
- Store operational `pending`/`published` state beside immutable snapshot columns. Publishing may
  add the protected object key/reference and publication timestamp; it cannot rewrite identity,
  source, contents, filename, or hashes.
- Object receipts accept relative protected keys and limited server-side metadata only. URL-like,
  query-bearing, or fragment-bearing keys are rejected so bearer URLs cannot become durable
  references or inspection output.
- A green refactor extracted persistence record encoding and latest-pointer policy from the Ecto
  adapter. The adapter is 146 lines; its focused collaborators are 44 and 28 lines.

### Red evidence

- The initial database tests failed because `reserve_call_details/4`,
  `mark_call_details_published/5`, and `CallDetailsObject` did not exist.
- A receipt-boundary refinement expected `:publication_not_found` and exposed that a missing
  publication was incorrectly reported as `:call_not_found`.
- A protected-reference test demonstrated that an HTTPS bearer URL was initially accepted as an
  object key.

### Green evidence

- `cd apps/vxpipe_calls && mix test` — 63 tests, 0 failures.
- `cd apps/vxpipe_persistence && VXPIPE_TEST_DATABASE_URL=postgres://postgres:postgres@127.0.0.1:55433/vxpipe_test mix test`
  — 39 tests, 0 failures.
- The persistence tests cover same-source identity/byte reuse, corrected-source revision creation,
  concurrent timestamp collision, nonregressing latest selection, idempotent and conflicting
  receipts, non-terminal and cross-tenant rejection, and call-owned cascading deletion.
- Root formatting, warnings-as-errors compilation, and unused-dependency checks passed. Strict
  Credo checked 726 source files with no issues. The complete umbrella suite passed 915 tests with
  its existing integration-tag exclusions.

## 2026-09-12 — checkpoint C1

### Decisions

- Use a focused immutable-document object-store boundary rather than forcing JSON through the
  PCM/multipart recording pipeline. The document adapter and recording pipeline share the S3
  client ecosystem but have different lifecycle and buffering concerns.
- A create carries `If-None-Match: *` and checksum metadata. If the key already exists, read its
  metadata and accept it only when the SHA-256 matches. This allows the object-success/DB-failure
  retry path without permitting a different publication to clobber an object.
- Generate the object key under an encoded tenant/call prefix and a `details/` segment. Expose only
  object key and ETag through `CallDetailsObject`; provider locations and signed URLs are discarded.
- Keep the generic document, object-store behavior, S3 document client, ExAws adapter, S3 policy,
  and call-details path adapter in separate cohesive modules.

### Red evidence

The four focused tests failed because `Document`, `S3DocumentStore`, `S3DocumentClient`, and
`CallDetailsWriter` did not exist. The initial test compile also caught an invalid dynamic value in
an assertion pattern before the intended red run; binding the checksum corrected the test itself.

### Green evidence

`cd apps/vxpipe_artifacts && mix test test/vxpipe/artifacts/s3_document_store_test.exs
test/vxpipe/artifacts/call_details_writer_test.exs` — 4 tests, 0 failures. Tests cover first write,
matching retry, content collision, unavailable storage, call-owned paths, exact bytes, and protected
receipts.

The full Artifacts suite passed 14 tests with one external integration test excluded. Root
formatting, warnings-as-errors compilation, unused-dependency checks, and strict Credo over 733
source files passed. The first umbrella run exposed a pre-existing timing failure in the Twilio
audio-ingress test while every changed child was green; its two focused tests passed immediately,
and a second complete umbrella run passed all 919 tests with the existing integration exclusions.

## 2026-09-12 — checkpoint C2a

### Decisions

- Calls now starts a dedicated publication supervision tree containing a unique registry, a task
  supervisor for bounded attempts, and a dynamic supervisor for short-lived delivery workers. No
  room process owns or waits for this work.
- A worker is unique by tenant, call, and source digest. A simultaneous duplicate receives the
  existing worker PID rather than starting a second object write.
- Each attempt runs reserve, artifact write, then receipt commit. A persisted published revision
  skips the artifact writer, making a later submission harmless. A failed object write leaves the
  already reserved database row pending.
- Attempt timeouts and retry counts are explicit application settings and may be overridden at the
  call boundary for focused tests or an embedding host. Exhaustion reports an internal unavailable
  outcome and stops normally; it never changes the pending row to published.
- The worker modules are separated by responsibility: validated job configuration, one delivery
  attempt, retry/lifecycle state, worker lifecycle, worker admission, and supervision. The largest
  production module is 119 lines.
- This checkpoint does not claim node-restart recovery. The persistence adapter still needs a
  bounded pending-row query and a post-Repo recovery process that resubmits those durable records.

### Red evidence

The first focused worker test failed with `UndefinedFunctionError` because
`Vxpipe.Calls.publish_call_details/4` and its supervision path did not exist. The first compilation
after implementation also rejected a project typespec named `port/0`, because Elixir reserves that
built-in type name; renaming the type to `adapter/0` fixed the project code without weakening the
contract. A fixture assertion then exposed that an `Agent` callback reported its own PID rather
than the actual publication-attempt caller; the fixture now captures and reports the calling task.

### Green evidence

- `cd apps/vxpipe_calls && mix test test/vxpipe/calls/publication_worker_test.exs` — 4 tests,
  0 failures.
- The tests cover asynchronous successful delivery, a later already-published submission with no
  second write, simultaneous active-job coalescing, a two-attempt storage failure that retains a
  pending revision, and forceful termination of a blocked attempt at its deadline.
- `cd apps/vxpipe_calls && mix test` — 67 tests, 0 failures.
- Root formatting, warnings-as-errors compilation, unused-dependency checks, and strict Credo over
  740 source files passed. The complete database-backed umbrella run then exited successfully with
  923 tests across all children and the existing external integration exclusions.

## 2026-09-12 — checkpoint C2b

### Decisions

- Extend the publication repository port with a bounded oldest-first pending query that returns
  public tenant/call ownership alongside each exact persisted revision. Recovery does not rebuild a
  snapshot from whichever source data happens to exist later.
- A publication job may originate from a new snapshot or an already-reserved revision. Both share
  the same tenant/call/source-digest worker key. The latter skips reservation and therefore safely
  handles process or node restart without creating a second record.
- A periodic Calls-owned recovery child scans and resubmits pending revisions. Repository failure is
  an observable failed scan, not a process terminal condition; later scans can recover.
- Persistence composes this child after its Repo only when an embedding host enables it and supplies
  an artifact writer through OTP application settings. Persistence injects
  `CallDetailsPublicationStore` and its Repo rather than accepting a second repository setting.
- Pending query/decode logic lives in `CallDetailsPublicationPending`, leaving the main Ecto adapter
  focused on transactional reservation and receipt commits.

### Red evidence

- The PostgreSQL test failed with `UndefinedFunctionError` for
  `Vxpipe.Calls.list_pending_call_details/2` before the repository port/query existed.
- The recovery test failed because `Vxpipe.Calls.PublicationRecovery` did not exist.
- The OTP composition tests failed because
  `Vxpipe.Persistence.PublicationRecoveryConfiguration.children/1` did not exist.

### Green evidence

- The PostgreSQL test now proves a bounded query returns only pending revisions, oldest first, with
  their public tenant and call identifiers.
- The Calls recovery tests prove an exact pending revision is uploaded and committed without a
  second reservation, and that a database-unavailable scan leaves the recovery process available
  for a successful later scan.
- The persistence configuration tests prove recovery is opt-in, injects the owning repository, and
  rejects an enabled configuration without a valid artifact writer.
- `cd apps/vxpipe_calls && mix test` — 69 tests, 0 failures.
- `cd apps/vxpipe_persistence && VXPIPE_TEST_DATABASE_URL=postgres://postgres:postgres@127.0.0.1:55433/vxpipe_test mix test`
  — 43 tests, 0 failures.
- Root formatting, warnings-as-errors compilation, unused-dependency checks, and strict Credo over
  744 source files passed. The complete database-backed umbrella run exited successfully with 929
  tests across all children and the existing external integration exclusions.

## 2026-09-12 — checkpoint C3a

### Decisions

- Introduce a source-read port that returns one `CallDetailsAssessment`: exact persisted
  `ended_at`, an already-permitted `CallDetailsSource`, and explicit component states. Calls remains
  independent of Ecto table/query details.
- Reject source results whose embedded tenant or call identity differs from the requested scope.
- Keep assessment synchronous and pure with respect to waiting. Before the reporting deadline it
  returns a `PublicationDecision` instead of sleeping; at or after the deadline it constructs and
  submits an immutable snapshot through the existing worker boundary.
- Use the supplied assessment time as the new publication record timestamp. A changed late source
  therefore gets a distinct digest and filename; an unchanged source remains deduplicated by the
  persistence contract already implemented.
- Separate assessment data, source behavior, configured source lookup, and orchestration into four
  cohesive modules. They are 30, 17, 35, and 88 lines respectively.

### Red evidence

The three focused tests failed because `CallDetailsAssessment`, `PublicationSource`, and
`Vxpipe.Calls.assess_call_details/4` did not exist. The test support compiler also reported the
missing behavior and callback before implementation.

### Green evidence

- `cd apps/vxpipe_calls && mix test test/vxpipe/calls/call_details_finalization_test.exs` — 3 tests,
  0 failures.
- The tests prove an unsettled pre-deadline component performs no reservation, the same component
  publishes as incomplete exactly at 60 seconds, and changed late permitted facts produce a second
  immutable source revision.
- `cd apps/vxpipe_calls && mix test` — 72 tests, 0 failures.
- Root formatting, warnings-as-errors compilation, unused-dependency checks, and strict Credo over
  748 source files passed. The complete database-backed umbrella run exited successfully with 932
  tests across all children and the existing external integration exclusions.

## 2026-09-12 — checkpoint C3b

### Decisions

- Start one short-lived finalizer per tenant/call under a dedicated Calls-owned dynamic supervisor.
  Registration coalesces simultaneous requests, while the existing delivery supervisor continues
  to own immutable snapshot writes independently.
- Assess immediately after start. If persisted components are unsettled before the reporting
  deadline, schedule the next assessment for the smaller of the configured polling interval and
  remaining reporting-window time. The room is neither retained nor consulted.
- Keep wall-clock and timer operations behind separate behaviors. Production uses UTC system time
  and `Process.send_after/3`; tests advance an Agent-backed clock and deliver the recorded timer
  token directly without sleeping.
- Treat source failure as retryable finalization unavailability. The finalizer reports the reason
  internally and polls again; it does not fabricate a snapshot, change `ended_at`, or report the
  call as published.
- Stop the finalizer normally once it hands a publishable snapshot to the existing delivery worker.
  Any reserved-but-undelivered revision remains the responsibility of durable pending-publication
  recovery rather than keeping this assessment process alive.
- Keep configuration validation, finalizer state, clock, timer, admission, process lifecycle, and
  supervision in separate cohesive modules. The largest new production module is 116 lines.

### Red evidence

The two focused tests first failed because `PublicationFinalizers`, `PublicationClock`, and
`PublicationTimer` did not exist. Before production behavior could be evaluated, the initial test
harness also exposed two fixture defects: a fake source returned a bare assessment instead of the
source-port tuple, and use of the application-global dynamic supervisor could leak a retrying child
between failed tests. The fixtures now return the exact port contract and give every test its own
supervised finalizer tree.

### Green evidence

- `cd apps/vxpipe_calls && mix test test/vxpipe/calls/publication_finalizer_test.exs` — 2 tests,
  0 failures.
- `cd apps/vxpipe_calls && mix test` — 74 tests, 0 failures.
- Focused behavior covers pending facts at 30 seconds, a deterministic wake-up at the exact
  60-second deadline, incomplete publication submission, source-read outage, and later successful
  complete publication.
- Root `mix format --check-formatted`, `mix compile --warnings-as-errors`,
  `mix deps.unlock --check-unused`, and `mix credo --strict` passed; Credo checked 756 source files
  without issues.
- Root `VXPIPE_TEST_DATABASE_URL=postgres://postgres:postgres@127.0.0.1:55433/vxpipe_test mix
  test` passed 934 tests across all umbrella children with the existing external integration-tag
  exclusions.

## 2026-09-12 — checkpoint C3c

### Decisions

- Capture the room-incarnation source-stop timestamp as soon as its monitor reports termination,
  before draining queued archive writes. The completion fact reuses that captured value rather than
  measuring storage completion time.
- Let the asynchronous persistence subscriber project call end as part of storing the private
  `archive_stream_closed` fact. `ArchiveStore` holds the owning call lock and writes the closure and
  `running`-to-`ended` transition in one transaction; the live room never waits for it.
- Preserve the original `started_at` and accept only an end at or after it. An identical closure
  retry is idempotent; a conflicting timestamp is rejected rather than changing call duration.
- Keep `terminal_reason` null for a normally ended durable call at this boundary. The monitored
  outer room supervisor does not preserve all semantic inner shutdown reasons, while the closure
  fact already retains the observed source reason. Null is more honest than inventing a reason.
- Extract completion-fact construction from the existing archive subscriber and call-end projection
  from the existing persistence store. The new modules are 30 and 42 lines respectively; neither
  the Engine nor persistence adapter gains the other's responsibility.

### Red evidence

- The focused Engine test expected a fixed source-stop time in the completion fact and instead saw
  current time measured after drain.
- The focused PostgreSQL test persisted a closure successfully but reloaded the call in its prior
  `running` state.

### Green evidence

- `cd apps/vxpipe_call_engine && mix test test/vxpipe/call_engine/archive/subscriber_test.exs` —
  6 tests, 0 failures.
- `cd apps/vxpipe_persistence && VXPIPE_TEST_DATABASE_URL=postgres://postgres:postgres@127.0.0.1:55433/vxpipe_test mix test test/vxpipe/persistence/call_store_test.exs`
  — 17 tests, 0 failures.
- The persistence behavior covers closure replay idempotency, exact `ended_at`, unchanged
  `started_at`, and the full bounded-subscriber path from monitored source exit through reload of
  the ended call.
- The complete Call Engine suite passed 397 tests with 1 existing integration exclusion; the
  complete Persistence suite passed 43 tests.
- Umbrella `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix credo --strict`,
  and `mix deps.unlock --check-unused` passed; Credo checked 758 files and reported no issues.
- Root `VXPIPE_TEST_DATABASE_URL=postgres://postgres:postgres@127.0.0.1:55433/vxpipe_test mix
  test` completed successfully across every umbrella child with the existing external integration
  exclusions.

## 2026-09-12 — checkpoint C3d

### Decisions

- Implement the production source as a Persistence adapter for the Calls-owned `PublicationSource`
  port. It loads every source relation in one PostgreSQL repeatable-read transaction, while Calls
  continues to own assessment, reporting-window and delivery behavior.
- Split query coordination, call/participant projection, archive-fact projection, Variables,
  structured usage, recording artifacts, timestamps and component assessment into focused modules.
  The public adapter coordinates them but does not accumulate each concern's encoding rules.
- Project only safe participant definition metadata and protected leg references. Do not copy agent
  prompts or connection destination numbers into the publication. Tool arguments/results remain in
  this private operator object after the existing archive sanitizer removes credential-shaped keys.
- Reuse source-time transcript filtering and recording source-interval policy as the primary privacy
  boundaries. Statically prohibited recording also suppresses all artifact references in the final
  projection, even if inconsistent metadata exists.
- Treat unknown usage price as observed data rather than zero or incomplete. No usage observations
  is `not_produced`; internally inconsistent amount evidence is `missing`.
- Bind recording expectation explicitly to the source adapter. An empty artifact set is `pending`
  when recording was configured and `unconfigured` otherwise; this expectation cannot grant
  recording. Runtime configuration currently mirrors the application-wide recording choice. If
  recording becomes per-call later, the expectation must be persisted with that call.

### Red evidence

- The new PostgreSQL integration test first reached the intended
  `UndefinedFunctionError` for `Vxpipe.Persistence.CallDetailsSource.read/3`. An earlier attempt was
  corrected because an unrelated invalid host-tool fixture stopped definition publication before
  the missing adapter could be exercised.

### Green evidence

- `cd apps/vxpipe_persistence && VXPIPE_TEST_DATABASE_URL=postgres://postgres:postgres@127.0.0.1:55433/vxpipe_test mix test test/vxpipe/persistence/call_details_source_test.exs`
  passed 2 tests. The complete source case covers pinned identity, lifecycle/route, safe participant
  activations, ordered transcript/delivery, tool/transfer history, latest and historical Variables,
  typed usage, protected recording references, component completeness and tenant isolation. The
  second case distinguishes configured-pending from unconfigured recording and absent usage.
- Root `mix compile --warnings-as-errors` passed after adding the adapter and projectors. Root
  `mix credo --strict` checked 769 source files and reported no issues.
- The complete Persistence suite passed 45 tests. Root `mix format --check-formatted`,
  `mix compile --warnings-as-errors`, `mix credo --strict`, and `mix deps.unlock --check-unused`
  passed. The database-backed umbrella run passed 936 tests across all eight child applications,
  with only the existing explicitly excluded external integration cases.

## 2026-09-12 — checkpoint C3e1

### Decisions

- Keep finalization trigger policy in Calls rather than the Ecto adapter. Archive closure, terminal
  artifact metadata and successfully stored billing enrichment are the only current authoritative
  inputs that request an assessment. Ordinary facts, Variables snapshots and raw usage
  observations do not start repeated finalizers.
- Request only after the owning repository operation succeeds. Starting assessment is a
  best-effort follow-on: its failure cannot reinterpret a committed history, artifact or billing
  write as failed.
- Make automatic triggering opt-in and resolve a narrow finalizer-starter behavior from application
  settings. Production uses the existing `PublicationFinalizers` boundary; tests observe the
  request without constructing unrelated delivery dependencies.
- Treat `call_not_found` and `call_not_ended` as terminal for that short-lived assessment request.
  This is expected when artifact or billing metadata lands before archive closure. Closure later
  requests a new assessment, while genuine source outages continue to poll.
- Separate trigger policy and finalizer admission behind focused modules. Archive, artifact and
  billing workflows only identify their post-commit trigger points; they do not own publication
  timing or delivery.

### Red evidence

- The focused Calls run had four intended failures: committed closure, artifact and billing
  enrichment produced no finalization request, and a finalizer receiving `call_not_found` retried
  instead of stopping cleanly.

### Green evidence

- `cd apps/vxpipe_calls && mix test test/vxpipe/calls/archives_test.exs
  test/vxpipe/calls/artifacts_test.exs test/vxpipe/calls/billing_enrichment_test.exs
  test/vxpipe/calls/publication_finalizer_test.exs` — 22 tests, 0 failures.
- `cd apps/vxpipe_calls && mix test` — 77 tests, 0 failures.
- Focused behavior proves only archive closure triggers from the fact stream, committed artifact and
  billing results request refresh, and missing/still-live calls terminate without a retry timer.
  Production object-store enablement and database-backed late revision verification are the next
  checkpoint.
- Root `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix credo --strict`, and
  `mix deps.unlock --check-unused` passed; Credo checked 771 source files without issues. The
  database-backed umbrella test command also exited successfully across all child applications
  with the existing tagged external integrations excluded.

## 2026-09-12 — checkpoint C3e2

### Decisions

- Configure automatic delivery only when the runtime has both PostgreSQL and a non-empty
  call-details object bucket. This keeps the default embeddable Calls application side-effect free
  and avoids creating retrying finalizers without a valid writer.
- Allow dedicated `VXPIPE_CALL_DETAILS_S3_*` settings to fall back individually to the existing
  `VXPIPE_RECORDING_S3_*` target. One call-artifact bucket therefore suffices, while deployments can
  separate JSON documents when required. Call-details configuration never enables recording.
- Put S3 document-target validation in the artifacts application. It accepts a bucket, optional
  region and a root HTTP(S) endpoint, constructs path-style ExAws request options, and rejects paths,
  embedded credentials and non-HTTP schemes without copying the supplied value into an error.
- Enable Calls trigger admission and persistence recovery with the exact same artifact-writer
  adapter. Runtime configuration preserves the common reporting-window and retry settings instead
  of replacing the nested application configuration.
- Verify the composed behavior against PostgreSQL: closure at the reporting deadline creates and
  commits an incomplete revision when configured recording is pending; later terminal recording
  metadata starts reassessment, commits a distinct complete revision and advances the latest
  pointer while retaining the first object record.

### Red evidence

- The new artifacts tests failed three times with `UndefinedFunctionError` because
  `Vxpipe.Artifacts.S3DocumentConfiguration.build/1` did not exist.

### Green evidence

- `cd apps/vxpipe_artifacts && mix test
  test/vxpipe/artifacts/s3_document_configuration_test.exs` — 3 tests, 0 failures.
- `cd apps/vxpipe_persistence &&
  VXPIPE_TEST_DATABASE_URL=postgres://postgres:postgres@127.0.0.1:55433/vxpipe_test mix test
  test/vxpipe/persistence/call_details_source_test.exs` — 3 tests, 0 failures. The added flow uses
  the production PostgreSQL source/repository with independently supervised finalizer and delivery
  workers and a deterministic test object writer.
- A `MIX_ENV=test mix run --no-start` configuration probe with non-secret dummy database and S3
  values showed the existing window/retry settings preserved, trigger delivery enabled with the
  validated writer, and recovery bound to that same writer. No database or object-store application
  was started and no network request was made.
- The complete Artifacts suite passed 17 tests with its existing live S3 case excluded, and the
  complete Persistence suite passed 46 tests. Root formatting, warnings-as-errors compilation,
  strict Credo over 772 source files, unused-dependency checking, and the database-backed umbrella
  suite all exited successfully with only the existing tagged external integrations excluded.

## 2026-09-12 — checkpoint C4a

### Decisions

- Keep operator reads behind a dedicated `CallDetailsInspectionRepository` rather than expanding
  the delivery-worker repository. Calls owns tenant/scope authorization, request validation and
  pagination; persistence owns table joins and decoding.
- List both pending and published revision metadata so an operator can distinguish unavailable
  delivery from an absent publication. Expose identity, timestamp, filename, completeness, state,
  SHA-256, exact byte size and latest-head status without exposing object keys or references.
- Return exact persisted canonical JSON only for a published revision. A pending row has not proven
  object delivery and therefore shares the not-found result with foreign-tenant or absent rows.
- Use a bounded page of 25 by default and 100 at most. The continuation encodes recorded time and
  publication identity as opaque URL-safe JSON; repository ordering is newest first.
- Keep the future Console presenter/controller separate from Calls and persistence. The backend
  document struct suppresses contents from `Inspect`, preventing accidental log output before the
  HTTP boundary deliberately sends it.

### Red evidence

- The Calls test first failed while compiling its fake adapter because `CallDetailsCursor` and the
  call-details inspection repository behavior did not exist.
- The PostgreSQL test then failed with `UndefinedFunctionError` for
  `Vxpipe.Persistence.CallDetailsInspectionStore.list/5`.

### Green evidence

- `cd apps/vxpipe_calls && mix test test/vxpipe/calls/call_details_inspections_test.exs` — 2 tests,
  0 failures. It proves bounded continuation, exact published bytes, scope rejection and invalid
  request/cursor rejection before repository access.
- `cd apps/vxpipe_persistence &&
  VXPIPE_TEST_DATABASE_URL=postgres://postgres:postgres@127.0.0.1:55433/vxpipe_test mix test
  test/vxpipe/persistence/call_details_publication_store_test.exs` — 6 tests, 0 failures. It proves
  safe newest-first metadata, cursor continuation, nonregressing head indication, exact canonical
  bytes, pending denial and cross-tenant denial.
- The complete Calls suite passed 79 tests and the complete Persistence suite passed 47 tests. Root
  formatting, warnings-as-errors compilation, strict Credo over 779 source files,
  unused-dependency checking, and the database-backed umbrella suite all exited successfully with
  only the existing tagged external integrations excluded.
