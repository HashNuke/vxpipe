defmodule Vxpipe.Gateway.WebRTC.NegotiatedAudio do
  @moduledoc false

  alias ExWebRTC.{MediaStreamTrack, RTPCodecParameters, RTPTransceiver}
  alias Vxpipe.CallEngine.Readiness.Resource

  def resolve(direction, transceivers, output_track) when direction in [:input, :output] do
    candidates = Enum.filter(transceivers, &usable?(&1, direction, output_track))

    case candidates do
      [] -> {:preparing, nil}
      [transceiver] -> project(transceiver, direction)
      _ambiguous -> {:failed, nil}
    end
  end

  defp usable?(
         %RTPTransceiver{kind: :audio, stopped: false, stopping: false} = transceiver,
         :input,
         _output_track
       ),
       do: transceiver.current_direction in [:recvonly, :sendrecv]

  defp usable?(
         %RTPTransceiver{kind: :audio, stopped: false, stopping: false} = transceiver,
         :output,
         output_track
       ) do
    transceiver.current_direction in [:sendonly, :sendrecv] and
      match?(%MediaStreamTrack{id: ^output_track}, transceiver.sender.track)
  end

  defp usable?(_transceiver, _direction, _output_track), do: false

  defp project(transceiver, direction) do
    case codec(transceiver, direction) do
      {:ok, codec} -> project_track(transceiver, direction, codec)
      :missing -> {:preparing, nil}
      :unsupported -> {:failed, nil}
    end
  end

  defp project_track(transceiver, direction, codec) do
    track = if direction == :input, do: transceiver.receiver.track, else: transceiver.sender.track

    if is_integer(track.id) or (is_binary(track.id) and byte_size(track.id) > 0) do
      {:ready,
       %{
         track: %{
           track_id: to_string(track.id),
           codec: :opus,
           sample_rate: codec.clock_rate,
           channels: codec.channels || 1
         },
         configuration:
           Resource.signature({transceiver.id, transceiver.mid, direction, track.id, codec})
       }}
    else
      {:failed, nil}
    end
  end

  defp codec(%{sender: %{codec: nil}}, :output), do: :missing

  defp codec(transceiver, :output) do
    codec = transceiver.sender.codec
    if supported?(codec), do: {:ok, codec}, else: :unsupported
  end

  defp codec(%{codecs: []}, :input), do: :missing

  defp codec(transceiver, :input) do
    case Enum.find(transceiver.codecs, &supported?/1) do
      nil -> :unsupported
      codec -> {:ok, codec}
    end
  end

  defp supported?(%RTPCodecParameters{mime_type: mime, clock_rate: 48_000, channels: channels})
       when is_binary(mime) and channels in [nil, 1, 2],
       do: String.downcase(mime) == "audio/opus"

  defp supported?(_codec), do: false
end
