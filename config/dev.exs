import Config

config :vxpipe_call_engine, Vxpipe.CallEngine.Application,
  speech_to_text: [
    enabled: true,
    provider: Vxpipe.CallEngine.Provider.Deepgram.Flux,
    provider_options: [
      model: "flux-general-en",
      encoding: :opus,
      sample_rate: 48_000
    ],
    transport: {Vxpipe.CallEngine.Provider.Deepgram.FluxSocket, []},
    media_ingress: [
      maximum_frames: 50,
      maximum_bytes: 262_144,
      maximum_age_ms: 2_000,
      maximum_consecutive_overflows: 5
    ]
  ]

config :vxpipe_gateway, Vxpipe.Gateway.Application,
  http: [
    enabled: true,
    room_creation: [
      enabled: true,
      agent: :deterministic_text,
      principal: [
        tenant_id: "tenant-development",
        actor_id: "actor-samples",
        scopes: ["rooms:create", "rooms:join"]
      ]
    ]
  ]
