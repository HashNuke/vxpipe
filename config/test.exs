import Config

config :vxpipe_call_engine, Vxpipe.CallEngine.Application,
  telemetry: [sample_interval_ms: 3_600_000]

config :vxpipe_console, Vxpipe.Console.Endpoint,
  secret_key_base: String.duplicate("test-only-", 8)
