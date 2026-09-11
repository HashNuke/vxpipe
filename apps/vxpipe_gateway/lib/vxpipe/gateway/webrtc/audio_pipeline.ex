defmodule Vxpipe.Gateway.WebRTC.AudioPipeline do
  @moduledoc """
  Normalizes one WebRTC audio track into room-clock-aligned mixer frames.
  """

  use Membrane.Pipeline

  import Membrane.ChildrenSpec

  alias Membrane.{Buffer, Pipeline, Time}
  alias Vxpipe.CallEngine.Media.AudioFrame
  alias Vxpipe.Gateway.Media.{MonoMixer, PCMFrame, PCMSink}
  alias Vxpipe.Gateway.WebRTC.AudioPipeline.{PacketSource, RoomTimestamp}

  @sample_rate 48_000
  @channels 1
  @children MapSet.new([
              :source,
              :jitter_buffer,
              :room_timestamp,
              :depayloader,
              :parser,
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

  defp validate(_frame, _state), do: :ok

  defp via(pipeline_id) do
    {:via, Registry, {Vxpipe.Gateway.WebRTC.Registry, {:audio_pipeline, pipeline_id}}}
  end
end
