defmodule Vxpipe.Gateway.Telephony.Twilio.AudioIngressPipeline.PacketSource do
  @moduledoc false

  use Membrane.Source

  alias Membrane.{Buffer, Time}
  alias Vxpipe.CallEngine.Media.AudioFrame
  alias Vxpipe.Gateway.Telephony.Twilio.PCMU.Format

  def_output_pad(:output,
    accepted_format: %Format{sample_rate: 8_000, channels: 1},
    flow_control: :push
  )

  @impl true
  def handle_playing(_context, state) do
    {[stream_format: {:output, %Format{sample_rate: 8_000, channels: 1}}], state}
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
