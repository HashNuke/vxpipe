defmodule Vxpipe.Gateway.WebRTC.RoomAudioOutputPipeline do
  @moduledoc """
  Encodes one room mixer subscription as a paced WebRTC Opus/RTP stream.
  """

  use Membrane.Pipeline

  import Membrane.ChildrenSpec

  alias Membrane.{Pipeline, RawAudio}
  alias Vxpipe.CallEngine.Media.MixedFrame
  alias Vxpipe.Gateway.WebRTC.RoomAudioOutputPipeline.{PCMSource, RTPSink}

  @sample_rate 48_000
  @channels 1
  @frame_samples 960
  @frame_bytes @frame_samples * @channels * 2
  @payload_type 111
  @children MapSet.new([:source, :encoder, :payloader, :rtp_header, :realtimer, :sink])

  @spec start_link(keyword()) :: Pipeline.on_start()
  def start_link(options) do
    pipeline_id = Keyword.fetch!(options, :pipeline_id)
    Pipeline.start_link(__MODULE__, options, name: via(pipeline_id))
  end

  @spec push(String.t(), MixedFrame.t()) :: :ok | {:error, atom()}
  def push(pipeline_id, %MixedFrame{} = frame) do
    Pipeline.call(via(pipeline_id), {:push, frame})
  end

  @impl true
  def handle_init(_context, options) do
    state = %{
      pipeline_id: Keyword.fetch!(options, :pipeline_id),
      owner: Keyword.fetch!(options, :owner),
      subscription_id: Keyword.fetch!(options, :subscription_id),
      tenant_id: Keyword.fetch!(options, :tenant_id),
      room_id: Keyword.fetch!(options, :room_id),
      incarnation_id: Keyword.fetch!(options, :incarnation_id),
      participant_id: Keyword.fetch!(options, :participant_id),
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
      |> child(:payloader, Membrane.RTP.Opus.Payloader)
      |> child(:rtp_header, %Membrane.RTP.HeaderGenerator{
        ssrc: :rand.uniform(4_294_967_296) - 1,
        payload_type: @payload_type,
        clock_rate: @sample_rate
      })
      |> child(:realtimer, Membrane.Realtimer)
      |> child(:sink, %RTPSink{
        peer_connection: Keyword.fetch!(options, :peer_connection),
        track_id: Keyword.fetch!(options, :track_id),
        send_rtp: Keyword.get(options, :send_rtp, &ExWebRTC.PeerConnection.send_rtp/3)
      })

    {[spec: specification], state}
  end

  @impl true
  def handle_child_playing(child, _context, state) do
    playing_children = MapSet.put(state.playing_children, child)

    if MapSet.equal?(playing_children, @children) do
      send(state.owner, {:vxpipe_room_audio_output_ready, state.pipeline_id})
    end

    {[], %{state | playing_children: playing_children}}
  end

  @impl true
  def handle_call({:push, %MixedFrame{} = frame}, _context, state) do
    case validate(frame, state) do
      :ok ->
        {[notify_child: {:source, {:push, frame}}, reply: :ok], state}

      {:error, reason} ->
        {[reply: {:error, reason}], state}
    end
  end

  @impl true
  def handle_child_notification({:sent, timestamp}, :sink, _context, state) do
    send(state.owner, {:vxpipe_room_audio_output_sent, state.pipeline_id, timestamp})
    {[], state}
  end

  @impl true
  def handle_child_notification({:send_failed, reason}, :sink, _context, state) do
    send(state.owner, {:vxpipe_room_audio_output_unavailable, state.pipeline_id, reason})
    {[terminate: {:shutdown, reason}], state}
  end

  defp validate(%MixedFrame{tenant_id: tenant_id}, %{tenant_id: expected})
       when tenant_id != expected,
       do: {:error, :wrong_tenant}

  defp validate(%MixedFrame{room_id: room_id}, %{room_id: expected})
       when room_id != expected,
       do: {:error, :wrong_room}

  defp validate(%MixedFrame{incarnation_id: incarnation_id}, %{incarnation_id: expected})
       when incarnation_id != expected,
       do: {:error, :wrong_incarnation}

  defp validate(%MixedFrame{subscription_id: subscription_id}, %{subscription_id: expected})
       when subscription_id != expected,
       do: {:error, :wrong_subscription}

  defp validate(%MixedFrame{recipient_participant_id: participant_id}, %{
         participant_id: expected
       })
       when participant_id != expected,
       do: {:error, :wrong_participant}

  defp validate(%MixedFrame{mode: mode}, _state) when mode not in [:full_mix, :mix_minus],
    do: {:error, :unsupported_mode}

  defp validate(%MixedFrame{sample_rate: sample_rate}, _state)
       when sample_rate != @sample_rate,
       do: {:error, :unsupported_audio}

  defp validate(%MixedFrame{channels: channels}, _state) when channels != @channels,
    do: {:error, :unsupported_audio}

  defp validate(%MixedFrame{payload: payload}, _state) when byte_size(payload) != @frame_bytes,
    do: {:error, :unsupported_audio}

  defp validate(%MixedFrame{timestamp: timestamp}, _state)
       when timestamp < 0 or rem(timestamp, @frame_samples) != 0,
       do: {:error, :unaligned_timestamp}

  defp validate(_frame, _state), do: :ok

  defp via(pipeline_id) do
    {:via, Registry, {Vxpipe.Gateway.WebRTC.Registry, {:room_audio_output_pipeline, pipeline_id}}}
  end
end
