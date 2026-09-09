defmodule Vxpipe.CallEngine.Provider.MorseCodeSTT do
  @moduledoc false

  @behaviour Vxpipe.CallEngine.Provider.SpeechToText

  alias Vxpipe.CallEngine.Provider.MorseCode.Config
  alias Vxpipe.CallEngine.Provider.SpeechToText.Signal

  @maximum_identifier_bytes 128
  @maximum_message_bytes 65_536
  @maximum_text_bytes 4_096

  @impl true
  def new(options) when is_list(options), do: Config.new(options)
  def new(_options), do: {:error, :invalid_configuration}

  @impl true
  def connection_options(%Config{} = config), do: %{config: config}

  @impl true
  def media_format(%Config{} = config) do
    %{codec: :linear16, sample_rate: config.sample_rate}
  end

  @impl true
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

  defp decode_message(%{
         "type" => "Connected",
         "request_id" => request_id,
         "sequence_id" => sequence
       }) do
    if valid_identifier?(request_id) and valid_sequence?(sequence) do
      {:ok, %Signal{kind: :connected, request_id: request_id, provider_sequence: sequence}}
    else
      {:error, :invalid_message}
    end
  end

  defp decode_message(
         %{
           "type" => "TurnInfo",
           "event" => event,
           "request_id" => request_id,
           "sequence_id" => sequence,
           "turn_index" => turn_index,
           "transcript" => transcript
         } = message
       ) do
    with {:ok, kind} <- turn_kind(event),
         true <- valid_identifier?(request_id),
         true <- valid_sequence?(sequence),
         true <- valid_sequence?(turn_index),
         true <- valid_text?(transcript),
         {:ok, trigger} <- trigger(kind, message) do
      {:ok,
       %Signal{
         kind: kind,
         provider_sequence: sequence,
         provider_turn_index: turn_index,
         request_id: request_id,
         text: transcript,
         end_of_turn_confidence: if(kind == :turn_ended, do: 1.0, else: nil),
         trigger: trigger
       }}
    else
      {:ignore, _reason} = ignored -> ignored
      _invalid -> {:error, :invalid_message}
    end
  end

  defp decode_message(%{
         "type" => "Error",
         "sequence_id" => sequence,
         "code" => code
       }) do
    if valid_sequence?(sequence) and valid_identifier?(code) do
      {:ok, %Signal{kind: :failed, provider_sequence: sequence, provider_code: code}}
    else
      {:error, :invalid_message}
    end
  end

  defp decode_message(%{"type" => type}) when type in ["Connected", "TurnInfo", "Error"],
    do: {:error, :invalid_message}

  defp decode_message(%{"type" => _type}), do: {:ignore, :unknown_message}
  defp decode_message(_message), do: {:error, :invalid_message}

  defp turn_kind("StartOfTurn"), do: {:ok, :turn_started}
  defp turn_kind("Update"), do: {:ok, :transcript_updated}
  defp turn_kind("EndOfTurn"), do: {:ok, :turn_ended}
  defp turn_kind(_event), do: {:ignore, :unknown_turn_event}

  defp trigger(:turn_ended, %{"trigger" => "morse_end_gap"}),
    do: {:ok, "morse_end_gap"}

  defp trigger(:turn_ended, _message), do: {:error, :missing_trigger}
  defp trigger(_kind, _message), do: {:ok, nil}

  defp valid_identifier?(value) do
    is_binary(value) and byte_size(value) > 0 and
      byte_size(value) <= @maximum_identifier_bytes and String.valid?(value)
  end

  defp valid_sequence?(value), do: is_integer(value) and value >= 0

  defp valid_text?(value) do
    is_binary(value) and byte_size(value) <= @maximum_text_bytes and String.valid?(value)
  end
end
