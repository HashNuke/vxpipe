import Config

config :vxpipe_console, Vxpipe.Console.Endpoint,
  secret_key_base: String.duplicate("test-only-", 8)
