defmodule Vxpipe.Gateway.Media.PCMSource do
  @moduledoc false

  use Membrane.Source

  alias Membrane.{Buffer, RawAudio, Time}
  alias Vxpipe.CallEngine.Media.MixedFrame

  @sample_rate 48_000

  def_output_pad(:output,
    accepted_format: %RawAudio{sample_format: :s16le, sample_rate: @sample_rate, channels: 1},
    flow_control: :push
  )

  @impl true
  def handle_playing(_context, state) do
    stream_format = %RawAudio{sample_format: :s16le, sample_rate: @sample_rate, channels: 1}
    {[stream_format: {:output, stream_format}], state}
  end

  @impl true
  def handle_parent_notification({:push, %MixedFrame{} = frame}, _context, state) do
    buffer = %Buffer{
      payload: frame.payload,
      pts: div(frame.timestamp * Time.second(), frame.sample_rate)
    }

    {[buffer: {:output, buffer}], state}
  end
end
