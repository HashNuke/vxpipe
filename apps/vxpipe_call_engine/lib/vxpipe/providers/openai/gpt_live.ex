defmodule Vxpipe.Providers.OpenAI.GPTLive do
  @moduledoc "Pure GPT-Live configuration and bounded WebSocket event codec."

  @endpoint "wss://api.openai.com/v1/live/sessions"
  @model "gpt-live-1"
  @voice_pattern ~r/\A[A-Za-z][A-Za-z0-9_-]*\z/
  @backend_pattern ~r/\A[A-Za-z0-9][A-Za-z0-9._-]*\z/
  @maximum_message_bytes 262_144
  @maximum_audio_bytes 65_536
  @maximum_text_bytes 65_536

  @enforce_keys [:api_key, :model, :voice, :backend_model]
  @derive {Inspect, only: [:model, :voice, :backend_model]}
  defstruct @enforce_keys ++
              [
                endpoint: @endpoint,
                input_sample_rate: 24_000,
                output_sample_rate: 24_000,
                system_prompt: "",
                tools: []
              ]

  def public_options(options) when is_list(options) do
    with true <- Keyword.keyword?(options),
         true <- length(options) == length(Enum.uniq(Keyword.keys(options))),
         {:ok, options} <-
           Keyword.validate(options,
             model: @model,
             voice: "marin",
             backend_model: "gpt-5",
             input_sample_rate: 24_000,
             output_sample_rate: 24_000
           ),
         @model <- Keyword.fetch!(options, :model),
         voice when is_binary(voice) <- Keyword.fetch!(options, :voice),
         true <- byte_size(voice) in 1..64 and Regex.match?(@voice_pattern, voice),
         backend when is_binary(backend) <- Keyword.fetch!(options, :backend_model),
         true <- byte_size(backend) in 1..128 and Regex.match?(@backend_pattern, backend),
         24_000 <- Keyword.fetch!(options, :input_sample_rate),
         24_000 <- Keyword.fetch!(options, :output_sample_rate) do
      {:ok,
       %{
         model: @model,
         voice: voice,
         backend_model: backend,
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
         api_key when is_binary(api_key) <- Keyword.get(options, :api_key),
         true <- byte_size(api_key) in 1..8_192,
         true <- Regex.match?(~r/\A[\x21-\x7E]+\z/, api_key),
         prompt = Keyword.get(options, :system_prompt, ""),
         tools = Keyword.get(options, :tools, []),
         :ok <- validate_agent_config(prompt, tools) do
      {:ok,
       struct(
         __MODULE__,
         Map.merge(public, %{api_key: api_key, system_prompt: prompt, tools: tools})
       )}
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  def new(_options), do: {:error, :invalid_configuration}

  def validate(%__MODULE__{endpoint: @endpoint} = config) do
    options = config |> Map.from_struct() |> Map.delete(:endpoint) |> Map.to_list()

    case new(options) do
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

  def connection_options(%__MODULE__{} = config),
    do: %{url: config.endpoint, headers: [{"authorization", "Bearer " <> config.api_key}]}

  def start(%__MODULE__{} = config, history) when is_list(history) do
    %{
      "type" => "session.start",
      "session" => %{
        "model" => config.model,
        "instructions" => config.system_prompt,
        "input" => Enum.map(history, &history_message/1),
        "audio" => %{
          "format" => %{"type" => "audio/pcm", "rate" => 24_000},
          "output" => %{"voice" => config.voice}
        },
        "delegation" => %{
          "type" => "responses",
          "responses" => %{"model" => config.backend_model, "tools" => openai_tools(config.tools)}
        },
        "store" => false
      }
    }
  end

  def audio_append(audio)
      when is_binary(audio) and byte_size(audio) > 0 and
             byte_size(audio) <= @maximum_audio_bytes and rem(byte_size(audio), 2) == 0,
      do: {:ok, %{"type" => "session.input_audio.append", "audio" => Base.encode64(audio)}}

  def audio_append(_audio), do: {:error, :invalid_audio}

  def commentary(text), do: context_append("session.commentary.append", text)
  def instructions(text), do: context_append("session.instructions.append", text)
  def thinking(text), do: context_append("session.thinking.append", text)

  def hold(true), do: %{"type" => "session.input_audio.mute"}
  def hold(false), do: %{"type" => "session.input_audio.unmute"}

  def tool_output(call_id, result) when is_binary(call_id) and byte_size(call_id) in 1..256 do
    output = JSON.encode!(result)

    if byte_size(output) <= @maximum_text_bytes do
      {:ok,
       %{
         "type" => "response.item.create",
         "item" => %{"type" => "function_call_output", "call_id" => call_id, "output" => output}
       }}
    else
      {:error, :invalid_tool_result}
    end
  rescue
    _exception -> {:error, :invalid_tool_result}
  end

  def tool_output(_call_id, _result), do: {:error, :invalid_tool_result}

  def response_create, do: %{"type" => "response.create"}
  def close, do: %{"type" => "session.close"}

  def decode(payload) when is_binary(payload) and byte_size(payload) <= @maximum_message_bytes do
    case JSON.decode(payload) do
      {:ok, %{"type" => type} = message} when is_binary(type) -> decode_message(type, message)
      _invalid -> {:error, :invalid_message}
    end
  end

  def decode(_payload), do: {:error, :invalid_message}

  defp openai_tools(tools) do
    Enum.map(tools, fn tool ->
      %{
        "type" => "function",
        "name" => Map.fetch!(tool, "name"),
        "description" => Map.fetch!(tool, "description"),
        "parameters" => Map.fetch!(tool, "parametersJsonSchema")
      }
    end)
  end

  defp history_message(%{"role" => "assistant", "content" => content} = message) do
    Map.put(message, "content", Enum.map(content, &Map.put(&1, "type", "output_text")))
  end

  defp history_message(message), do: message

  defp validate_agent_config(prompt, tools) do
    with true <- is_binary(prompt) and byte_size(prompt) <= @maximum_text_bytes,
         true <- String.valid?(prompt),
         true <- is_list(tools) and length(tools) <= 64,
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
       when map_size(tool) == 3 and is_binary(name) and is_binary(description) do
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
  rescue
    _exception -> false
  end

  defp valid_tool?(_tool), do: false

  defp context_append(type, text)
       when is_binary(text) and byte_size(text) in 1..2_000 do
    if String.valid?(text),
      do: {:ok, %{"type" => type, "content" => text, "delegation_id" => nil}},
      else: {:error, :invalid_text}
  end

  defp context_append(_type, _text), do: {:error, :invalid_text}

  defp decode_message("session.started", %{"session" => %{"id" => id}})
       when is_binary(id) and byte_size(id) in 1..256,
       do: {:ok, {:started, id}}

  defp decode_message(type, %{"delta" => text, "start_ms" => start_ms, "end_ms" => end_ms})
       when type in ["session.input_transcript.delta", "session.output_transcript.delta"] and
              is_binary(text) and byte_size(text) <= @maximum_text_bytes and
              is_integer(start_ms) and is_integer(end_ms) and start_ms >= 0 and end_ms >= start_ms do
    if String.valid?(text) do
      kind =
        if type == "session.input_transcript.delta", do: :input_fragment, else: :output_fragment

      {:ok, {kind, %{text: text, start_ms: start_ms, end_ms: end_ms}}}
    else
      {:error, :invalid_message}
    end
  end

  defp decode_message("session.output_audio.delta", %{"delta" => encoded})
       when is_binary(encoded) do
    with {:ok, pcm} <- Base.decode64(encoded),
         true <- byte_size(pcm) > 0 and byte_size(pcm) <= @maximum_audio_bytes,
         true <- rem(byte_size(pcm), 2) == 0 do
      {:ok, {:output_audio, pcm}}
    else
      _invalid -> {:error, :invalid_message}
    end
  end

  defp decode_message("session.delegation.created", %{
         "delegation" => %{"id" => id, "target" => target} = delegation
       })
       when is_binary(id) and byte_size(id) in 1..256 and is_binary(target) do
    {:ok, {:delegation, id, target, Map.get(delegation, "response_id")}}
  end

  defp decode_message("response.event", %{"delegation_id" => id, "event" => event})
       when is_binary(id) and byte_size(id) in 1..256 and is_map(event),
       do: {:ok, {:response_event, id, event}}

  defp decode_message("session.usage.updated", %{"usage" => %{"seconds" => seconds}})
       when is_number(seconds) and seconds >= 0,
       do: {:ok, {:voice_usage, seconds}}

  defp decode_message("session.closed", %{"reason" => reason} = message)
       when reason in [
              "close_requested",
              "remote_hangup",
              "content",
              "expired",
              "connection_lost"
            ],
       do: {:ok, {:closed, reason, Map.get(message, "usage")}}

  defp decode_message("error", %{"error" => %{} = error}), do: {:ok, {:error, error}}

  defp decode_message(type, message)
       when type in [
              "session.input_audio.muted",
              "session.input_audio.unmuted",
              "session.instructions.appended",
              "session.thinking.appended",
              "session.commentary.appended"
            ],
       do: {:ok, {:acknowledged, type, Map.get(message, "client_event_id")}}

  defp decode_message(_type, _message), do: {:error, :invalid_message}
end
