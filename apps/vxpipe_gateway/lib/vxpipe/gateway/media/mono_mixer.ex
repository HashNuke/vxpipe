defmodule Vxpipe.Gateway.Media.MonoMixer do
  @moduledoc false

  use Membrane.Filter

  alias Membrane.{Buffer, RawAudio}

  def_input_pad(:input,
    accepted_format:
      %RawAudio{sample_format: :s16le, sample_rate: 48_000, channels: channels}
      when channels in [1, 2],
    flow_control: :auto
  )

  def_output_pad(:output,
    accepted_format: %RawAudio{sample_format: :s16le, sample_rate: 48_000, channels: 1},
    flow_control: :auto
  )

  @impl true
  def handle_stream_format(:input, %RawAudio{} = format, _context, _state) do
    {[stream_format: {:output, %{format | channels: 1}}], %{channels: format.channels}}
  end

  @impl true
  def handle_buffer(:input, %Buffer{} = buffer, _context, %{channels: 1} = state) do
    {[buffer: {:output, buffer}], state}
  end

  def handle_buffer(:input, %Buffer{} = buffer, _context, %{channels: 2} = state) do
    payload =
      for <<left::little-signed-16, right::little-signed-16 <- buffer.payload>>, into: <<>> do
        <<div(left + right, 2)::little-signed-16>>
      end

    {[buffer: {:output, %{buffer | payload: payload}}], state}
  end
end
