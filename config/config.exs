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
      maximum_audio_packets: 100
    ],
    room_creation: [enabled: false],
    cors: [
      allowed_origins: [],
      allowed_methods: ["GET", "POST", "PATCH", "OPTIONS"],
      allowed_headers: ["content-type", "authorization"],
      allow_credentials: false
    ]
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
