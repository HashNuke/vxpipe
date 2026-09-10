# This file is responsible for configuring your umbrella
# and **all applications** and their dependencies with the
# help of the Config module.
#
# Note that all applications in your umbrella share the
# same configuration and dependencies, which is why they
# all use the same configuration file. If you want different
# configurations or dependencies per app, it is best to
# move said applications out of the umbrella.
import Config

config :phoenix, :filter_parameters, ["password", "secret", "token", "api_key"]

config :vxpipe_persistence,
  ecto_repos: [Vxpipe.Persistence.Repo],
  enabled: false

config :vxpipe_persistence, Vxpipe.Persistence.Repo, log: false

config :vxpipe_calls, Vxpipe.Calls,
  live_inspection_source: {Vxpipe.Calls.EngineLiveInspectionSource, []},
  registries: %{capability_profiles: %{}, host_tools: %{}}

config :vxpipe_call_engine, Vxpipe.CallEngine.Application,
  agent_runtime: [
    implementation: :agent_runtime,
    model_provider: Vxpipe.AgentRuntime.Provider.ReqLLM,
    model_provider_options: [],
    model_provider_label: :req_llm,
    tool_invocation_timeout_ms: 30_000,
    maximum_tool_invocations: 4,
    maximum_completed_requests: 32,
    maximum_pending_requests: 4,
    maximum_output_bytes: 65_536,
    maximum_tool_result_bytes: 16_384,
    request_timeout_ms: 30_000
  ],
  model_fixture: [enabled: false],
  model_inference: [enabled: false],
  live_inspection: [maximum_pending_records: 64, maximum_retained_records: 256],
  remote_mcp: [
    enabled: false,
    refresh_interval_ms: 60_000,
    stale_after_ms: 300_000,
    refresh_timeout_ms: 30_000
  ],
  speech_to_text: [enabled: false],
  telemetry: [sample_interval_ms: 1_000],
  text_to_speech: [enabled: false]

config :vxpipe_gateway, Vxpipe.Gateway.Application,
  http: [
    enabled: false,
    ip: :loopback,
    port: 4000,
    call_admission: [enabled: false],
    webrtc: [
      ice_servers: [],
      candidate_gathering_timeout_ms: 1_000,
      maximum_audio_packets: 500
    ],
    room_creation: [enabled: false],
    cors: [
      allowed_origins: [],
      allowed_methods: ["GET", "POST", "PATCH", "OPTIONS"],
      allowed_headers: ["content-type", "authorization"],
      allow_credentials: false
    ]
  ]

config :vxpipe_console, Vxpipe.Console.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  live_view: [signing_salt: "vxpipe-console-live"],
  pubsub_server: Vxpipe.Console.PubSub,
  server: false,
  url: [host: "localhost"]

config :vxpipe_console, :diagnostics,
  enabled: false,
  max_pending_events: 1_000

config :vxpipe_console, :sample_call, enabled: false

config :vxpipe_console, :operator_authenticator, {Vxpipe.Console.CallsOperatorAuthenticator, []}

config :vxpipe_console, :operator_session, max_age_seconds: 3_600

config :vxpipe_console, :call_inspection_backend, {Vxpipe.Console.CallsInspectionBackend, []}

config :esbuild,
  version: "0.25.4",
  vxpipe_console: [
    args:
      ~w(src/main.tsx --bundle --format=esm --target=es2022 --outdir=../priv/static/assets --entry-names=app),
    cd: Path.expand("../apps/vxpipe_console/assets", __DIR__),
    env: %{
      "NODE_PATH" => Path.expand("../apps/vxpipe_console/assets/node_modules", __DIR__)
    }
  ]

# Sample configuration:
#
#     config :logger, :default_handler,
#       level: :info
#
#     config :logger, :default_formatter,
#       format: "$date $time [$level] $metadata$message\n",
#       metadata: [:user_id]
#

import_config "#{config_env()}.exs"
