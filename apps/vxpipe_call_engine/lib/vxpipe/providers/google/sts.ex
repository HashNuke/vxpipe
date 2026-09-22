defmodule Vxpipe.Providers.Google.STS do
  @moduledoc """
  Pure configuration and wire codec for the Gemini 3.8 Live speech-to-speech
  adapter.

  The message shapes below are this adapter's wire assumption, derived from the
  documented Live API families (setup, realtime input audio/text/activity,
  tool responses; server content audio/transcription/generation/turn
  completion, interruption, tool calls/cancellations, go-away, resumption
  updates and usage metadata). Hosted byte-level compatibility is NOT claimed
  here; it waits for the explicitly authorized tagged interoperability check.
  Ordinary tests use fixture payloads and fake sockets only.
  """

  @endpoint "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"
  @model "gemini-3.8-live"
  @maximum_message_bytes 262_144
  @maximum_audio_bytes 32_000
  @maximum_output_chunk_bytes 131_072
  @maximum_text_bytes 65_536
  @voice_pattern ~r/\A[A-Za-z][A-Za-z0-9_-]*\z/
  @turn_controls ["provider", "external", "hybrid"]

  @enforce_keys [:api_key, :model, :voice, :turn_control]
  @derive {Inspect, only: [:model, :voice, :turn_control]}
  defstruct @enforce_keys ++ [endpoint: @endpoint]

  def new(options) when is_list(options) do
    with {:ok, public} <- public_options(Keyword.drop(options, [:api_key])),
         api_key when is_binary(api_key) <- Keyword.get(options, :api_key),
         true <- byte_size(api_key) in 1..8_192,
         true <- Regex.match?(~r/\A[\x21-\x7E]+\z/, api_key) do
      {:ok, struct(__MODULE__, Map.merge(public, %{api_key: api_key}))}
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  def new(_options), do: {:error, :invalid_configuration}

  def public_options(options) when is_list(options) do
    with {:ok, options} <-
           Keyword.validate(options, model: @model, voice: "Kore", turn_control: "provider"),
         @model <- Keyword.fetch!(options, :model),
         voice when is_binary(voice) <- Keyword.fetch!(options, :voice),
         true <- byte_size(voice) in 1..64 and Regex.match?(@voice_pattern, voice),
         turn_control when is_binary(turn_control) <- Keyword.fetch!(options, :turn_control),
         true <- turn_control in @turn_controls do
      {:ok,
       %{
         model: @model,
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
        "automaticActivityDetection" => %{"disabled" => config.turn_control == "external"}
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
      {:ok,
       JSON.encode!(%{
         "clientContent" => %{
           "turns" => [%{"role" => "user", "parts" => [%{"text" => text}]}],
           "turnComplete" => true
         }
       })}
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

  def encode_interrupt do
    {:ok, JSON.encode!(%{"realtimeInput" => %{"activityEnd" => %{}}})}
  end

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
    with {:ok, content} <- server_content(message),
         {:ok, tools} <- tool_calls(message),
         {:ok, cancellations} <- tool_cancellations(message),
         {:ok, control} <- control_events(message) do
      ready = if Map.has_key?(message, "setupComplete"), do: [:ready], else: []
      {:ok, ready ++ content ++ tools ++ cancellations ++ control}
    end
  end

  defp server_content(%{"serverContent" => content}) when is_map(content) do
    with {:ok, activity} <- activity(content),
         {:ok, transcripts} <- transcripts(content),
         {:ok, audio} <- output_audio(content),
         {:ok, boundaries} <- boundaries(content) do
      {:ok, activity ++ transcripts ++ audio ++ boundaries}
    end
  end

  defp server_content(%{"serverContent" => _content}), do: {:error, :invalid_message}
  defp server_content(_message), do: {:ok, []}

  defp activity(%{"activityStart" => true} = content) do
    if map_size(Map.delete(content, "activityStart")) >= 0, do: {:ok, [:activity_start]}
  end

  defp activity(%{"activityStart" => _invalid}), do: {:error, :invalid_message}
  defp activity(_content), do: {:ok, []}

  defp transcripts(content) do
    with {:ok, activity_end} <- flag(content, "activityEnd", :activity_end),
         {:ok, input} <- transcript_text(content, "inputTranscription", :input_transcript),
         {:ok, output} <- transcript_text(content, "outputTranscription", :output_transcript),
         {:ok, turn_text} <- turn_texts(content) do
      {:ok, activity_end ++ input ++ output ++ turn_text}
    end
  end

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

  defp turn_texts(%{"modelTurn" => %{"parts" => parts}}) when is_list(parts) do
    Enum.reduce_while(parts, {:ok, []}, fn part, {:ok, events} ->
      case part do
        %{"text" => text}
        when is_binary(text) and byte_size(text) <= @maximum_text_bytes ->
          if String.valid?(text),
            do: {:cont, {:ok, events ++ [{:output_transcript, text}]}},
            else: {:halt, {:error, :invalid_message}}

        %{"text" => _invalid} ->
          {:halt, {:error, :invalid_message}}

        _other ->
          {:cont, {:ok, events}}
      end
    end)
  end

  defp turn_texts(%{"modelTurn" => _invalid}), do: {:error, :invalid_message}
  defp turn_texts(_content), do: {:ok, []}

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
         {:ok, turn} <- flag(content, "turnComplete", :turn_complete),
         {:ok, interrupted} <- flag(content, "interrupted", :interrupted) do
      {:ok, generation ++ turn ++ interrupted}
    end
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
