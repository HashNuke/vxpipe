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
