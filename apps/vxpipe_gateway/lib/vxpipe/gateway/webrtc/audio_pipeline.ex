defmodule Vxpipe.Gateway.WebRTC.AudioPipeline do
  @moduledoc """
  Normalizes one WebRTC audio track into room-clock-aligned mixer frames.
  """

  use Membrane.Pipeline

  @behaviour Vxpipe.CallEngine.Readiness.Adapter

  import Membrane.ChildrenSpec

  alias Membrane.{Buffer, Pipeline, Time}
  alias Vxpipe.CallEngine.Media.AudioFrame
  alias Vxpipe.CallEngine.Readiness.Resource
  alias Vxpipe.Gateway.Media.{MonoMixer, OpusInputPreparation, PCMFrame, PCMSink}
  alias Vxpipe.Gateway.WebRTC.AudioPipeline.{PacketSource, RoomTimestamp}

  @sample_rate 48_000
  @channels 1
  @children MapSet.new([
              :source,
              :jitter_buffer,
              :room_timestamp,
              :depayloader,
              :parser,
              :input_preparation,
              :decoder,
              :channel_mixer,
              :frame_parser,
              :sink
            ])

  @spec start_link(keyword()) :: Pipeline.on_start()
  def start_link(options) do
    pipeline_id = Keyword.fetch!(options, :pipeline_id)
    Pipeline.start_link(__MODULE__, options, name: via(pipeline_id))
  end

  @spec push(String.t(), AudioFrame.t()) :: :ok | {:error, atom()}
  def push(pipeline_id, %AudioFrame{} = frame) do
    Pipeline.call(via(pipeline_id), {:push, frame})
  end

  def prepare_track(pipeline, track), do: call(pipeline, {:prepare_track, track})

  @impl Vxpipe.CallEngine.Readiness.Adapter
  def readiness(pipeline), do: call(pipeline, :readiness)

  @impl true
  def handle_init(_context, options) do
    state = %{
      pipeline_id: Keyword.fetch!(options, :pipeline_id),
      owner: Keyword.fetch!(options, :owner),
      tenant_id: Keyword.fetch!(options, :tenant_id),
      room_id: Keyword.fetch!(options, :room_id),
      incarnation_id: Keyword.fetch!(options, :incarnation_id),
      participant_id: Keyword.fetch!(options, :participant_id),
      connection_id: Keyword.fetch!(options, :connection_id),
      track_id: nil,
      prepared_track: nil,
      preparation_reference: nil,
      preparation_status: :preparing,
      input_resource:
        Resource.new(
          :audio_input,
          {:participant, Keyword.fetch!(options, :participant_id)},
          __MODULE__,
          options,
          binding: Keyword.fetch!(options, :connection_id)
        ),
      playing_children: MapSet.new()
    }

    jitter_latency = options |> Keyword.fetch!(:jitter_latency) |> Time.milliseconds()

    specification =
      child(:source, PacketSource)
      |> child(:jitter_buffer, %Membrane.RTP.JitterBuffer{
        clock_rate: @sample_rate,
        latency: jitter_latency
      })
      |> child(:room_timestamp, %RoomTimestamp{
        clock_origin_ms: Keyword.fetch!(options, :clock_origin_ms)
      })
      |> child(:depayloader, Membrane.RTP.Opus.Depayloader)
      |> child(:parser, Membrane.Opus.Parser)
      |> child(:input_preparation, OpusInputPreparation)
      |> child(:decoder, %Membrane.Opus.Decoder{sample_rate: @sample_rate})
      |> child(:channel_mixer, MonoMixer)
      |> child(:frame_parser, %Membrane.RawAudioParser{
        chunk_duration: Time.milliseconds(20)
      })
      |> child(:sink, PCMSink)

    {[spec: specification], state}
  end

  @impl true
  def handle_child_playing(child, _context, state) do
    playing_children = MapSet.put(state.playing_children, child)

    if MapSet.equal?(playing_children, @children) do
      send(state.owner, {:vxpipe_audio_pipeline_ready, state.pipeline_id})
    end

    {[], %{state | playing_children: playing_children}}
  end

  @impl true
  def handle_call(:readiness, _context, state) do
    resource = %{
      state.input_resource
      | configuration:
          Resource.signature({state.input_resource.configuration, state.prepared_track})
    }

    status =
      if MapSet.equal?(state.playing_children, @children),
        do: state.preparation_status,
        else: :preparing

    {[reply: {:ok, resource, status}], state}
  end

  def handle_call({:prepare_track, track}, _context, state) do
    case validate_preparation(track, state) do
      :ok when state.prepared_track == track ->
        {[reply: :ok], state}

      :ok ->
        reference = make_ref()

        state = %{
          state
          | track_id: track.track_id,
            prepared_track: track,
            preparation_reference: reference,
            preparation_status: :preparing
        }

        {[notify_child: {:input_preparation, {:prepare, reference, track.channels}}, reply: :ok],
         state}

      {:error, _reason} = error ->
        {[reply: error], state}
    end
  end

  def handle_call({:push, %AudioFrame{} = frame}, _context, state) do
    case validate(frame, state) do
      :ok ->
        state = %{state | track_id: state.track_id || frame.track_id}
        {[notify_child: {:source, {:push, frame}}, reply: :ok], state}

      {:error, reason} ->
        {[reply: {:error, reason}], state}
    end
  end

  @impl true
  def handle_child_notification(
        {:input_prepared, reference},
        :sink,
        _context,
        %{preparation_reference: reference} = state
      )
      when is_reference(reference) do
    {[], %{state | preparation_status: :ready}}
  end

  def handle_child_notification(
        {:input_preparation_failed, reference},
        :sink,
        _context,
        %{preparation_reference: reference} = state
      )
      when is_reference(reference) do
    {[], %{state | preparation_status: :failed}}
  end

  def handle_child_notification({:pcm, %Buffer{} = buffer}, :sink, _context, state) do
    frame = %PCMFrame{
      tenant_id: state.tenant_id,
      room_id: state.room_id,
      incarnation_id: state.incarnation_id,
      participant_id: state.participant_id,
      connection_id: state.connection_id,
      track_id: state.track_id,
      timestamp: Time.as_seconds(buffer.pts * @sample_rate, :round),
      sample_rate: @sample_rate,
      channels: @channels,
      payload: buffer.payload
    }

    send(state.owner, {:vxpipe_audio_pipeline, state.pipeline_id, frame})
    {[], state}
  end

  def handle_child_notification(_notification, _child, _context, state), do: {[], state}

  defp validate_preparation(
         %{track_id: id, codec: :opus, sample_rate: 48_000, channels: channels} = track,
         state
       )
       when is_binary(id) and byte_size(id) > 0 and channels in [1, 2] and map_size(track) == 4 do
    cond do
      state.track_id != nil and state.track_id != id -> {:error, :wrong_track}
      state.prepared_track not in [nil, track] -> {:error, :track_already_prepared}
      true -> :ok
    end
  end

  defp validate_preparation(_track, _state), do: {:error, :unsupported_audio}

  defp validate(%AudioFrame{connection_id: connection_id}, %{connection_id: expected})
       when connection_id != expected,
       do: {:error, :wrong_connection}

  defp validate(%AudioFrame{tenant_id: tenant_id}, %{tenant_id: expected})
       when tenant_id != expected,
       do: {:error, :wrong_tenant}

  defp validate(%AudioFrame{room_id: room_id}, %{room_id: expected})
       when room_id != expected,
       do: {:error, :wrong_room}

  defp validate(%AudioFrame{incarnation_id: incarnation_id}, %{incarnation_id: expected})
       when incarnation_id != expected,
       do: {:error, :wrong_incarnation}

  defp validate(%AudioFrame{participant_id: participant_id}, %{participant_id: expected})
       when participant_id != expected,
       do: {:error, :wrong_participant}

  defp validate(%AudioFrame{track_id: track_id}, %{track_id: expected})
       when not is_nil(expected) and track_id != expected,
       do: {:error, :wrong_track}

  defp validate(%AudioFrame{codec: codec}, _state) when codec != :opus,
    do: {:error, :unsupported_codec}

  defp validate(frame, %{prepared_track: track}) when not is_nil(track) do
    if frame.sample_rate == track.sample_rate and frame.channels == track.channels,
      do: :ok,
      else: {:error, :unsupported_audio}
  end

  defp validate(_frame, _state), do: :ok

  defp via(pipeline_id) do
    {:via, Registry, {Vxpipe.Gateway.WebRTC.Registry, {:audio_pipeline, pipeline_id}}}
  end

  defp call(pipeline, message) do
    server = if is_pid(pipeline), do: pipeline, else: via(pipeline)
    Pipeline.call(server, message, 1_000)
  catch
    :exit, _reason -> {:error, :unavailable}
  end
end
