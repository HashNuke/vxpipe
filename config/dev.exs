import Config

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
