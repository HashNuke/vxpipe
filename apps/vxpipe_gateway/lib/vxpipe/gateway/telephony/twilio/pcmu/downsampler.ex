defmodule Vxpipe.Gateway.Telephony.Twilio.PCMU.Downsampler do
  @moduledoc false

  use Membrane.Filter

  alias Membrane.{Buffer, RawAudio}
  alias Vxpipe.Gateway.Telephony.Twilio.PCMU.RateConverter

  def_input_pad(:input,
    accepted_format: %RawAudio{sample_format: :s16le, sample_rate: 48_000, channels: 1},
    flow_control: :auto
  )

  def_output_pad(:output,
    accepted_format: %RawAudio{sample_format: :s16le, sample_rate: 8_000, channels: 1},
    flow_control: :auto
  )

  @impl true
  def handle_init(_context, _options), do: {[], %{remainder: <<>>}}

  @impl true
  def handle_stream_format(:input, %RawAudio{}, _context, state) do
    format = %RawAudio{sample_format: :s16le, sample_rate: 8_000, channels: 1}
    {[stream_format: {:output, format}], state}
  end

  @impl true
  def handle_buffer(:input, %Buffer{} = buffer, _context, state) do
    {:ok, payload, remainder} =
      RateConverter.downsample_48_to_8(buffer.payload, state.remainder)

    actions = if payload == <<>>, do: [], else: [buffer: {:output, %{buffer | payload: payload}}]
    {actions, %{state | remainder: remainder}}
  end
end
