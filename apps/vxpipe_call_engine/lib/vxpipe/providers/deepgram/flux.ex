defmodule Vxpipe.Providers.Deepgram.Flux do
  @moduledoc false

  alias Vxpipe.CallEngine.Provider.SpeechToText.Signal

  @endpoint "wss://api.deepgram.com/v2/listen"
  @maximum_message_bytes 262_144
  @maximum_request_id_bytes 128
  @maximum_transcript_bytes 65_536
  @maximum_trigger_bytes 64
  @encodings [:linear16, :opus]

  @derive {Inspect, only: [:model, :encoding, :sample_rate]}
  @enforce_keys [:api_key, :model, :encoding, :sample_rate]
  defstruct @enforce_keys ++ [endpoint: @endpoint]

  @type t :: %__MODULE__{
          api_key: String.t(),
          endpoint: String.t(),
          model: String.t(),
          encoding: :linear16 | :opus,
          sample_rate: pos_integer()
        }

  alias Vxpipe.CallEngine.Speech.Model

  def models do
    [
      Model.new("flux-general-en", "Flux General English", false),
      Model.new("flux-general-multi", "Flux General Multilingual", true)
    ]
    |> Enum.map(&Map.put(&1, :options, %{"encoding" => "linear16", "sample_rate" => 48_000}))
  end

  def new(options) when is_list(options) do
    api_key = Keyword.get(options, :api_key)
    model = Keyword.get(options, :model, "flux-general-en")
    encoding = Keyword.get(options, :encoding)
    sample_rate = Keyword.get(options, :sample_rate)

    if valid_api_key?(api_key) and validate_options(options) == :ok do
      {:ok,
       %__MODULE__{
         api_key: api_key,
         model: model,
         encoding: encoding,
         sample_rate: sample_rate
       }}
    else
      {:error, :invalid_configuration}
    end
  end

  @doc false
  def validate_options(options) do
    model = Keyword.get(options, :model, "flux-general-en")
    encoding = Keyword.get(options, :encoding)
    sample_rate = Keyword.get(options, :sample_rate)

    if Model.supported?(models(), model) and encoding in @encodings and
         is_integer(sample_rate) and sample_rate > 0,
       do: :ok,
       else: {:error, :invalid_configuration}
  end

  def connection_options(%__MODULE__{} = config) do
    query =
      URI.encode_query(%{
        "encoding" => encoding(config.encoding),
        "model" => config.model,
        "sample_rate" => Integer.to_string(config.sample_rate)
      })

    %{
      url: config.endpoint <> "?" <> query,
      headers: [{"Authorization", "Token " <> config.api_key}]
    }
  end

  def media_format(%__MODULE__{} = config) do
    %{codec: config.encoding, sample_rate: config.sample_rate}
  end

  def usage_identity(%__MODULE__{} = config) do
    [name: "deepgram", model: config.model]
  end

  def decode(payload) when is_binary(payload) do
    if byte_size(payload) > @maximum_message_bytes do
      {:error, :message_too_large}
    else
      case JSON.decode(payload) do
        {:ok, message} when is_map(message) -> decode_message(message)
        {:ok, _other} -> {:error, :invalid_message}
        {:error, _reason} -> {:error, :invalid_json}
      end
    end
  end

  @spec maximum_message_bytes() :: pos_integer()
  def maximum_message_bytes, do: @maximum_message_bytes

  defp decode_message(%{
         "type" => "Connected",
         "request_id" => request_id,
         "sequence_id" => sequence
       }) do
    if valid_bounded_string?(request_id, @maximum_request_id_bytes) and valid_sequence?(sequence) do
      {:ok,
       %Signal{
         kind: :connected,
         request_id: request_id,
         provider_sequence: sequence
       }}
    else
      {:error, :invalid_message}
    end
  end

  defp decode_message(
         %{
           "type" => "TurnInfo",
           "request_id" => request_id,
           "sequence_id" => sequence,
           "event" => event,
           "turn_index" => turn_index,
           "audio_window_start" => window_start,
           "audio_window_end" => window_end,
           "transcript" => transcript,
           "words" => words,
           "end_of_turn_confidence" => confidence
         } = message
       ) do
    with {:ok, kind} <- turn_kind(event),
         true <- valid_bounded_string?(request_id, @maximum_request_id_bytes),
         true <- valid_sequence?(sequence),
         true <- valid_sequence?(turn_index),
         true <- valid_number?(window_start),
         true <- valid_number?(window_end),
         true <- window_end >= window_start,
         {:ok, audio_duration_ms} <- audio_duration_ms(window_start, window_end),
         true <- valid_transcript?(transcript),
         true <- is_list(words),
         true <- valid_number?(confidence),
         {:ok, trigger} <- trigger(kind, message) do
      {:ok,
       %Signal{
         kind: kind,
         request_id: request_id,
         provider_sequence: sequence,
         provider_turn_index: turn_index,
         audio_duration_ms: audio_duration_ms,
         text: transcript,
         end_of_turn_confidence: confidence,
         trigger: trigger
       }}
    else
      {:ignore, :unknown_turn_event} -> {:ignore, :unknown_turn_event}
      _invalid -> {:error, :invalid_message}
    end
  end

  defp decode_message(%{
         "type" => "Error",
         "sequence_id" => sequence,
         "code" => code,
         "description" => description
       }) do
    if valid_sequence?(sequence) and
         valid_bounded_string?(code, Signal.maximum_provider_code_bytes()) and
         is_binary(description) do
      {:ok,
       %Signal{
         kind: :failed,
         provider_sequence: sequence,
         provider_code: code
       }}
    else
      {:error, :invalid_message}
    end
  end

  defp decode_message(%{"type" => type})
       when type in ["ConfigureSuccess", "ConfigureFailure"] do
    {:ignore, :configuration_message}
  end

  defp decode_message(%{"type" => type}) when type in ["Connected", "TurnInfo", "Error"] do
    {:error, :invalid_message}
  end

  defp decode_message(%{"type" => _type}), do: {:ignore, :unknown_message}
  defp decode_message(_message), do: {:error, :invalid_message}

  defp turn_kind("Update"), do: {:ok, :transcript_updated}
  defp turn_kind("StartOfTurn"), do: {:ok, :turn_started}
  defp turn_kind("EagerEndOfTurn"), do: {:ok, :eager_turn_ended}
  defp turn_kind("TurnResumed"), do: {:ok, :turn_resumed}
  defp turn_kind("EndOfTurn"), do: {:ok, :turn_ended}
  defp turn_kind(_event), do: {:ignore, :unknown_turn_event}

  defp trigger(:turn_ended, %{"trigger" => trigger}) do
    if valid_bounded_string?(trigger, @maximum_trigger_bytes) do
      {:ok, trigger}
    else
      {:error, :invalid_trigger}
    end
  end

  defp trigger(:turn_ended, _message), do: {:error, :missing_trigger}
  defp trigger(_kind, _message), do: {:ok, nil}

  defp encoding(:linear16), do: "linear16"
  defp encoding(:opus), do: "opus"

  defp valid_api_key?(value), do: is_binary(value) and byte_size(String.trim(value)) > 0

  defp valid_bounded_string?(value, maximum_bytes) do
    is_binary(value) and byte_size(value) > 0 and byte_size(value) <= maximum_bytes
  end

  defp valid_transcript?(value) do
    is_binary(value) and byte_size(value) <= @maximum_transcript_bytes
  end

  defp valid_sequence?(value), do: is_integer(value) and value >= 0
  defp valid_number?(value), do: is_number(value) and value >= 0

  defp audio_duration_ms(window_start, window_end) do
    milliseconds = round((window_end - window_start) * 1_000)

    if milliseconds >= 0,
      do: {:ok, milliseconds},
      else: {:error, :invalid_audio_window}
  end
end
