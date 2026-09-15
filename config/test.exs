import Config

test_database_url = System.get_env("VXPIPE_TEST_DATABASE_URL")

test_repo =
  if test_database_url do
    [url: test_database_url]
  else
    connection =
      case System.get_env("PGHOST") do
        nil -> []
        "/" <> _path = socket_dir -> [socket_dir: socket_dir]
        hostname -> [hostname: hostname]
      end

    connection ++
      [
        username: System.get_env("PGUSER") || System.fetch_env!("USER"),
        database: System.get_env("VXPIPE_TEST_DATABASE", "vxpipe_test")
      ]
  end

config :vxpipe_persistence,
       Vxpipe.Persistence.Repo,
       test_repo ++
         [
           pool: Ecto.Adapters.SQL.Sandbox,
           pool_size: System.schedulers_online() * 2
         ]

config :vxpipe_call_engine, Vxpipe.CallEngine.Application,
  credential_source: {Vxpipe.CallEngine.TestSpeechCredentialSource, :synthetic},
  agent_runtime: [
    implementation: :agent_runtime,
    fixture:
      {Vxpipe.CallEngine.Diagnostics.AgentRuntimeModelProvider,
       [fixture: Vxpipe.CallEngine.Diagnostics.ModelFixture]},
    tool_invocation_timeout_ms: 30_000,
    maximum_tool_invocations: 4,
    maximum_completed_requests: 32,
    maximum_model_context_bytes: 262_144,
    model_context_timeout_ms: 1_000,
    maximum_pending_requests: 4,
    maximum_output_bytes: 65_536,
    maximum_tool_result_bytes: 16_384,
    request_timeout_ms: 30_000
  ],
  model_fixture: [
    enabled: true,
    default_scenario: :success,
    delay_ms: 0,
    response: "Local fixture response."
  ],
  telemetry: [sample_interval_ms: 3_600_000]

config :vxpipe_console, Vxpipe.Console.Endpoint,
  secret_key_base: String.duplicate("test-only-", 8)
