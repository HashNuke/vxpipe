# Definition-driven call implementation

## Goal

Implement milestone 1, `definition-driven-call`, as sequential red-green
checkpoints. Keep the existing room, gateway, speech and interruption behavior
green while replacing preset startup with a pinned typed definition and a
supervised Jido agent activation.

## Baseline

- Milestone status is not implemented and has no prerequisites.
- The current engine accepts `CreateRoom.agent` presets and directly starts the
  custom `ModelInference` capability from application settings.
- `vxpipe_call_engine` currently depends on ReqLLM and WebSockex; Jido AI and
  Jido Action are not installed.
- The existing gateway creates rooms through the preset path. The first compiler
  checkpoint must therefore be additive and must not break that runnable path.
- Worktree was clean at the start of the goal. Commit `702b4bb` is the preceding
  documentation checkpoint.

## Checkpoint 1: typed definition boundary

Selected schema release: `20260906.02`, matching the approved candidate in the
call-definition design. Resource ID and revision are trusted constructor metadata,
not keys in the schema document. Trusted tenant and actor identities are constructor
options for `CallInvocation`, not invocation-body values.

The initial supported compiler subset is deliberately closed:

- human web caller using receive/start-call connection intent;
- one agent receiver with inline prompt and first-message mode;
- capability profile refs resolved from a trusted registry;
- exact-name static host-tool bindings;
- bounded call duration; and
- empty transfers only until the transfer milestone.

Unsupported fields and enabled later-milestone behavior fail with path-specific,
secret-safe errors. Raw JSON maps and ordinary Elixir maps must converge on the
same structs. A resolved plan gets fresh call/room/participant/activation identities
and copies resolved data so later source/catalog changes cannot affect it.

### Red evidence

Added focused compiler tests covering JSON/Elixir parity, entry refs, schema and
field rejection, trusted invocation identity, closed profile/tool resolution,
pinning, and fresh runtime identities.

The first focused run failed during test compilation at the first expected
typed structure: `Vxpipe.CallEngine.CallDefinition.ConnectionIntent` was
undefined. No test executed, confirming that the new boundary was absent rather
than failing because of existing runtime behavior.

### Green implementation and review

- Added one top-level module per file for definition, participant, connection,
  capability refs/selections, tool selection, invocation, resolved plan and its
  participant/capability/tool data, plus pure validation and compilation.
- Extended only the engine's protocol-neutral error-code union and ID generator.
- Fixed-key normalization accepts the atom-key form used by trusted Elixir hosts
  and string keys produced by `JSON.decode/1`; it never converts input to atoms.
- Definition resource identity and invocation tenant/actor identity are supplied
  as trusted constructor options. Unknown invocation keys therefore reject entry
  or tenant override attempts.
- Closed capability-profile and host-tool maps are the only resolution path.
  Capability options containing credential-like keys cannot enter the pinned plan.
- The first green run passed `7 tests, 0 failures`. It initially exposed an alias
  collision between definition and resolved participant structs; fixing the
  explicit struct match resolved that implementation defect. Warnings for unused
  clause arguments were also removed.
- No room, provider, gateway, Jido or sample behavior changed in this checkpoint.

### Checkpoint 1 verification

From the umbrella root:

- `mix format --check-formatted` passed.
- `mix compile --warnings-as-errors` passed for call engine and gateway.
- `mix test` passed: call engine `73 tests, 0 failures (1 excluded)` and gateway
  `37 tests, 0 failures (3 excluded)`. Expected failure-path tests emitted
  supervised provider/transport termination logs without test failures.
- `mix deps.unlock --check-unused` passed with no output.

### Remaining milestone work

Runtime plan startup, supervised Jido integration, host-action execution through
Jido, provider failure cleanup, the trusted sample fixture, browser verification
and all milestone-level acceptance checks remain pending. Existing preset startup
stays available until the replacement path is proven.

## Checkpoint 2: typed initial Call Variables

This compiler checkpoint uses the already locked JSV 0.22 dependency for
Draft 2020-12 validation. The call-engine application declares it directly because
the engine owns schema compilation. JSV is configured without application-provided
resolvers and without atom casting. Definition validation rejects external `$ref`
usage rather than allowing network schema resolution.

### Red evidence

Focused tests cover typed section schemas, read/read+write agent permissions,
recursive default rejection, invalid schemas, partial initial values despite
`required`, explicit empty sections, unknown sections/properties, wrong datatypes,
JSON/Elixir parity, and unfilled sections remaining absent rather than becoming
empty or null values. The initial run failed while compiling the test because
`Vxpipe.CallEngine.CallDefinition.VariableSection` did not exist.

Review of the first green implementation found that removing `required` before
building the validator also allowed a malformed string-valued `required` keyword.
A new focused case reproduced that defect before the schema compiler was tightened;
an unsupported `allOf` case also establishes the dated schema's closed boundary.

### Green implementation and review

- Added typed Call Variables declaration, variable-section, permission, resolved
  section and resolved collection structures, one top-level module per file.
- Agent grants accept only `read` or the unique pair `read` and `write`, and must
  name a declared section. Human participants cannot declare agent grants.
- A schema compiler validates JSON-only data and a closed initial keyword/type
  subset, rejects defaults and references by treating all unsupported keywords
  uniformly, then compiles through JSV without casts or reference resolvers.
- `required` is validated as authored metadata, then removed contextually from
  schema nodes in the compiled runtime validator. It is not removed from enum data
  or the authored definition. Partial values therefore remain type checked at any
  populated depth without demanding missing values.
- Initial values validate before participant resolution/provider startup. Unknown
  sections, non-object roots, undeclared direct variables and datatype violations
  return only a path and generic reason. Omitted sections use `nil` with revision
  zero; explicitly supplied empty objects remain `%{}` with revision zero.
- Focused Call Variables tests passed `7 tests, 0 failures`; the original compiler
  tests passed `7 tests, 0 failures`.
- The first complete engine run had one unrelated 100 ms STT monitor assertion
  miss while its expected termination appeared in logs. That test passed alone,
  and the complete engine rerun passed `80 tests, 0 failures (1 excluded)`.

### Checkpoint 2 verification

From the umbrella root after the test-only termination-wait checkpoint `c1547f9`:

- `mix format --check-formatted` passed.
- `mix compile --warnings-as-errors` passed.
- `mix test` passed: call engine `80 tests, 0 failures (1 excluded)` and gateway
  `37 tests, 0 failures (3 excluded)`. Expected failure-path tests emitted
  supervised provider/transport termination logs without test failures.
- `mix deps.unlock --check-unused` passed with no output.

The milestone records the constructor/compiler test and minimal compiler checklist
items as complete. The ordered milestone index remains unchecked because the
runnable definition-driven call has not been delivered. Runtime variable ownership
and tools remain milestone 4 rather than being claimed by this compiler checkpoint.
Final staged-diff and worktree review remain before commit and push.
