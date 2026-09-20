defmodule Vxpipe.Gateway.Media.OpusMonoDecoder do
  @moduledoc false

  use Membrane.Filter

  alias Membrane.{Buffer, Opus, RawAudio}
  alias Vxpipe.Gateway.WebRTC.OpusDecoder

  @sample_rate 48_000

  def_input_pad(:input, accepted_format: Opus, flow_control: :auto)

  def_output_pad(:output,
    accepted_format: %RawAudio{
      sample_format: :s16le,
      sample_rate: @sample_rate,
      channels: 1
    },
    flow_control: :auto
  )

  @impl true
  def handle_init(_context, _options) do
    {:ok, decoder} = OpusDecoder.new(@sample_rate)
    {[], %{decoder: decoder}}
  end

  @impl true
  def handle_stream_format(:input, %Opus{}, _context, state) do
    format = %RawAudio{sample_format: :s16le, sample_rate: @sample_rate, channels: 1}
    {[stream_format: {:output, format}], state}
  end

  @impl true
  def handle_buffer(:input, %Buffer{} = buffer, _context, state) do
    case OpusDecoder.decode(state.decoder, buffer.payload) do
      {:ok, payload} -> {[buffer: {:output, %{buffer | payload: payload}}], state}
      {:error, :invalid_packet} -> {[], state}
    end
  end
end
