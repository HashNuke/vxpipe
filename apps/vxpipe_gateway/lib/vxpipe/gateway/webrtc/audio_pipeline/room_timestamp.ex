defmodule Vxpipe.Gateway.WebRTC.AudioPipeline.RoomTimestamp do
  @moduledoc false

  use Membrane.Filter

  alias Membrane.{Buffer, Time}

  @frame_duration Time.milliseconds(20)

  def_input_pad(:input,
    accepted_format: Membrane.RTP,
    flow_control: :auto
  )

  def_output_pad(:output,
    accepted_format: Membrane.RTP,
    flow_control: :auto
  )

  def_options(clock_origin_ms: [spec: integer()])

  @impl true
  def handle_init(_context, options) do
    {[], %{clock_origin_ms: options.clock_origin_ms, offset: nil}}
  end

  @impl true
  def handle_buffer(:input, %Buffer{} = buffer, _context, %{offset: nil} = state) do
    received_at = get_in(buffer.metadata, [:received_at])
    elapsed = max(received_at - state.clock_origin_ms, 0)
    offset = elapsed |> Time.milliseconds() |> align_to_frame()

    {[buffer: {:output, shift(buffer, offset)}], %{state | offset: offset}}
  end

  def handle_buffer(:input, %Buffer{} = buffer, _context, state) do
    {[buffer: {:output, shift(buffer, state.offset)}], state}
  end

  defp align_to_frame(timestamp), do: div(timestamp, @frame_duration) * @frame_duration

  defp shift(%Buffer{pts: pts} = buffer, offset), do: %{buffer | pts: pts + offset}
end
