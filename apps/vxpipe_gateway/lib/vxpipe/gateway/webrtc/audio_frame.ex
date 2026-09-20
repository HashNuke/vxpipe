defmodule Vxpipe.Gateway.WebRTC.AudioFrame do
  @moduledoc false

  alias ExRTP.Packet
  alias ExWebRTC.RTPCodecParameters
  alias Vxpipe.CallEngine.Media.AudioFrame
  alias Vxpipe.Gateway.Session.Snapshot
  alias Vxpipe.Gateway.WebRTC.OpusInput

  @spec from_rtp(
          Snapshot.t(),
          String.t(),
          ExWebRTC.MediaStreamTrack.id(),
          RTPCodecParameters.t(),
          Packet.t(),
          integer()
        ) ::
          {:ok, AudioFrame.t()}
          | {:error, :unsupported_codec | :invalid_packet}
  def from_rtp(
        %Snapshot{} = session,
        connection_id,
        track_id,
        %RTPCodecParameters{} = codec,
        %Packet{} = packet,
        received_at
      )
      when is_binary(connection_id) and is_integer(received_at) do
    with {:ok, engine_codec} <- engine_codec(codec.mime_type),
         {:ok, _packet_channels} <- OpusInput.channels(codec, packet.payload),
         {:ok, channels} <- OpusInput.track_channels(codec),
         true <- codec.payload_type == packet.payload_type,
         true <- is_binary(packet.payload) and byte_size(packet.payload) > 0,
         {:ok, normalized_track_id} <- normalize_track_id(track_id) do
      {:ok,
       %AudioFrame{
         tenant_id: session.tenant_id,
         room_id: session.room_id,
         incarnation_id: session.incarnation_id,
         participant_id: session.participant_id,
         connection_id: connection_id,
         track_id: normalized_track_id,
         codec: engine_codec,
         sample_rate: codec.clock_rate,
         channels: channels,
         sequence_number: packet.sequence_number,
         timestamp: packet.timestamp,
         payload: packet.payload,
         received_at: received_at
       }}
    else
      {:error, :unsupported_codec} -> {:error, :unsupported_codec}
      {:error, :invalid_packet} -> {:error, :invalid_packet}
      _invalid -> {:error, :invalid_packet}
    end
  end

  defp engine_codec(mime_type) when is_binary(mime_type) do
    case String.downcase(mime_type) do
      "audio/opus" -> {:ok, :opus}
      _unsupported -> {:error, :unsupported_codec}
    end
  end

  defp normalize_track_id(track_id) when is_integer(track_id),
    do: {:ok, Integer.to_string(track_id)}

  defp normalize_track_id(track_id) when is_binary(track_id), do: {:ok, track_id}
  defp normalize_track_id(_track_id), do: {:error, :invalid_track_id}
end
