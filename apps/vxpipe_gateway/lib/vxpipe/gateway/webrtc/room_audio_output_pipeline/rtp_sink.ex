defmodule Vxpipe.Gateway.WebRTC.RoomAudioOutputPipeline.RTPSink do
  @moduledoc false

  use Membrane.Sink

  alias ExRTP.Packet
  alias Membrane.{Buffer, RTP, Time}

  @sample_rate 48_000

  def_options(
    peer_connection: [spec: pid()],
    track_id: [spec: String.t()],
    send_rtp: [spec: function()]
  )

  def_input_pad(:input,
    accepted_format: RTP,
    flow_control: :push
  )

  @impl true
  def handle_buffer(:input, %Buffer{} = buffer, _context, state) do
    packet = packet(buffer)

    notification =
      case state.send_rtp.(state.peer_connection, state.track_id, packet) do
        :ok -> {:sent, Time.as_seconds(buffer.pts * @sample_rate, :round)}
        {:error, reason} -> {:send_failed, reason}
      end

    {[notify_parent: notification], state}
  end

  defp packet(%Buffer{payload: payload, metadata: %{rtp: header}}) do
    Packet.new(payload,
      payload_type: header.payload_type,
      sequence_number: header.sequence_number,
      timestamp: header.timestamp,
      ssrc: header.ssrc,
      marker: header.marker,
      csrc: header.csrcs
    )
  end
end
