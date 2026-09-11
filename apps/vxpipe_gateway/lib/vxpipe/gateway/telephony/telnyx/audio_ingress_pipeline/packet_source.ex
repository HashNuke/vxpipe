defmodule Vxpipe.Gateway.Telephony.Telnyx.AudioIngressPipeline.PacketSource do
  @moduledoc false

  use Membrane.Source

  alias Membrane.{Buffer, Opus, Time}
  alias Vxpipe.CallEngine.Media.AudioFrame

  def_output_pad(:output,
    accepted_format: %Opus{channels: 1, self_delimiting?: false},
    flow_control: :push
  )

  @impl true
  def handle_playing(_context, state) do
    {[stream_format: {:output, %Opus{channels: 1}}], state}
  end

  @impl true
  def handle_parent_notification({:push, %AudioFrame{} = frame}, _context, state) do
    buffer = %Buffer{
      payload: frame.payload,
      pts: Time.milliseconds(frame.timestamp),
      metadata: %{received_at: frame.received_at}
    }

    {[buffer: {:output, buffer}], state}
  end
end
