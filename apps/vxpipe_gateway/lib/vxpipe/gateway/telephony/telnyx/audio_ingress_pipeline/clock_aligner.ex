defmodule Vxpipe.Gateway.Telephony.Telnyx.AudioIngressPipeline.ClockAligner do
  @moduledoc false

  use Membrane.Filter

  alias Membrane.{Buffer, Opus, Time}

  @frame_duration Time.milliseconds(20)

  def_input_pad(:input,
    accepted_format: %Opus{channels: 1, self_delimiting?: false},
    flow_control: :auto
  )

  def_output_pad(:output,
    accepted_format: %Opus{channels: 1, self_delimiting?: false},
    flow_control: :auto
  )

  def_options(clock_origin_ms: [spec: integer()])

  @impl true
  def handle_init(_context, options) do
    {[], %{clock_origin_ms: options.clock_origin_ms, offset: nil}}
  end

  @impl true
  def handle_buffer(:input, %Buffer{} = buffer, _context, %{offset: nil} = state) do
    received_at = Map.fetch!(buffer.metadata, :received_at)
    room_time = received_at |> Kernel.-(state.clock_origin_ms) |> max(0) |> milliseconds()
    offset = align_to_frame(room_time) - buffer.pts

    {[buffer: {:output, shift(buffer, offset)}], %{state | offset: offset}}
  end

  def handle_buffer(:input, %Buffer{} = buffer, _context, state) do
    {[buffer: {:output, shift(buffer, state.offset)}], state}
  end

  defp milliseconds(value), do: Time.milliseconds(value)
  defp align_to_frame(timestamp), do: div(timestamp, @frame_duration) * @frame_duration
  defp shift(%Buffer{} = buffer, offset), do: %{buffer | pts: max(buffer.pts + offset, 0)}
end
