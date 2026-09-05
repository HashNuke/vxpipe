import Config

config :vxpipe_call_engine, Vxpipe.CallEngine.Application,
  model_inference: [
    enabled: true,
    provider: Vxpipe.CallEngine.Provider.ReqLLM,
    provider_options: [
      model: "google:gemini-3.5-flash-lite",
      streaming: true,
      generation_options: [
        temperature: 0.2,
        max_tokens: 256,
        receive_timeout: 25_000,
        total_timeout: 25_000
      ]
    ],
    system_prompt: """
    You are a concise, helpful voice assistant. Respond naturally in plain text.
    Keep replies brief unless the user asks for detail. Do not use Markdown because
    your response will be spoken aloud. Always use get_current_time when asked for
    the current date or time; never guess it.
    """,
    maximum_context_turns: 8,
    maximum_pending_requests: 4,
    maximum_output_bytes: 65_536,
    tools: [Vxpipe.CallEngine.Tool.CurrentTime],
    maximum_tool_result_bytes: 16_384,
    maximum_tool_rounds: 2,
    request_timeout_ms: 30_000
  ],
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
  ],
  text_to_speech: [
    enabled: true,
    provider: Vxpipe.CallEngine.Provider.Deepgram.FluxTextToSpeech,
    provider_options: [
      model: "flux-haley-en",
      encoding: :linear16,
      sample_rate: 48_000
    ],
    transport: {Vxpipe.CallEngine.Provider.Deepgram.FluxTextToSpeechSocket, []},
    maximum_requests: 4
  ]

config :vxpipe_gateway, Vxpipe.Gateway.Application,
  http: [
    enabled: true,
    room_creation: [
      enabled: true,
      agent: :model_inference,
      principal: [
        tenant_id: "tenant-development",
        actor_id: "actor-samples",
        scopes: ["rooms:create", "rooms:join"]
      ]
    ]
  ]
