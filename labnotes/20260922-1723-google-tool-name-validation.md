# Google tool name validation

- Independent Astra xhigh review of fixed `dd501d39` reported P2: shared
  ToolDescriptor name validation uses `^...$`, admitting a trailing newline.
  Ordinary Call Spec rejects the name; no permission bypass was demonstrated.
- Parent requested an adapter-local full-string check, constructor regression
  and tampered-private-config fake-socket preconnect proof. Added the milestone
  task before tests/code. Existing sidecar work remains unstaged for its own commit.
- Exact reviewer probe: construct
  `%{"name" => "lookup\n", "description" => "synthetic",
  "parametersJsonSchema" => %{"type" => "object"}}`, pass it to
  `STS.new(api_key: "synthetic", tools: [tool])`, then call `STS.validate(config)`
  and `STS.setup(config)`. Baseline accepts and encodes the malformed name.
- Red: 36 Google codec/session tests, two expected failures. Constructor returned
  `{:ok, config}` for the review probe; tampered config connected the fake socket
  and emitted setup containing `lookup\n` instead of closing before connection.
- Repair: `STSAgentConfig` now requires `\A[A-Za-z0-9_-]+\z` before shared
  descriptor validation. The accepted alphabet and shared length bound are
  unchanged. No sanitization or shared ToolDescriptor changes.
- Green: same 36 tests, zero failures, seed 0; one second. Tests also reject CRLF,
  embedded newline, leading/trailing spaces, empty names and unsupported dots,
  and retain the exact accepted `0_lookup-ABC` name.
- All three changed Elixir files formatted; scoped diff check clean. Separate
  review checkpoint staged without the concurrent sidecar work. No broad gates.

Exact focused command from the isolated checkout root:

```sh
task_build="$PWD/_build"
cd apps/vxpipe_call_engine
ERL_FLAGS='+S 2:2' MIX_BUILD_PATH="$task_build" mix test \
  test/vxpipe/providers/google/sts_test.exs \
  test/vxpipe/providers/google/sts_session_test.exs --seed 0
```
