import Config

config :vxpipe_persistence, Vxpipe.Persistence.Repo,
  username: "postgres",
  password: "postgres"

config :vxpipe_call_engine, Vxpipe.CallEngine.Application,
  agent_runtime: [context_compaction: [enabled: true]]

config :vxpipe_gateway, Vxpipe.Gateway.Application, http: [enabled: false]

development_secret = String.duplicate("development-only-", 4)

config :vxpipe_console, :development_operator_login_secret, development_secret

config :vxpipe_console, Vxpipe.Console.Endpoint,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: development_secret,
  server: true,
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:vxpipe_console, ~w(--sourcemap=inline --watch)]},
    tailwind:
      {System, :cmd,
       [
         "npm",
         ["run", "css:watch"],
         [cd: Path.expand("../apps/vxpipe_console/assets", __DIR__)]
       ]}
  ],
  live_reload: [
    patterns: [
      ~r"priv/static/assets/.*\.(css|js)$",
      ~r"lib/vxpipe/console/.*\.(ex|heex)$"
    ]
  ]

config :vxpipe_console, :diagnostics, enabled: true
