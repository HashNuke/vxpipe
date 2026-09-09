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
  telemetry: [sample_interval_ms: 3_600_000]

config :vxpipe_console, Vxpipe.Console.Endpoint,
  secret_key_base: String.duplicate("test-only-", 8)
