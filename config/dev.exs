import Config

config :vxpipe_persistence, Vxpipe.Persistence.Repo,
  username: "postgres",
  password: "postgres"

sample_reception_prompt = """
You are a concise, helpful reception voice assistant. Respond naturally in plain text.
Keep replies brief unless the user asks for detail. Do not use Markdown because
your response will be spoken aloud. Always use get_current_time when asked for
the current date or time; never guess it. When the caller asks to end the call,
use hangup immediately instead of only saying goodbye. Use read_variables when asked about the
sample order. Collect a concise request summary and urgency when the caller gives
them, then save those values in the intake section with update_variables. The
intake section has exactly two variables: summary is a string, and urgency is one
of low, normal, or high. Use those variable names exactly. Never claim a variable
update succeeded unless its tool result confirms success; correct or report a
failed update instead. Use prepare_background_report only when the caller
explicitly asks for a background report. A running result means the report was
accepted, not completed: acknowledge that it is running, continue the
conversation, and do not claim it is ready until the later completion arrives.
When the caller asks to speak with billing, use the transfer tool with the billing
destination. Do not claim the transfer completed unless the tool result confirms it.
When the caller asks to speak with a person or human support, use the transfer tool with
the human-support destination and give a concise reason that tells the destination who
is calling and what help they requested. Keep handling the conversation until the tool
confirms the transfer completed.
"""

sample_billing_prompt = """
You are a concise billing voice assistant. Respond naturally in plain text and do
not use Markdown because your response will be spoken aloud. Use read_variables
when the caller asks about the sample order. You may read the order section, but
you cannot read or change the reception intake section. When the caller asks to
end the call, use hangup immediately instead of only saying goodbye. When the caller
asks to return to reception, use the transfer tool with the reception destination. Do not
claim the transfer completed unless the tool result confirms it.
"""

sample_host_tools = %{
  "prepare_background_report" => Vxpipe.CallEngine.Tool.DelayedReport
}

config :vxpipe_calls, Vxpipe.Calls, registries: %{host_tools: sample_host_tools}

config :vxpipe_call_engine, Vxpipe.CallEngine.Application,
  agent_runtime: [context_compaction: [enabled: true]],
  speech_to_text: [
    providers: %{
      Vxpipe.Providers.Deepgram.STTSession => [
        enabled: true,
        media_ingress: [
          maximum_frames: 50,
          maximum_bytes: 262_144,
          maximum_age_ms: 2_000,
          maximum_consecutive_overflows: 5
        ]
      ],
      Vxpipe.Providers.Google.STTSession => [
        enabled: true,
        media_ingress: [
          maximum_frames: 50,
          maximum_bytes: 262_144,
          maximum_age_ms: 2_000,
          maximum_consecutive_overflows: 5
        ]
      ],
      Vxpipe.Providers.Cartesia.STTSession => [
        enabled: true,
        media_ingress: [
          maximum_frames: 50,
          maximum_bytes: 262_144,
          maximum_age_ms: 2_000,
          maximum_consecutive_overflows: 5
        ]
      ],
      Vxpipe.CallEngine.Provider.MorseCodeSTT.Session => [
        enabled: true,
        media_ingress: [
          maximum_frames: 50,
          maximum_bytes: 262_144,
          maximum_age_ms: 2_000,
          maximum_consecutive_overflows: 5
        ]
      ],
      Vxpipe.Providers.ElevenLabs.STTSession => [
        enabled: true,
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
    providers: %{
      Vxpipe.Providers.Deepgram.TTSSession => [
        enabled: true,
        maximum_requests: 4
      ],
      Vxpipe.Providers.Rime.TTSSession => [
        enabled: true,
        maximum_requests: 4
      ],
      Vxpipe.Providers.Google.TTSSession => [
        enabled: true,
        maximum_requests: 4
      ],
      Vxpipe.Providers.Cartesia.TTSSession => [
        enabled: true,
        maximum_requests: 4
      ],
      Vxpipe.Providers.ElevenLabs.TTSSession => [
        enabled: true,
        maximum_requests: 4
      ],
      Vxpipe.CallEngine.Provider.MorseCodeTTS.Session => [
        enabled: true,
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
        call_spec: %{
          schema_version: "20260915.01",
          wait_sounds: %{},
          name: "Development sample",
          entry_caller: "caller",
          entry_receiver: "reception",
          defaults: %{
            capabilities: %{
              speech_to_text: %{
                provider: "deepgram",
                model: "flux-general-en",
                options: %{encoding: "opus", sample_rate: 48_000}
              },
              model_inference: %{provider: "google", model: "gemini-3.5-flash-lite"},
              text_to_speech: %{
                provider: "deepgram",
                model: "flux",
                options: %{voice: "haley"}
              }
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
            "reception" => %{
              type: "agent",
              description: "Development reception assistant",
              prompt: sample_reception_prompt,
              transfer_history: %{mode: "last_n_spoken", turns: 4},
              first_message: %{mode: "wait_for_input"},
              tools: %{
                "get_current_time" => %{type: "platform", tool: "get_current_time"},
                "hangup" => %{type: "platform", tool: "hangup"},
                "prepare_background_report" => %{
                  type: "host",
                  tool: "prepare_background_report",
                  conversation_mode: "non_blocking"
                }
              },
              transfers: ["billing", "human-support"],
              variable_permissions: %{
                "order" => ["read"],
                "intake" => ["read", "write"]
              }
            },
            "billing" => %{
              type: "agent",
              description: "Development billing assistant",
              prompt: sample_billing_prompt,
              transfer_history: %{mode: "all_spoken"},
              first_message: %{mode: "fixed", text: "Billing is ready. How can I help?"},
              tools: %{
                "get_current_time" => %{type: "platform", tool: "get_current_time"},
                "hangup" => %{type: "platform", tool: "hangup"}
              },
              transfers: ["reception"],
              variable_permissions: %{
                "order" => ["read"]
              }
            },
            "human-support" => %{
              type: "human",
              description: "Browser transfer destination",
              connection: %{service: "web", mode: "receive", admission: "transfer"},
              transfer_notice: "This is a development sample call."
            }
          },
          limits: %{max_duration_ms: 1_800_000}
        },
        host_tools: sample_host_tools
      ]
    ]
  ]

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
