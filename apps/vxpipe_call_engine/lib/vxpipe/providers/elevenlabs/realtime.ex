defmodule Vxpipe.Providers.ElevenLabs.Realtime do
  @moduledoc "Pure configuration and bounded wire codec for ElevenLabs Realtime models."

  alias Vxpipe.CallEngine.Speech.Model
  alias Vxpipe.Providers.APIKeyCredential

  @enforce_keys [:api_key, :model, :voice]
  @derive {Inspect, only: [:model, :voice]}
  defstruct @enforce_keys ++ [system_prompt: "", tools: []]

  def models do
    [
      Model.new(
        "eleven_realtime_v1_mini",
        "Eleven Realtime v1 Mini",
        true,
        Model.free_voice("brian")
      ),
      Model.new(
        "eleven_realtime_v1_max",
        "Eleven Realtime v1 Max",
        false,
        Model.free_voice("brian")
      )
    ]
  end

  def public_options(options) when is_list(options) do
    with true <- Keyword.keyword?(options),
         true <- length(options) == length(Enum.uniq(Keyword.keys(options))),
         {:ok, options} <-
           Keyword.validate(options,
             model: "eleven_realtime_v1_mini",
             voice: "brian",
             turn_control: "provider"
           ),
         model = Keyword.fetch!(options, :model),
         true <- Model.supported?(models(), model),
         voice = Keyword.fetch!(options, :voice),
         true <-
           is_binary(voice) and byte_size(voice) in 1..64 and
             Regex.match?(~r/\A[A-Za-z0-9_-]+\z/, voice),
         "provider" <- Keyword.fetch!(options, :turn_control) do
      {:ok,
       %{
         model: model,
         voice: voice,
         turn_control: "provider",
         input_sample_rate: 24_000,
         output_sample_rate: 24_000
       }}
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  def public_options(_options), do: {:error, :invalid_configuration}

  def new(options) when is_list(options) do
    with true <- Keyword.keyword?(options),
         true <- length(options) == length(Enum.uniq(Keyword.keys(options))),
         {:ok, public} <-
           public_options(Keyword.drop(options, [:api_key, :system_prompt, :tools])),
         key = Keyword.get(options, :api_key),
         :ok <- APIKeyCredential.validate("api_key", %{"api_key" => key}),
         prompt = Keyword.get(options, :system_prompt, ""),
         tools = Keyword.get(options, :tools, []),
         :ok <- validate_agent_config(prompt, tools) do
      {:ok,
       %__MODULE__{
         api_key: key,
         model: public.model,
         voice: public.voice,
         system_prompt: prompt,
         tools: tools
       }}
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  def new(_options), do: {:error, :invalid_configuration}

  def validate(%__MODULE__{} = config) do
    case new(Map.to_list(Map.from_struct(config))) do
      {:ok, ^config} -> :ok
      _invalid -> {:error, :invalid_configuration}
    end
  end

  def validate(_config), do: {:error, :invalid_configuration}

  def pcm_format do
    %{
      encoding: :linear16,
      container: :raw,
      sample_rate: 24_000,
      channels: 1,
      byte_order: :little,
      signed?: true
    }
  end

  def acknowledged?(config, session) do
    get_in(session, ["model"]) == config.model and
      get_in(session, ["audio", "input", "format", "type"]) == "audio/pcm" and
      get_in(session, ["audio", "input", "format", "rate"]) == 24_000 and
      is_map(get_in(session, ["audio", "input", "transcription"])) and
      get_in(session, ["audio", "output", "format", "type"]) == "audio/pcm" and
      get_in(session, ["audio", "input", "turn_detection", "type"]) == "semantic_vad" and
      get_in(session, ["audio", "input", "turn_detection", "create_response"]) == true and
      get_in(session, ["audio", "input", "turn_detection", "interrupt_response"]) == false
  rescue
    _malformed -> false
  end

  def session(%__MODULE__{} = config) do
    %{
      "type" => "realtime",
      "model" => config.model,
      "instructions" => config.system_prompt,
      "output_modalities" => ["audio"],
      "audio" => %{
        "input" => %{
          "format" => %{"type" => "audio/pcm", "rate" => 24_000},
          "transcription" => %{},
          # ElevenLabs owns native turn detection and response generation.
          # Room policy remains the interruption owner.
          "turn_detection" => %{
            "type" => "semantic_vad",
            "create_response" => true,
            "interrupt_response" => false
          }
        },
        "output" => %{"format" => %{"type" => "audio/pcm"}, "voice" => config.voice}
      },
      "tools" => Enum.map(config.tools, &tool/1)
    }
  end

  def audio(pcm)
      when is_binary(pcm) and byte_size(pcm) in 2..65_536 and rem(byte_size(pcm), 2) == 0,
      do: {:ok, %{"type" => "input_audio_buffer.append", "audio" => Base.encode64(pcm)}}

  def audio(_pcm), do: {:error, :invalid_audio}

  def text(id, text) when is_binary(text) and byte_size(text) in 1..65_536 do
    if String.valid?(text),
      do:
        {:ok,
         %{
           "type" => "conversation.item.create",
           "item" => %{
             "id" => id,
             "type" => "message",
             "role" => "user",
             "content" => [%{"type" => "input_text", "text" => text}]
           }
         }},
      else: {:error, :invalid_text}
  end

  def text(_id, _text), do: {:error, :invalid_text}

  def response(token, instructions \\ nil) do
    response = %{"metadata" => %{"vxpipe_response" => token}}

    response =
      if instructions, do: Map.put(response, "instructions", instructions), else: response

    %{"type" => "response.create", "response" => response}
  end

  def cancel(id), do: %{"type" => "response.cancel", "response_id" => id}

  def tool_result(id, result) do
    with true <- :erlang.external_size(result) <= 131_072,
         encoded = JSON.encode!(result),
         true <- byte_size(encoded) <= 65_536 do
      {:ok,
       %{
         "type" => "conversation.item.create",
         "item" => %{"type" => "function_call_output", "call_id" => id, "output" => encoded}
       }}
    else
      _invalid -> {:error, :invalid_tool_result}
    end
  rescue
    _exception -> {:error, :invalid_tool_result}
  end

  def decode(payload) when is_binary(payload) and byte_size(payload) <= 262_144 do
    case JSON.decode(payload) do
      {:ok, %{"type" => type} = message} when is_binary(type) -> decode_event(type, message)
      _invalid -> {:error, :invalid_message}
    end
  end

  def decode(_payload), do: {:error, :invalid_message}

  defp decode_event("error", _message), do: {:error, :provider_error}

  defp decode_event(type, %{"session" => %{"model" => model} = session})
       when type in ["session.created", "session.updated"],
       do: {:ok, {:session, model, session}}

  defp decode_event(type, %{"item_id" => id})
       when type in ["input_audio_buffer.speech_started", "input_audio_buffer.speech_stopped"] and
              is_binary(id) and byte_size(id) in 1..256 do
    kind =
      if type == "input_audio_buffer.speech_started", do: :speech_started, else: :speech_stopped

    {:ok, {kind, id}}
  end

  defp decode_event("conversation.item.input_audio_transcription.completed", %{
         "item_id" => id,
         "transcript" => text
       })
       when is_binary(id) and byte_size(id) in 1..256 and is_binary(text) and
              byte_size(text) <= 65_536,
       do: {:ok, {:input_transcript, id, text}}

  defp decode_event("response.created", %{"response" => %{"id" => id} = response})
       when is_binary(id) and byte_size(id) in 1..256 do
    case Map.get(response, "metadata") do
      nil -> {:ok, {:response_created, id, nil}}
      %{} = metadata -> {:ok, {:response_created, id, Map.get(metadata, "vxpipe_response")}}
      _invalid -> {:error, :invalid_message}
    end
  end

  defp decode_event(type, %{"response_id" => id, "delta" => encoded})
       when type in ["response.output_audio.delta", "response.audio.delta"] and is_binary(id) and
              byte_size(id) in 1..256 and is_binary(encoded) do
    with {:ok, pcm} <- Base.decode64(encoded),
         true <- byte_size(pcm) in 2..131_072 and rem(byte_size(pcm), 2) == 0 do
      {:ok, {:audio, id, pcm}}
    else
      _invalid -> {:error, :invalid_message}
    end
  end

  defp decode_event(type, %{"response_id" => id, "transcript" => text})
       when type in ["response.output_audio_transcript.done", "response.audio_transcript.done"] and
              is_binary(id) and byte_size(id) in 1..256 and is_binary(text) and
              byte_size(text) <= 65_536,
       do: {:ok, {:output_transcript, id, text}}

  defp decode_event("response.done", %{"response" => %{"id" => id, "status" => status}})
       when is_binary(id) and byte_size(id) in 1..256 and
              status in ["completed", "cancelled", "failed", "incomplete"],
       do: {:ok, {:response_done, id, status}}

  defp decode_event("response.function_call_arguments.done", %{
         "response_id" => response,
         "call_id" => id,
         "name" => name,
         "arguments" => arguments
       })
       when is_binary(response) and byte_size(response) in 1..256 and is_binary(id) and
              byte_size(id) in 1..256 and
              is_binary(name) and byte_size(name) in 1..256 and is_binary(arguments) and
              byte_size(arguments) <= 65_536 do
    case JSON.decode(arguments) do
      {:ok, %{} = arguments} -> {:ok, {:tool_call, response, id, name, arguments}}
      _invalid -> {:error, :invalid_message}
    end
  end

  defp decode_event(type, _message)
       when type in [
              "session.created",
              "session.updated",
              "input_audio_buffer.speech_started",
              "input_audio_buffer.speech_stopped",
              "conversation.item.input_audio_transcription.completed",
              "conversation.item.input_audio_transcription.failed",
              "response.created",
              "response.done",
              "response.output_audio.delta",
              "response.audio.delta",
              "response.output_audio_transcript.done",
              "response.audio_transcript.done",
              "response.function_call_arguments.done"
            ],
       do: {:error, :invalid_message}

  defp decode_event(_type, _message), do: {:ok, :ignored}

  defp tool(tool) do
    %{
      "type" => "function",
      "name" => Map.fetch!(tool, "name"),
      "description" => Map.fetch!(tool, "description"),
      "parameters" => Map.fetch!(tool, "parametersJsonSchema")
    }
  end

  defp validate_agent_config(prompt, tools) do
    with true <- is_binary(prompt) and String.valid?(prompt) and byte_size(prompt) <= 65_536,
         true <- is_list(tools) and length(tools) <= 64,
         true <- :erlang.external_size({prompt, tools}) <= 131_072,
         true <- Enum.all?(tools, &valid_tool?/1),
         names = Enum.map(tools, &Map.fetch!(&1, "name")),
         true <- Enum.uniq(names) == names,
         true <- byte_size(JSON.encode!(%{"prompt" => prompt, "tools" => tools})) <= 131_072 do
      :ok
    else
      _invalid -> {:error, :invalid_configuration}
    end
  rescue
    _exception -> {:error, :invalid_configuration}
  end

  defp valid_tool?(
         %{
           "name" => name,
           "description" => description,
           "parametersJsonSchema" => %{"type" => "object"} = schema
         } = tool
       )
       when map_size(tool) == 3 and is_binary(name) do
    Regex.match?(~r/\A[A-Za-z0-9_-]+\z/, name) and
      JSON.decode!(JSON.encode!(schema)) == schema and
      match?(
        {:ok, _descriptor},
        Vxpipe.AgentRuntime.ToolDescriptor.new(
          name: name,
          description: description,
          input_schema: schema,
          binding: :configuration
        )
      )
  end

  defp valid_tool?(_tool), do: false
end
