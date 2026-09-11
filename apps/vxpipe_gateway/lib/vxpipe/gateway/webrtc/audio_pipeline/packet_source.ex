defmodule Vxpipe.Gateway.WebRTC.AudioPipeline.PacketSource do
  @moduledoc false

  use Membrane.Source

  alias Membrane.{Buffer, Opus, RTP}
  alias Vxpipe.CallEngine.Media.AudioFrame

  def_output_pad(:output,
    accepted_format: RTP,
    flow_control: :push
  )

  @impl true
  def handle_playing(_context, state) do
    {[stream_format: {:output, %RTP{payload_format: Opus}}], state}
  end

  @impl true
  def handle_parent_notification({:push, %AudioFrame{} = frame}, _context, state) do
    buffer = %Buffer{
      payload: frame.payload,
      metadata: %{
        received_at: frame.received_at,
        rtp: %{
          sequence_number: frame.sequence_number,
          timestamp: frame.timestamp
        }
      }
    }

    {[buffer: {:output, buffer}], state}
  end
end
