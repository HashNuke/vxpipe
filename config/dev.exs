import Config

sample_system_prompt = """
You are a concise, helpful voice assistant. Respond naturally in plain text.
Keep replies brief unless the user asks for detail. Do not use Markdown because
your response will be spoken aloud. Always use get_current_time when asked for
the current date or time; never guess it. Use read_variables when asked about the
sample order. Collect a concise request summary and urgency when the caller gives
them, then save those values in the intake section with update_variables. The
intake section has exactly two variables: summary is a string, and urgency is one
of low, normal, or high. Use those variable names exactly. Never claim a variable
update succeeded unless its tool result confirms success; correct or report a
failed update instead. Use prepare_background_report only when the caller
explicitly asks for a background report. A running result means the report was
accepted, not completed: acknowledge that it is running, continue the
conversation, and do not claim it is ready until the later completion arrives.
"""

sample_capability_profiles = %{
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
  },
  "morse-code-stt" => %{
    kind: :speech_to_text,
    provider: Vxpipe.CallEngine.Provider.MorseCodeSTT,
    options: %{
      amplitude: 4_096,
      frequency_hz: 700,
      sample_rate: 16_000,
      unit_duration_ms: 60
    }
  },
  "morse-code-tts" => %{
    kind: :text_to_speech,
    provider: Vxpipe.CallEngine.Provider.MorseCodeTTS,
    options: %{
      amplitude: 4_096,
      frequency_hz: 700,
      sample_rate: 48_000,
      unit_duration_ms: 60
    }
  }
}

sample_host_tools = %{
  "get_current_time" => Vxpipe.CallEngine.Tool.CurrentTime,
  "prepare_background_report" => Vxpipe.CallEngine.Tool.DelayedReport
}

config :vxpipe_calls, Vxpipe.Calls,
  registries: %{capability_profiles: sample_capability_profiles, host_tools: sample_host_tools}

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
    ],
    providers: %{
      Vxpipe.CallEngine.Provider.MorseCodeSTT => [
        enabled: true,
        provider_options: [],
        transport: {Vxpipe.CallEngine.Provider.MorseCodeSTT.Transport, []},
        media_ingress: [
          maximum_frames: 50,
          maximum_bytes: 262_144,
          maximum_age_ms: 2_000,
          maximum_consecutive_overflows: 5
        ]
      ]
    }
  ],
  text_to_speech: [
    enabled: true,
    provider: Vxpipe.CallEngine.Provider.Deepgram.FluxTextToSpeech,
    provider_options: [],
    transport: {Vxpipe.CallEngine.Provider.Deepgram.FluxTextToSpeechSocket, []},
    maximum_requests: 4,
    providers: %{
      Vxpipe.CallEngine.Provider.MorseCodeTTS => [
        enabled: true,
        provider_options: [],
        transport: {Vxpipe.CallEngine.Provider.MorseCodeTTS.Transport, []},
        maximum_requests: 4
      ]
    }
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
        tool_visibility: "full",
        initial_variables: %{
          "order" => %{"id" => "order-demo-1001"}
        },
        definition: %{
          schema_version: "20260910.01",
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
          call_variables: %{
            sections: %{
              "order" => %{
                schema: %{
                  "type" => "object",
                  "properties" => %{
                    "id" => %{"type" => "string", "minLength" => 1}
                  },
                  "additionalProperties" => false
                }
              },
              "intake" => %{
                schema: %{
                  "type" => "object",
                  "properties" => %{
                    "summary" => %{"type" => "string"},
                    "urgency" => %{
                      "type" => "string",
                      "enum" => ["low", "normal", "high"]
                    }
                  },
                  "additionalProperties" => false
                }
              }
            }
          },
          tool_visibility: "full",
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
                "get_current_time" => %{type: "host", tool: "get_current_time"},
                "prepare_background_report" => %{
                  type: "host",
                  tool: "prepare_background_report"
                }
              },
              transfers: [],
              variable_permissions: %{
                "order" => ["read"],
                "intake" => ["read", "write"]
              }
            }
          },
          limits: %{max_duration_ms: 1_800_000}
        },
        capability_profiles: sample_capability_profiles,
        host_tools: sample_host_tools
      ]
    ]
  ]

config :vxpipe_console, Vxpipe.Console.Endpoint,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: String.duplicate("development-only-", 4),
  server: true,
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:vxpipe_console, ~w(--sourcemap=inline --watch)]}
  ],
  live_reload: [
    patterns: [
      ~r"priv/static/assets/.*\.(css|js)$",
      ~r"lib/vxpipe/console/.*\.(ex|heex)$"
    ]
  ]

config :vxpipe_console, :diagnostics, enabled: true
