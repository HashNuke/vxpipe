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

### Remaining milestone work

Typed Call Variables are still rejected unless empty. Runtime plan startup,
supervised Jido integration, host-action execution through Jido, provider failure
cleanup, the trusted sample fixture, browser verification and all milestone-level
acceptance checks remain pending. Existing preset startup stays available until
the replacement path is proven.

### Verification evidence

From the umbrella root:

- `mix format --check-formatted` passed.
- `mix compile --warnings-as-errors` passed for call engine and gateway.
- `mix test` passed: call engine `73 tests, 0 failures (1 excluded)` and gateway
  `37 tests, 0 failures (3 excluded)`. Expected failure-path tests emitted
  supervised provider/transport termination logs without test failures.
- `mix deps.unlock --check-unused` passed with no output.

The milestone records only the constructor/compiler-test checklist item as
complete. The ordered milestone index remains unchecked because the runnable
definition-driven call has not been delivered. Final staged-diff and worktree
review remain before commit and push.
