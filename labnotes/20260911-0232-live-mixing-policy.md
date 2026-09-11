# Live mixing and media policy

## 2026-09-11 — immutable policy contract

- Began milestone 15 on `milestone/live-mixing-media-policy`. The first checkpoint deliberately
  establishes one compiled policy input before implementing realtime frame routing: public JSON
  semantics must not be duplicated by Room Authority, a mixer, transcript projection, and storage
  gates.
- Selected four independently optional fields for both normal `media_policy` and participant
  `while_present`: `audio_routes`, `transcript_routes`, `record_audio`, and `save_transcripts`.
  Omission is represented as `:inherit`; an explicit empty route map remains an empty map. Route
  values retain ordered definition keys in the validated definition and compile to participant IDs
  plus `MapSet` recipients in the immutable plan.
- Wrote the focused compiler test first. Its red run stopped at test compilation because
  `CallDefinition.MediaPolicy` did not exist, which was the expected missing contract.
- Added separate validated-definition and resolved-plan policy modules. The call definition owns
  closed shape/reference validation; the resolved policy owns the one-time definition-key to
  runtime-ID translation. Participant parsing owns only the optional `while_present` field, and the
  compiler continues to compose the immutable plan rather than absorbing policy behavior.
- The first complete Call Engine run exposed two expected migration gaps: the older compiler test
  still classified the newly supported keys as invalid, and direct resolved-plan fixtures lacked
  the new enforced field. Updating those assertions/fixtures restored the suite without weakening
  the new invalid-shape coverage.
- Focused verification: `mix test
  test/vxpipe/call_engine/call_definition/media_policy_compiler_test.exs` passes four tests.
  The final focused case first mutated an otherwise validated policy to an unsupported permission
  atom and demonstrated that compilation accepted it. The resolved-policy compiler now revalidates
  those permission values and rejects the forged typed input at the policy boundary.
  Complete Call Engine verification: `mix test` passes 286 tests with one tagged integration
  exclusion. Umbrella formatting, warnings-as-errors compilation, strict Credo, and unused-lock
  checks pass.
- The first database-backed umbrella test run exposed the prior transfer commit race documented in
  the transfer labnote. After that independently committed correction, a fresh run against a
  disposable PostgreSQL 17 instance passes: MCP 37 tests with three exclusions, Agent Runtime 58
  with two exclusions, Call Engine 286 with one exclusion, Calls 37, Persistence 25, Gateway 67
  with four exclusions, and Console 57. The disposable database was removed after verification.
- Runtime policy intersection, authoritative presence transitions, media commit barriers, mixer
  supervision, route delivery, and transcript/archive gates are intentionally not claimed yet.

## 2026-09-11 — pure effective-policy intersection

- Wrote the effective-policy tests before the implementation. All five initially failed because
  `Vxpipe.CallEngine.MediaPolicy.Effective` did not exist.
- Added a pure composer that accepts the resolved host ceiling, normal call policy, and a map of
  authoritatively present participant contributions. It performs no process, transport, or database
  work.
- Inherited routes become unrestricted only when every input inherits. Otherwise every explicit
  route map is treated as a complete allowlist: sources must survive every map and recipient sets
  are intersected. A surviving source with an empty recipient intersection remains explicit.
- Effective audio-recording and transcript-storage permissions are concrete booleans. Omission does
  not restrict; any false input wins. Recomputing without one owner removes only that contribution.
- Moved resolved-policy representation validation into its owning module. Malformed or forged
  inputs return `{:error, :invalid_policy}` so the later admission barrier can fail closed.
- Focused verification passes nine tests across the policy compiler and effective composer.
- Complete verification passes formatting, warnings-as-errors compilation, 291 Call Engine tests
  with one integration exclusion, strict Credo, and the unused-lock check. A fresh database-backed
  umbrella run also passes: MCP 37 tests with three exclusions, Agent Runtime 58 with two
  exclusions, Call Engine 291 with one exclusion, Calls 37, Persistence 25, Gateway 67 with four
  exclusions, and Console 57. The disposable PostgreSQL 17 container was removed afterward.

## 2026-09-11 — room policy authority

- Wrote four process-contract tests first. The red run failed at compilation because the
  `MediaPolicy.Authority` and revisioned `MediaPolicy.Snapshot` contracts did not exist.
- Added one temporary, significant GenServer per planned room. It owns only the immutable host/call
  policy inputs, participant-ID-to-policy catalog, active contribution map, monotonic revision, and
  current effective snapshot. It accepts only participant identities pinned into the resolved plan.
- Added a separate supervision-boundary assertion. Its red run found no registered policy process
  beside a live planned room; adding the significant child to the room incarnation made it green.
  If this privacy-critical process terminates, `auto_shutdown: :any_significant` ends the room
  subtree rather than restarting with an empty presence map.
- Tightened the existing definition-driven startup scenario from a revision-zero expectation to
  both entry participants at revision two. That red run proved the initially supervised process was
  not yet synchronized with Room Authority membership.
- Participant commit now applies the pinned `while_present` contribution before writing membership
  to Room Authority state. A transition failure aborts admission. Authoritative participant exit
  removes its contribution; a connection detach does not, which preserves the approved distinction
  between transport loss and leave.
- Focused room tests confirm the two entry admissions, disconnect-versus-leave behavior, and
  fail-closed room teardown on policy-authority loss. Media sinks do not consume policy revisions
  yet, so this is state ownership and commit-order groundwork rather than a completed media barrier.
- A subsequent boundary test submitted a participant ID absent from the pinned catalog. The policy
  rejection was correct, but the red test found its already-prepared participant supervisor still
  registered. `ParticipantLifecycle.start/3` now discards every preparation whose commit fails;
  rejection leaves neither membership nor a stray participant process and does not advance policy
  revision.
- Complete verification passes formatting, warnings-as-errors compilation, 297 Call Engine tests
  with one integration exclusion, strict Credo, and the unused-lock check. A fresh database-backed
  umbrella run also passes: MCP 37 tests with three exclusions, Agent Runtime 58 with two
  exclusions, Call Engine 297 with one exclusion, Calls 37, Persistence 25, Gateway 67 with four
  exclusions, and Console 57. The disposable PostgreSQL 17 container was removed afterward.
