defmodule Vxpipe.Gateway.WebRTC.AudioPipeline.PCMSink do
  @moduledoc false

  use Membrane.Sink

  alias Membrane.{Buffer, RawAudio}

  def_input_pad(:input,
    accepted_format: %RawAudio{sample_format: :s16le, sample_rate: 48_000, channels: 1},
    flow_control: :auto
  )

  @impl true
  def handle_buffer(:input, %Buffer{} = buffer, _context, state) do
    {[notify_parent: {:pcm, buffer}], state}
  end
end
