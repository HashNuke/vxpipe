defmodule Vxpipe.Gateway.WebRTC.AudioEgress do
  @moduledoc false

  use GenServer

  alias ExRTP.Packet
  alias Vxpipe.CallEngine.Media.AudioOutputFrame
  alias Vxpipe.Gateway.WebRTC.OpusEncoder

  @frame_bytes 1_920
  @frame_duration_ms 20
  @rtp_timestamp_step 960

  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :connection_id)},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary
    }
  end

  @impl true
  def init(options) do
    {encoder_module, encoder_options} = Keyword.get(options, :encoder, {OpusEncoder, []})

    case encoder_module.new(encoder_options) do
      {:ok, encoder} ->
        {:ok,
         %{
           connection_id: Keyword.fetch!(options, :connection_id),
           current: nil,
           encoder: encoder,
           encoder_module: encoder_module,
           maximum_packets: Keyword.get(options, :maximum_packets, 100),
           pace_ref: nil,
           peer_connection: Keyword.fetch!(options, :peer_connection),
           queue: :queue.new(),
           remainder: <<>>,
           rtp_sequence: 0,
           rtp_timestamp: 0,
           schedule: Keyword.get(options, :schedule, &Process.send_after/3),
           send_rtp: Keyword.get(options, :send_rtp, &send_rtp/3),
           ssrc: :rand.uniform(4_294_967_295),
           track_id: Keyword.fetch!(options, :track_id)
         }}

      {:error, _reason} ->
        {:stop, :encoder_unavailable}
    end
  end

  @impl true
  def handle_call({:vxpipe_audio_output, %AudioOutputFrame{} = frame}, _from, state) do
    with :ok <- validate_frame(frame, state),
         {:ok, state} <- establish_turn(frame, state),
         {:ok, pcm_frames, remainder} <- split_pcm(state.remainder <> frame.payload, state),
         {:ok, packets} <- encode_frames(pcm_frames, state),
         state <- enqueue_packets(packets, remainder, state),
         {:ok, state} <- maybe_send(state) do
      {:reply, :ok, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:vxpipe_audio_output_finish, turn, callback}, _from, state) do
    with :ok <- validate_finish(turn, callback, state),
         {:ok, state} <- enqueue_final_remainder(state),
         state <- put_in(state.current.finished, true),
         {:ok, state} <- maybe_send_or_complete(state) do
      {:reply, :ok, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info({:vxpipe_audio_pace, pace_ref}, %{pace_ref: pace_ref} = state) do
    state = %{state | pace_ref: nil}

    case maybe_send_or_complete(state) do
      {:ok, state} -> {:noreply, state}
      {:error, reason} -> {:stop, reason, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp validate_frame(frame, state) do
    cond do
      frame.connection_id != state.connection_id -> {:error, :wrong_connection}
      frame.codec != :linear16 -> {:error, :unsupported_audio}
      frame.sample_rate != 48_000 -> {:error, :unsupported_audio}
      frame.channels != 1 -> {:error, :unsupported_audio}
      frame.byte_order != :little -> {:error, :unsupported_audio}
      not is_pid(frame.reply_to) -> {:error, :invalid_frame}
      not is_binary(frame.payload) or byte_size(frame.payload) == 0 -> {:error, :invalid_frame}
      true -> :ok
    end
  end

  defp establish_turn(frame, %{current: nil} = state) do
    current = %{
      callback: frame.reply_to,
      command_id: frame.command_id,
      correlation_id: frame.correlation_id,
      finished: false,
      started: false
    }

    {:ok, %{state | current: current}}
  end

  defp establish_turn(frame, state) do
    current = state.current

    if current.correlation_id == frame.correlation_id and current.command_id == frame.command_id and
         current.callback == frame.reply_to and not current.finished do
      {:ok, state}
    else
      {:error, :busy}
    end
  end

  defp split_pcm(pcm, state) do
    frame_count = div(byte_size(pcm), @frame_bytes)

    if frame_count + :queue.len(state.queue) > state.maximum_packets do
      {:error, :queue_full}
    else
      full_bytes = frame_count * @frame_bytes
      <<full::binary-size(full_bytes), remainder::binary>> = pcm
      {:ok, split_full_frames(full, []), remainder}
    end
  end

  defp split_full_frames(<<>>, frames), do: Enum.reverse(frames)

  defp split_full_frames(<<frame::binary-size(@frame_bytes), rest::binary>>, frames) do
    split_full_frames(rest, [frame | frames])
  end

  defp encode_frames(frames, state) do
    Enum.reduce_while(frames, {:ok, []}, fn frame, {:ok, packets} ->
      case state.encoder_module.encode(state.encoder, frame) do
        {:ok, packet} -> {:cont, {:ok, [packet | packets]}}
        {:error, _reason} -> {:halt, {:error, :encode_failed}}
      end
    end)
    |> case do
      {:ok, packets} -> {:ok, Enum.reverse(packets)}
      {:error, _reason} = error -> error
    end
  end

  defp enqueue_packets(packets, remainder, state) do
    queue = Enum.reduce(packets, state.queue, &:queue.in/2)
    %{state | queue: queue, remainder: remainder}
  end

  defp validate_finish(turn, callback, %{current: current}) when current != nil do
    if current.correlation_id == turn and current.callback == callback and not current.finished do
      :ok
    else
      {:error, :wrong_turn}
    end
  end

  defp validate_finish(_turn, _callback, _state), do: {:error, :wrong_turn}

  defp enqueue_final_remainder(%{remainder: <<>>} = state), do: {:ok, state}

  defp enqueue_final_remainder(state) do
    if :queue.len(state.queue) >= state.maximum_packets do
      {:error, :queue_full}
    else
      padding_bytes = @frame_bytes - byte_size(state.remainder)
      pcm = state.remainder <> :binary.copy(<<0>>, padding_bytes)

      case state.encoder_module.encode(state.encoder, pcm) do
        {:ok, packet} ->
          {:ok, %{state | queue: :queue.in(packet, state.queue), remainder: <<>>}}

        {:error, _reason} ->
          {:error, :encode_failed}
      end
    end
  end

  defp maybe_send(%{pace_ref: nil} = state), do: send_next(state)
  defp maybe_send(state), do: {:ok, state}

  defp maybe_send_or_complete(state) do
    cond do
      not :queue.is_empty(state.queue) -> send_next(state)
      state.current != nil and state.current.finished -> {:ok, complete_turn(state)}
      true -> {:ok, state}
    end
  end

  defp send_next(state) do
    case :queue.out(state.queue) do
      {{:value, payload}, queue} ->
        packet =
          Packet.new(payload,
            payload_type: 111,
            sequence_number: state.rtp_sequence,
            timestamp: state.rtp_timestamp,
            ssrc: state.ssrc,
            marker: not state.current.started
          )

        case state.send_rtp.(state.peer_connection, state.track_id, packet) do
          :ok ->
            state = maybe_notify_started(state)
            pace_ref = make_ref()
            _timer = state.schedule.(self(), {:vxpipe_audio_pace, pace_ref}, @frame_duration_ms)

            {:ok,
             %{
               state
               | pace_ref: pace_ref,
                 queue: queue,
                 rtp_sequence: rem(state.rtp_sequence + 1, 65_536),
                 rtp_timestamp: rem(state.rtp_timestamp + @rtp_timestamp_step, 4_294_967_296)
             }}

          {:error, _reason} ->
            {:error, :rtp_unavailable}
        end

      {:empty, _queue} ->
        {:ok, state}
    end
  end

  defp maybe_notify_started(%{current: %{started: false} = current} = state) do
    send(
      current.callback,
      {:vxpipe_audio_playback, self(), current.correlation_id, :started}
    )

    %{state | current: %{current | started: true}}
  end

  defp maybe_notify_started(state), do: state

  defp complete_turn(state) do
    current = state.current

    send(
      current.callback,
      {:vxpipe_audio_playback, self(), current.correlation_id, :completed}
    )

    %{state | current: nil, remainder: <<>>}
  end

  defp send_rtp(peer_connection, track_id, packet) do
    ExWebRTC.PeerConnection.send_rtp(peer_connection, track_id, packet)
  end
end
