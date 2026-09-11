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
