defmodule Vxpipe.Gateway.Telephony.Twilio.MediaPacketDecoder do
  @moduledoc false

  alias Vxpipe.CallEngine.Telephony.{Event, MediaPacket}
  alias Vxpipe.Gateway.Telephony.Twilio.{Identifier, MediaFields}

  @spec decode(keyword(), map()) :: {:ok, Event.t()} | {:error, :invalid_twilio_media_message}
  def decode(options, %{"media" => media} = message) when is_map(media) do
    with {:ok, stream_id} <- MediaFields.string(message, "streamSid"),
         true <- Identifier.stream_sid?(stream_id),
         :ok <- MediaFields.required_expected(options, :stream_id, stream_id),
         {:ok, provider_sequence} <- MediaFields.integer(message, "sequenceNumber"),
         {:ok, sequence_number} <- MediaFields.integer(media, "chunk"),
         {:ok, timestamp} <- MediaFields.integer(media, "timestamp"),
         "inbound" <- Map.get(media, "track"),
         {:ok, payload} <- MediaFields.payload(Map.get(media, "payload")),
         {:ok, identity} <- MediaFields.identity(options) do
      packet = %MediaPacket{
        codec: :pcmu,
        sample_rate: 8_000,
        channels: 1,
        sequence_number: sequence_number,
        timestamp: timestamp,
        payload: payload
      }

      event =
        struct!(
          Event,
          Map.merge(identity, %{
            kind: :media,
            provider_event_id: "#{stream_id}:#{provider_sequence}",
            sequence_number: sequence_number,
            stream_id: stream_id,
            media: packet
          })
        )

      {:ok, event}
    else
      _invalid -> invalid()
    end
  end

  def decode(_options, _message), do: invalid()
  defp invalid, do: {:error, :invalid_twilio_media_message}
end
