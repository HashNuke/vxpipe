# Google activation configuration

- Isolated branch baseline verified clean at `9908a1a1`; native implementation
  explicitly authorized. No teammate runner, hosted calls or credential inspection.
- Read AGENTS, milestone/index, prerequisites and relevant provider/private startup
  contracts. Expanded the existing configuration item before tests or code.
- Found Google absent from the fixed registry (intentional hosted gate); its private
  config currently has no prompt/tools. Existing resumption reuses `STS.setup(config)`.
- Reuse `AgentRuntime.ToolDescriptors` for authorized bindings. Keep executable
  bindings out of provider config. Shared tool lifetime/room changes remain parent-owned.
- Verification uses two BEAM schedulers, this checkout's build, focused child tests.

## Decisions and implementation

- `PlanStartup` now resolves private STS activation data before constructing the
  runtime. The existing descriptor compiler selects authorized host/platform/
  transfer definitions and variable actions; only model-visible fields survive.
- Exposed the existing `AgentActivation.variable_binding/3` helper for reuse.
  Validation-only startup cannot silently omit granted variable tools. Missing
  variable binding or MCP owner fails with a sanitized configuration error.
- Google private resolution validates authenticated options independently of
  public descriptor configuration. Prompt/tool overrides in those options fail;
  the pinned activation is authoritative. Registry/catalog production gating is
  unchanged, so Google startup is verified directly at the configuration boundary.
- Official sources read: `https://ai.google.dev/api/live#bidigeneratecontentsetup`
  and `https://ai.google.dev/api/generate-content#FunctionDeclaration`. Confirmed
  Content text parts and `parametersJsonSchema` preserve schemas without lossy
  conversion. Also corrected the existing top-level activity-detection field to
  its documented `realtimeInputConfig` location, after a focused failing test.
- Private config is retained across the existing handle resumption flow. Provider
  startup revalidates structs before sockets. No fresh fallback or replay.
- Bounds: 64 KiB UTF-8 prompt, 64 tools, 128 KiB combined term and JSON, plus shared
  descriptor/schema limits. Config and startup inspect redaction covers private
  prompt/schema/key material; fake-wire failure test checks logs and status.

## Red/green evidence and coordination

- Copied dependency sources into this checkout before building; all dependency
  compilation and native outputs stayed local. Main build/deps were not modified.
- Initial command (three files below), baseline implementation: 16 tests, five
  expected failures. Prompt leaked through startup Inspect, Google rejected private
  prompt/tools, and the activation resolver/provider arity did not exist.
- Existing command handle `50731` completed exit 2 at 16:53 UTC. Held new BEAM
  commands during the parent's measurement window; a process check found no live
  checkout BEAM/build processes. Resumed only after explicit release.
- First implementation: the same 16 tests passed. Next Google run: 31 tests, two
  failures (missing private-config revalidation and provider module load ordering
  during direct activation). Added explicit load checking; did not mask by retry.
- Tampered-config red: one test failed because a fake socket actually received the
  invalid declaration. Added pre-connect struct validation. Combined 38 tests green.
- Documented activity-field red: 18 tests, one failure (missing nested field).
  Authenticated resolution red: six tests, one failure (missing configure boundary).
  Both repaired; combined 43 tests passed before final added compiled-plan coverage.
- Final focused command below: **88 tests, zero failures**, seed 0, 5.6 seconds.
  All changed Elixir files formatted; `git diff --check` clean.

Reproduction, from this isolated checkout's root (build variable is task-local):

```sh
task_build="$PWD/_build"
cd apps/vxpipe_call_engine
ERL_FLAGS='+S 2:2' MIX_BUILD_PATH="$task_build" mix test \
  test/vxpipe/call_engine/plan_startup/sts_configuration_test.exs \
  test/vxpipe/call_engine/plan_startup/sts_activation_test.exs \
  test/vxpipe/providers/google/sts_test.exs --seed 0
```

Those were the initial three-file red/green targets; subsequent tests expanded them.
Final focused regression command, from the same child with the same build variable:

```sh
ERL_FLAGS='+S 2:2' MIX_BUILD_PATH="$task_build" mix test \
  test/vxpipe/call_engine/plan_startup \
  test/vxpipe/call_engine/call_spec/sts_selection_test.exs \
  test/vxpipe/providers/google/sts_test.exs \
  test/vxpipe/providers/google/sts_session_test.exs \
  test/vxpipe/providers/google/sts_output_test.exs \
  test/vxpipe/call_engine/speech/sts_conformance_test.exs \
  test/vxpipe/call_engine/speech/sts_output_test.exs --seed 0
```

## Handoff limits

- No hosted/billable calls, credentials inspection, production selection/manifest
  or UI enablement, history replay, main checkout writes or tool execution.
- MCP support needs an explicitly owned activation runtime before using its
  descriptors; no fake owner or dynamic registry bypass was introduced. Variable
  tools use the existing binding; shared execution/retirement remains parent-owned.
- Final serial umbrella, native and measured-load gates and independent integration
  review belong to the parent. No full suite or measured load was run here. The
  index remains unchecked; this only closes the bounded local configuration item.
