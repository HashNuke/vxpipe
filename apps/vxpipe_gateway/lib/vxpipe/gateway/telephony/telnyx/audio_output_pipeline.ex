defmodule Vxpipe.Gateway.Telephony.Telnyx.AudioOutputPipeline do
  @moduledoc """
  Encodes acknowledged direct playout as paced Telnyx Opus media messages.
  """

  use Membrane.Pipeline

  import Membrane.ChildrenSpec

  alias Membrane.{Pipeline, RawAudio}
  alias Vxpipe.Gateway.Media.{PCMSource, PlaybackFrame}
  alias Vxpipe.Gateway.Telephony.Telnyx.AudioEgressPipeline.SocketSink

  @sample_rate 48_000
  @channels 1
  @frame_samples 960
  @frame_bytes @frame_samples * @channels * 2
  @children MapSet.new([:source, :encoder, :realtimer, :sink])

  @spec start_link(keyword()) :: Pipeline.on_start()
  def start_link(options) do
    pipeline_id = Keyword.fetch!(options, :pipeline_id)
    Pipeline.start_link(__MODULE__, options, name: via(pipeline_id))
  end

  @spec push(String.t(), PlaybackFrame.t()) :: :ok | {:error, atom()}
  def push(pipeline_id, %PlaybackFrame{} = frame) do
    Pipeline.call(via(pipeline_id), {:push, frame})
  end

  @impl true
  def handle_init(_context, options) do
    state = %{
      pipeline_id: Keyword.fetch!(options, :pipeline_id),
      owner: Keyword.fetch!(options, :owner),
      last_sequence_number: nil,
      playing_children: MapSet.new()
    }

    raw_audio = %RawAudio{sample_format: :s16le, sample_rate: @sample_rate, channels: @channels}

    specification =
      child(:source, PCMSource)
      |> child(:encoder, %Membrane.Opus.Encoder{
        input_stream_format: raw_audio,
        application: :voip,
        signal_type: :voice
      })
      |> child(:realtimer, Membrane.Realtimer)
      |> child(:sink, %SocketSink{socket_owner: Keyword.fetch!(options, :socket_owner)})

    {[spec: specification], state}
  end

  @impl true
  def handle_child_playing(child, _context, state) do
    playing_children = MapSet.put(state.playing_children, child)

    if MapSet.equal?(playing_children, @children) do
      send(state.owner, {:vxpipe_audio_output_pipeline_ready, state.pipeline_id})
    end

    {[], %{state | playing_children: playing_children}}
  end

  @impl true
  def handle_call({:push, %PlaybackFrame{} = frame}, _context, state) do
    case validate(frame, state) do
      :ok ->
        state = %{state | last_sequence_number: frame.sequence_number}
        {[notify_child: {:source, {:push, frame}}, reply: :ok], state}

      {:error, reason} ->
        {[reply: {:error, reason}], state}
    end
  end

  @impl true
  def handle_child_notification({:sent, timestamp}, :sink, _context, state) do
    send(state.owner, {:vxpipe_audio_output_pipeline_sent, state.pipeline_id, timestamp})
    {[], state}
  end

  defp validate(%PlaybackFrame{sample_rate: rate}, _state) when rate != @sample_rate,
    do: {:error, :unsupported_audio}

  defp validate(%PlaybackFrame{payload: payload}, _state) when byte_size(payload) != @frame_bytes,
    do: {:error, :unsupported_audio}

  defp validate(%PlaybackFrame{sequence_number: sequence, timestamp: timestamp}, _state)
       when timestamp != sequence * @frame_samples,
       do: {:error, :unaligned_frame}

  defp validate(%PlaybackFrame{sequence_number: sequence}, %{last_sequence_number: previous})
       when not is_nil(previous) and sequence <= previous,
       do: {:error, :stale_sequence}

  defp validate(_frame, _state), do: :ok

  defp via(pipeline_id) do
    {:via, Registry, {Vxpipe.Gateway.Media.Registry, {:telnyx_audio_output, pipeline_id}}}
  end
end
