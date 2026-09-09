import Config

sample_system_prompt = """
You are a concise, helpful voice assistant. Respond naturally in plain text.
Keep replies brief unless the user asks for detail. Do not use Markdown because
your response will be spoken aloud. Always use get_current_time when asked for
the current date or time; never guess it.
"""

config :vxpipe_call_engine, Vxpipe.CallEngine.Application,
  speech_to_text: [
    enabled: true,
    provider: Vxpipe.CallEngine.Provider.Deepgram.Flux,
    provider_options: [],
    transport: {Vxpipe.CallEngine.Provider.Deepgram.FluxSocket, []},
    media_ingress: [
      maximum_frames: 50,
      maximum_bytes: 262_144,
      maximum_age_ms: 2_000,
      maximum_consecutive_overflows: 5
    ]
  ],
  text_to_speech: [
    enabled: true,
    provider: Vxpipe.CallEngine.Provider.Deepgram.FluxTextToSpeech,
    provider_options: [],
    transport: {Vxpipe.CallEngine.Provider.Deepgram.FluxTextToSpeechSocket, []},
    maximum_requests: 4
  ]

config :vxpipe_gateway, Vxpipe.Gateway.Application,
  http: [
    enabled: false,
    room_creation: [
      enabled: true,
      principal: [
        tenant_id: "tenant-development",
        actor_id: "actor-samples",
        scopes: ["rooms:create", "rooms:join"]
      ],
      trusted_call: [
        resource_id: "development-sample",
        revision: 1,
        definition: %{
          schema_version: "20260906.02",
          name: "Development sample",
          entry_caller: "caller",
          entry_receiver: "assistant",
          defaults: %{
            capabilities: %{
              speech_to_text: "deepgram-flux-stt",
              model_inference: "gemini-flash-lite",
              text_to_speech: "deepgram-flux-voice"
            }
          },
          call_variables: %{sections: %{}},
          participants: %{
            "caller" => %{
              type: "human",
              description: "Browser caller",
              connection: %{service: "web", mode: "receive", admission: "start_call"}
            },
            "assistant" => %{
              type: "agent",
              description: "Development voice assistant",
              prompt: sample_system_prompt,
              first_message: %{mode: "wait_for_input"},
              tools: %{
                "get_current_time" => %{type: "host", tool: "get_current_time"}
              },
              transfers: []
            }
          },
          limits: %{max_duration_ms: 1_800_000}
        },
        capability_profiles: %{
          "deepgram-flux-stt" => %{
            kind: :speech_to_text,
            provider: Vxpipe.CallEngine.Provider.Deepgram.Flux,
            options: %{model: "flux-general-en", encoding: :opus, sample_rate: 48_000}
          },
          "gemini-flash-lite" => %{
            kind: :model_inference,
            provider: :req_llm,
            options: %{model: "google:gemini-3.5-flash-lite"}
          },
          "deepgram-flux-voice" => %{
            kind: :text_to_speech,
            provider: Vxpipe.CallEngine.Provider.Deepgram.FluxTextToSpeech,
            options: %{model: "flux-haley-en", encoding: :linear16, sample_rate: 48_000}
          }
        },
        host_tools: %{
          "get_current_time" => Vxpipe.CallEngine.Tool.CurrentTime
        }
      ]
    ]
  ]

config :vxpipe_console, Vxpipe.Console.Endpoint,
  debug_errors: true,
  secret_key_base: String.duplicate("development-only-", 4),
  server: true,
  watchers: [
    node: [
      "vite-dev.mjs",
      cd: Path.expand("../apps/vxpipe_console/assets", __DIR__)
    ]
  ]

config :vxpipe_console, :diagnostics, enabled: true
