defmodule Vxpipe.Providers.Twilio.PCMU.Decoder do
  @moduledoc false

  use Membrane.Filter

  alias Membrane.{Buffer, RawAudio}
  alias Vxpipe.Providers.Twilio.PCMU.{Codec, Format}

  def_input_pad(:input,
    accepted_format: %Format{sample_rate: 8_000, channels: 1},
    flow_control: :auto
  )

  def_output_pad(:output,
    accepted_format: %RawAudio{sample_format: :s16le, sample_rate: 8_000, channels: 1},
    flow_control: :auto
  )

  @impl true
  def handle_stream_format(:input, %Format{}, _context, state) do
    format = %RawAudio{sample_format: :s16le, sample_rate: 8_000, channels: 1}
    {[stream_format: {:output, format}], state}
  end

  @impl true
  def handle_buffer(:input, %Buffer{} = buffer, _context, state) do
    {:ok, payload} = Codec.decode(buffer.payload)
    {[buffer: {:output, %{buffer | payload: payload}}], state}
  end
end
