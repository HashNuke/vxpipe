defmodule Vxpipe.Gateway.Telephony.Twilio.AudioEgressPipeline.SocketSink do
  @moduledoc false

  use Membrane.Sink

  alias Membrane.{Buffer, Time}
  alias Vxpipe.Gateway.Telephony.Twilio.PCMU.Format

  @encoded_sample_rate 8_000
  @room_sample_rate 48_000

  def_options(
    socket_owner: [spec: pid()],
    stream_id: [spec: String.t()]
  )

  def_input_pad(:input,
    accepted_format: %Format{sample_rate: @encoded_sample_rate, channels: 1},
    flow_control: :push
  )

  @impl true
  def handle_buffer(:input, %Buffer{} = buffer, _context, state) do
    message =
      JSON.encode!(%{
        "event" => "media",
        "streamSid" => state.stream_id,
        "media" => %{"payload" => Base.encode64(buffer.payload)}
      })

    send(state.socket_owner, {:vxpipe_twilio_socket_send, message})
    timestamp = Time.as_seconds(buffer.pts * @room_sample_rate, :round)

    {[notify_parent: {:sent, timestamp}], state}
  end
end
