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

config :vxpipe_call_engine, Vxpipe.CallEngine.Application,
  agent_runtime: [
    maximum_completed_requests: 32,
    maximum_pending_requests: 4,
    maximum_output_bytes: 65_536,
    maximum_tool_result_bytes: 16_384,
    request_timeout_ms: 30_000
  ],
  model_inference: [enabled: false],
  speech_to_text: [enabled: false],
  text_to_speech: [enabled: false]

config :vxpipe_gateway, Vxpipe.Gateway.Application,
  http: [
    enabled: false,
    ip: :loopback,
    port: 4000,
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
  access: :disabled

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
