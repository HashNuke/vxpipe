defmodule Vxpipe.Gateway.Media.PCMSink do
  @moduledoc false

  use Membrane.Sink

  alias Membrane.{Buffer, RawAudio}
  alias Vxpipe.Gateway.Media.InputPrepared

  def_input_pad(:input,
    accepted_format: %RawAudio{sample_format: :s16le, sample_rate: 48_000, channels: 1},
    flow_control: :auto
  )

  @impl true
  def handle_event(:input, %InputPrepared{reference: reference}, context, state) do
    case context.pads.input.stream_format do
      %RawAudio{sample_format: :s16le, sample_rate: 48_000, channels: 1} ->
        {[notify_parent: {:input_prepared, reference}], state}

      _unprepared ->
        {[notify_parent: {:input_preparation_failed, reference}], state}
    end
  end

  def handle_event(_pad, _event, _context, state), do: {[], state}

  @impl true
  def handle_buffer(:input, %Buffer{} = buffer, _context, state) do
    {[notify_parent: {:pcm, buffer}], state}
  end
end
