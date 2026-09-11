defmodule Vxpipe.Gateway.Telephony.Telnyx.AudioEgressPipeline.SocketSink do
  @moduledoc false

  use Membrane.Sink

  alias Membrane.{Buffer, Opus, Time}

  @sample_rate 48_000

  def_options(socket_owner: [spec: pid()])

  def_input_pad(:input,
    accepted_format: %Opus{channels: 1, self_delimiting?: false},
    flow_control: :push
  )

  @impl true
  def handle_buffer(:input, %Buffer{} = buffer, _context, state) do
    message =
      JSON.encode!(%{
        "event" => "media",
        "media" => %{"payload" => Base.encode64(buffer.payload)}
      })

    send(state.socket_owner, {:vxpipe_telnyx_socket_send, message})
    timestamp = Time.as_seconds(buffer.pts * @sample_rate, :round)

    {[notify_parent: {:sent, timestamp}], state}
  end
end
