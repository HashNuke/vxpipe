defmodule Vxpipe.Gateway.Media.OpusInputPreparation do
  @moduledoc false

  use Membrane.Filter

  alias Membrane.Opus
  alias Vxpipe.Gateway.Media.InputPrepared

  def_input_pad(:input, accepted_format: Opus, flow_control: :auto)
  def_output_pad(:output, accepted_format: Opus, flow_control: :auto)

  @impl true
  def handle_init(_context, _options), do: {[], %{format: nil, pending_preparation: nil}}

  @impl true
  def handle_playing(_context, %{pending_preparation: nil} = state), do: {[], state}

  def handle_playing(_context, %{pending_preparation: {reference, channels}} = state) do
    prepare(reference, channels, %{state | pending_preparation: nil})
  end

  @impl true
  def handle_stream_format(:input, %Opus{} = format, _context, state) do
    {[stream_format: {:output, format}], %{state | format: format}}
  end

  @impl true
  def handle_parent_notification({:prepare, reference, channels}, %{playback: :playing}, state) do
    prepare(reference, channels, state)
  end

  def handle_parent_notification({:prepare, reference, channels}, _context, state) do
    {[], %{state | pending_preparation: {reference, channels}}}
  end

  @impl true
  def handle_buffer(:input, buffer, _context, state), do: {[buffer: {:output, buffer}], state}

  defp prepare(reference, channels, state) do
    format = state.format || %Opus{channels: channels}
    actions = if state.format, do: [], else: [stream_format: {:output, format}]
    event = %InputPrepared{reference: reference}
    {actions ++ [event: {:output, event}], %{state | format: format}}
  end
end
