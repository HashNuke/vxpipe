defmodule Vxpipe.Providers.Google.STS do
  @moduledoc """
  Pure configuration and wire codec for the Gemini 3.8 Live speech-to-speech
  adapter.

  The message shapes below are this adapter's wire assumption, derived from the
  documented Live API families (setup, realtime input audio/text/activity,
  tool responses; server content audio/transcription/generation/turn
  completion, interruption, tool calls/cancellations, go-away, resumption
  updates and usage metadata). Tagged hosted and phone tests verify the
  exercised wire scenarios; ordinary tests use fixture payloads and fake
  sockets only. Broader continuity and history contracts retain separate gates.
  """

  @endpoint "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"
  @model "gemini-3.8-live"
  @maximum_message_bytes 262_144
  @maximum_audio_bytes 32_000
  @maximum_output_chunk_bytes 131_072
  @maximum_text_bytes 65_536
  @voice_pattern ~r/\A[A-Za-z][A-Za-z0-9_-]*\z/
  @turn_controls ["provider", "external"]

  @enforce_keys [:api_key, :model, :voice, :turn_control]
  @derive {Inspect, only: [:model, :voice, :turn_control]}
  defstruct @enforce_keys ++ [endpoint: @endpoint, system_prompt: "", tools: []]

  alias Vxpipe.CallEngine.Speech.Model

  def models do
    [
      Model.new("gemini-3.8-live", "Gemini 3.8 Live", true, Model.free_voice("Kore"))
    ]
  end

  def new(options) when is_list(options) do
    with true <- Keyword.keyword?(options),
         true <- length(Keyword.keys(options)) == length(Enum.uniq(Keyword.keys(options))),
         {:ok, public} <-
           public_options(Keyword.drop(options, [:api_key, :system_prompt, :tools])),
         api_key when is_binary(api_key) <- Keyword.get(options, :api_key),
         true <- byte_size(api_key) in 1..8_192,
         true <- Regex.match?(~r/\A[\x21-\x7E]+\z/, api_key),
         prompt = Keyword.get(options, :system_prompt, ""),
         tools = Keyword.get(options, :tools, []),
         :ok <- Vxpipe.Providers.Google.STSAgentConfig.validate(prompt, tools) do
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

  def public_options(options) when is_list(options) do
    with {:ok, options} <-
           Keyword.validate(options, model: @model, voice: "Kore", turn_control: "provider"),
         model <- Keyword.fetch!(options, :model),
         true <- Model.supported?(models(), model),
         voice when is_binary(voice) <- Keyword.fetch!(options, :voice),
         true <- byte_size(voice) in 1..64 and Regex.match?(@voice_pattern, voice),
         turn_control when is_binary(turn_control) <- Keyword.fetch!(options, :turn_control),
         true <- turn_control in @turn_controls do
      {:ok,
       %{
         model: model,
         voice: voice,
         turn_control: turn_control,
         input_sample_rate: 16_000,
         output_sample_rate: 24_000
       }}
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  def public_options(_options), do: {:error, :invalid_configuration}

  @doc "Raw mono linear16 format accepted and produced at the given rate."
  def pcm_format(sample_rate) when is_integer(sample_rate) and sample_rate > 0 do
    %{
      encoding: :linear16,
      container: :raw,
      sample_rate: sample_rate,
      channels: 1,
      byte_order: :little,
      signed?: true
    }
  end

  def connection_options(%__MODULE__{} = config),
    do: %{url: config.endpoint, headers: [{"x-goog-api-key", config.api_key}]}

  def setup(%__MODULE__{} = config) do
    %{
      "setup" => %{
        "model" => "models/" <> config.model,
        "generationConfig" => %{
          "responseModalities" => ["AUDIO"],
          "speechConfig" => %{
            "voiceConfig" => %{"prebuiltVoiceConfig" => %{"voiceName" => config.voice}}
          }
        },
        "inputAudioTranscription" => %{},
        "outputAudioTranscription" => %{},
        "sessionResumption" => %{},
        "contextWindowCompression" => %{"slidingWindow" => %{}},
        "systemInstruction" => %{"parts" => [%{"text" => config.system_prompt}]},
        "tools" =>
          if(config.tools == [], do: [], else: [%{"functionDeclarations" => config.tools}]),
        "realtimeInputConfig" => %{
          "automaticActivityDetection" => %{"disabled" => config.turn_control == "external"}
        }
      }
    }
  end

  def encode_audio(audio)
      when is_binary(audio) and byte_size(audio) > 0 and
             byte_size(audio) <= @maximum_audio_bytes and rem(byte_size(audio), 2) == 0 do
    {:ok,
     JSON.encode!(%{
       "realtimeInput" => %{
         "audio" => %{"data" => Base.encode64(audio), "mimeType" => "audio/pcm;rate=16000"}
       }
     })}
  end

  def encode_audio(_audio), do: {:error, :invalid_audio}

  def encode_text(text) when is_binary(text) do
    if String.valid?(text) and byte_size(text) in 1..@maximum_text_bytes do
      {:ok, JSON.encode!(%{"realtimeInput" => %{"text" => text}})}
    else
      {:error, :invalid_text}
    end
  end

  def encode_text(_text), do: {:error, :invalid_text}

  def encode_activity(boundary) when boundary in [:started, :ended] do
    key = if boundary == :started, do: "activityStart", else: "activityEnd"
    {:ok, JSON.encode!(%{"realtimeInput" => %{key => %{}}})}
  end

  def encode_activity(_boundary), do: {:error, :invalid_activity}

  def encode_tool_result(call_id, name, result)
      when is_binary(call_id) and is_binary(name) and is_map(result) do
    if byte_size(call_id) in 1..256 and byte_size(name) in 1..256 and
         byte_size(JSON.encode!(result)) <= @maximum_text_bytes do
      {:ok,
       JSON.encode!(%{
         "toolResponse" => %{
           "functionResponses" => [%{"id" => call_id, "name" => name, "response" => result}]
         }
       })}
    else
      {:error, :invalid_tool_result}
    end
  rescue
    _exception -> {:error, :invalid_tool_result}
  end

  def encode_tool_result(_call_id, _name, _result), do: {:error, :invalid_tool_result}

  def decode(payload) when is_binary(payload) and byte_size(payload) <= @maximum_message_bytes do
    case JSON.decode(payload) do
      {:ok, %{"error" => _error}} -> {:error, :provider_failure}
      {:ok, message} when is_map(message) -> decode_message(message)
      _invalid -> {:error, :invalid_message}
    end
  end

  def decode(_payload), do: {:error, :invalid_message}

  defp decode_message(message) do
    with {:ok, activity} <- voice_activity(message),
         {:ok, content} <- server_content(message),
         {:ok, tools} <- tool_calls(message),
         {:ok, cancellations} <- tool_cancellations(message),
         {:ok, control} <- control_events(message) do
      ready = if Map.has_key?(message, "setupComplete"), do: [:ready], else: []
      {:ok, ready ++ activity ++ content ++ tools ++ cancellations ++ control}
    end
  end

  defp server_content(%{"serverContent" => content}) when is_map(content) do
    with {:ok, transcripts} <- transcripts(content),
         {:ok, audio} <- output_audio(content),
         {:ok, boundaries} <- boundaries(content) do
      active? =
        Map.has_key?(content, "modelTurn") or Map.get(content, "generationComplete") == true or
          Map.get(content, "interrupted") == true

      activity = if active?, do: [:model_activity], else: []

      content_evidence =
        case content do
          %{"modelTurn" => %{"parts" => [_ | _]}} -> [:model_content]
          _other -> []
        end

      {:ok, activity ++ content_evidence ++ transcripts ++ audio ++ boundaries}
    end
  end

  defp server_content(%{"serverContent" => _content}), do: {:error, :invalid_message}
  defp server_content(_message), do: {:ok, []}

  defp voice_activity(%{"voiceActivity" => activity}) when is_map(activity) do
    with false <-
           Enum.any?(
             ["voiceActivityType", "voice_activity_type", "audio_offset"],
             &Map.has_key?(activity, &1)
           ),
         :ok <- activity_offset(activity) do
      # Raw Gemini JSON uses `type`; the Python MLDev converter renames it for
      # SDK consumers. SDK property names are not alternate wire versions.
      case Map.fetch(activity, "type") do
        {:ok, "ACTIVITY_START"} -> {:ok, [:activity_start]}
        {:ok, "ACTIVITY_END"} -> {:ok, [:activity_end]}
        {:ok, "TYPE_UNSPECIFIED"} -> {:ok, []}
        :error -> {:ok, []}
        _invalid -> {:error, :invalid_message}
      end
    else
      _invalid -> {:error, :invalid_message}
    end
  end

  defp voice_activity(%{"voiceActivity" => _invalid}), do: {:error, :invalid_message}
  defp voice_activity(_message), do: {:ok, []}

  # The SDK exposes an optional string. It is not a playback clock or controller
  # boundary timestamp; validate its wire type without inventing timing semantics.
  defp activity_offset(activity) do
    case Map.fetch(activity, "audioOffset") do
      :error ->
        :ok

      {:ok, offset} when is_binary(offset) and byte_size(offset) <= @maximum_text_bytes ->
        if String.valid?(offset), do: :ok, else: {:error, :invalid_message}

      _invalid ->
        {:error, :invalid_message}
    end
  end

  defp transcripts(content) do
    with {:ok, interim} <-
           transcript_text(content, "interimInputTranscription", :input_transcript),
         {:ok, input} <- transcript_text(content, "inputTranscription", :input_transcript),
         {:ok, output} <- transcript_text(content, "outputTranscription", :output_transcript),
         :ok <- validate_model_text(content) do
      {:ok, input_finality(interim, false) ++ input_finality(input, true) ++ output}
    end
  end

  defp input_finality(events, final?),
    do: Enum.map(events, fn {kind, text} -> {kind, text, final?} end)

  defp flag(content, key, event) do
    case Map.fetch(content, key) do
      :error -> {:ok, []}
      {:ok, true} -> {:ok, [event]}
      _invalid -> {:error, :invalid_message}
    end
  end

  defp transcript_text(content, key, event) do
    case Map.fetch(content, key) do
      :error ->
        {:ok, []}

      {:ok, %{"text" => text}}
      when is_binary(text) and byte_size(text) <= @maximum_text_bytes ->
        if String.valid?(text), do: {:ok, [{event, text}]}, else: {:error, :invalid_message}

      _invalid ->
        {:error, :invalid_message}
    end
  end

  # Model text (including thoughts) is not the selected audio transcription.
  defp validate_model_text(%{"modelTurn" => %{"parts" => parts}}) when is_list(parts) do
    Enum.reduce_while(parts, :ok, fn part, :ok ->
      case part do
        %{"text" => text}
        when is_binary(text) and byte_size(text) <= @maximum_text_bytes ->
          if String.valid?(text),
            do: {:cont, :ok},
            else: {:halt, {:error, :invalid_message}}

        %{"text" => _invalid} ->
          {:halt, {:error, :invalid_message}}

        _other ->
          {:cont, :ok}
      end
    end)
  end

  defp validate_model_text(%{"modelTurn" => _invalid}), do: {:error, :invalid_message}
  defp validate_model_text(_content), do: :ok

  defp output_audio(%{"modelTurn" => %{"parts" => parts}}) when is_list(parts) do
    Enum.reduce_while(parts, {:ok, []}, fn part, {:ok, events} ->
      case part do
        %{"inlineData" => %{"mimeType" => "audio/pcm;rate=24000", "data" => data}} ->
          case decode_audio_chunk(data) do
            {:ok, chunks} -> {:cont, {:ok, events ++ chunks}}
            {:error, _reason} = error -> {:halt, error}
          end

        %{"inlineData" => _invalid} ->
          {:halt, {:error, :invalid_message}}

        _other ->
          {:cont, {:ok, events}}
      end
    end)
  end

  defp output_audio(%{"modelTurn" => _invalid}), do: {:error, :invalid_message}
  defp output_audio(_content), do: {:ok, []}

  defp decode_audio_chunk(data) when is_binary(data) do
    with {:ok, pcm} <- Base.decode64(data),
         true <- byte_size(pcm) > 0 and byte_size(pcm) <= @maximum_message_bytes,
         true <- rem(byte_size(pcm), 2) == 0 do
      {:ok, Enum.map(split_audio(pcm), &{:audio, &1})}
    else
      _invalid -> {:error, :invalid_message}
    end
  end

  defp decode_audio_chunk(_data), do: {:error, :invalid_message}

  defp split_audio(pcm) when byte_size(pcm) <= @maximum_output_chunk_bytes, do: [pcm]

  defp split_audio(pcm) do
    <<chunk::binary-size(@maximum_output_chunk_bytes), rest::binary>> = pcm
    [chunk | split_audio(rest)]
  end

  defp boundaries(content) do
    with {:ok, generation} <- flag(content, "generationComplete", :generation_complete),
         {:ok, turn} <- model_completion(content),
         {:ok, interrupted} <- flag(content, "interrupted", :interrupted) do
      {:ok, generation ++ turn ++ interrupted}
    end
  end

  defp model_completion(%{"turnComplete" => true} = content) do
    case Map.fetch(content, "interactionStatus") do
      :error -> {:ok, [{:turn_complete, :omitted}]}
      {:ok, "IDLE"} -> {:ok, [{:turn_complete, :idle}]}
      {:ok, "IN_PROGRESS"} -> {:ok, [{:turn_complete, :in_progress}]}
      {:ok, "INTERACTION_STATUS_UNSPECIFIED"} -> {:ok, [{:turn_complete, :unknown}]}
      {:ok, "REQUIRES_ACTION"} -> {:ok, [{:turn_complete, :requires_action}]}
      _invalid -> {:error, :invalid_message}
    end
  end

  defp model_completion(%{"turnComplete" => false} = content) do
    if Map.has_key?(content, "interactionStatus"),
      do: {:error, :invalid_message},
      else: {:ok, []}
  end

  defp model_completion(content) do
    if Map.has_key?(content, "turnComplete") or Map.has_key?(content, "interactionStatus"),
      do: {:error, :invalid_message},
      else: {:ok, []}
  end

  defp tool_calls(%{"toolCall" => %{"functionCalls" => calls}}) when is_list(calls) do
    Enum.reduce_while(calls, {:ok, []}, fn call, {:ok, events} ->
      with %{"id" => id, "name" => name} when is_binary(id) and is_binary(name) <- call,
           true <- byte_size(id) in 1..256 and byte_size(name) in 1..256,
           args when is_map(args) <- Map.get(call, "args", %{}),
           true <- Vxpipe.CallEngine.Speech.ToolArguments.valid?(args) do
        {:cont, {:ok, events ++ [{:tool_call, id, name, args}]}}
      else
        _invalid -> {:halt, {:error, :invalid_message}}
      end
    end)
  end

  defp tool_calls(%{"toolCall" => _invalid}), do: {:error, :invalid_message}
  defp tool_calls(_message), do: {:ok, []}

  defp tool_cancellations(%{"toolCallCancellation" => %{"ids" => ids}}) when is_list(ids) do
    Enum.reduce_while(ids, {:ok, []}, fn id, {:ok, events} ->
      if is_binary(id) and byte_size(id) in 1..256,
        do: {:cont, {:ok, events ++ [{:tool_cancel, id}]}},
        else: {:halt, {:error, :invalid_message}}
    end)
  end

  defp tool_cancellations(%{"toolCallCancellation" => _invalid}),
    do: {:error, :invalid_message}

  defp tool_cancellations(_message), do: {:ok, []}

  defp control_events(message) do
    with {:ok, go_away} <- go_away(message),
         {:ok, resumption} <- resumption(message),
         {:ok, usage} <- usage(message) do
      {:ok, go_away ++ resumption ++ usage}
    end
  end

  defp go_away(%{"goAway" => %{"timeLeft" => left}}) when is_binary(left) do
    case Regex.run(~r/\A(\d{1,6})(?:\.(\d{1,9}))?s\z/, left) do
      [_, seconds] ->
        {:ok, [{:go_away, String.to_integer(seconds) * 1_000}]}

      [_, seconds, fraction] ->
        milliseconds = fraction |> String.pad_trailing(3, "0") |> String.slice(0, 3)
        {:ok, [{:go_away, String.to_integer(seconds) * 1_000 + String.to_integer(milliseconds)}]}

      _invalid ->
        {:error, :invalid_message}
    end
  end

  defp go_away(%{"goAway" => _invalid}), do: {:error, :invalid_message}
  defp go_away(_message), do: {:ok, []}

  defp resumption(%{"sessionResumptionUpdate" => %{"resumable" => false}}),
    do: {:ok, [{:resumption, nil}]}

  defp resumption(%{
         "sessionResumptionUpdate" => %{"newHandle" => handle, "resumable" => true}
       }) do
    if is_binary(handle) and byte_size(handle) in 1..1_024 do
      {:ok, [{:resumption, handle}]}
    else
      {:error, :invalid_message}
    end
  end

  defp resumption(%{"sessionResumptionUpdate" => _invalid}), do: {:error, :invalid_message}
  defp resumption(_message), do: {:ok, []}

  defp usage(%{"usageMetadata" => metadata}) when is_map(metadata),
    do: {:ok, [{:usage, metadata}]}

  defp usage(%{"usageMetadata" => _invalid}), do: {:error, :invalid_message}
  defp usage(_message), do: {:ok, []}
end
