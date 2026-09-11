defmodule Vxpipe.Gateway.Telephony.MediaSession do
  @moduledoc false

  use GenServer

  alias Vxpipe.CallEngine.Command.ParticipantTransferControl
  alias Vxpipe.CallEngine.ConnectionAttachment
  alias Vxpipe.CallEngine.Media.AudioFrame
  alias Vxpipe.CallEngine.Telephony.{Event, MediaPacket}

  alias Vxpipe.Gateway.Telephony.{
    IncomingAudio,
    MediaBinding,
    MediaRouting,
    MediaSessionSetup
  }

  @call_timeout 5_000

  def start_link(options) do
    connection_id = Keyword.fetch!(options, :connection_id)
    GenServer.start_link(__MODULE__, options, name: via(connection_id))
  end

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :connection_id)},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary
    }
  end

  @spec handle_event(pid(), pid(), Event.t()) :: :ok | {:error, term()}
  def handle_event(session, source, %Event{} = event) do
    safe_call(session, {:event, source, event})
  end

  @spec report_transfer_control(pid(), pid(), ParticipantTransferControl.action()) ::
          :ok | {:error, term()}
  def report_transfer_control(session, source, action) when action in [:accept, :media_ready] do
    safe_call(session, {:transfer_control, source, action})
  end

  @spec snapshot(pid()) :: {:ok, map()} | {:error, term()}
  def snapshot(session), do: safe_call(session, :snapshot)

  @impl true
  def init(options) do
    socket_owner = Keyword.fetch!(options, :socket_owner)
    binding = Keyword.fetch!(options, :binding)

    monitors = %{
      Process.monitor(socket_owner) => :socket,
      Process.monitor(binding.leg) => :leg
    }

    case MediaSessionSetup.run(options) do
      {:ok, setup} ->
        monitors = Map.put(monitors, setup.attachment.room_monitor, :room)

        {:ok,
         Map.merge(setup, %{
           binding: binding,
           connection_id: Keyword.fetch!(options, :connection_id),
           monitors: monitors,
           reported_transfer_controls: MapSet.new(),
           socket_owner: socket_owner,
           stream_id: Keyword.fetch!(options, :stream_id)
         })}

      {:error, _reason} ->
        {:stop, :media_attachment_failed}
    end
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    {:reply,
     {:ok,
      Map.take(state, [
        :attachment,
        :audio_output,
        :connection_id,
        :room_audio_egress,
        :room_audio_ingress,
        :stream_id
      ])}, state}
  end

  def handle_call({:event, source, _event}, _from, %{socket_owner: socket_owner} = state)
      when source != socket_owner do
    {:reply, {:error, :wrong_media_source}, state}
  end

  def handle_call(
        {:transfer_control, source, _action},
        _from,
        %{socket_owner: socket_owner} = state
      )
      when source != socket_owner do
    {:reply, {:error, :wrong_media_source}, state}
  end

  def handle_call(
        {:transfer_control, source, action},
        _from,
        %{socket_owner: source} = state
      ) do
    case transfer_control_outcome(action, state) do
      {:ok, state} -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(
        {:event, source,
         %Event{kind: :media, stream_id: stream_id, media: %MediaPacket{}} = event},
        _from,
        %{socket_owner: source, stream_id: stream_id} = state
      ) do
    result =
      state.engine
      |> IncomingAudio.deliver(
        state.attachment,
        state.room_audio_ingress,
        audio_frame(state.binding, event)
      )
      |> normalize_delivery()

    {:reply, result, state}
  end

  def handle_call({:event, _source, _event}, _from, state) do
    {:reply, {:error, :unsupported_media_event}, state}
  end

  @impl true
  def handle_info({:DOWN, monitor, :process, _process, _reason}, %{monitors: monitors} = state)
      when is_map_key(monitors, monitor) do
    {:stop, :normal, state}
  end

  def handle_info({:vxpipe_connection_unavailable, _reason}, state) do
    {:stop, :media_unavailable, state}
  end

  def handle_info(
        {:vxpipe_transfer_main_media, attempt_id,
         %ConnectionAttachment{admission: :main} = attachment},
        %{
          attachment: %ConnectionAttachment{
            admission: :transfer_preparation,
            transfer_attempt_id: attempt_id
          }
        } = state
      ) do
    case MediaRouting.start(attachment, routing_options(state)) do
      {:ok, routing} ->
        state = %{
          state
          | attachment: attachment,
            room_audio_egress: routing.room_audio_egress,
            room_audio_ingress: routing.room_audio_ingress
        }

        {:noreply, state}

      {:error, _reason} ->
        {:stop, :media_unavailable, state}
    end
  end

  def handle_info({:vxpipe_event, _event}, state), do: {:noreply, state}
  def handle_info(_message, state), do: {:noreply, state}

  defp audio_frame(%MediaBinding{} = binding, %Event{media: %MediaPacket{} = media} = event) do
    %AudioFrame{
      tenant_id: binding.tenant_id,
      room_id: binding.room_id,
      incarnation_id: binding.incarnation_id,
      participant_id: binding.participant_id,
      connection_id: binding.client_state_leg_id,
      track_id: event.stream_id,
      codec: media.codec,
      sample_rate: media.sample_rate,
      channels: media.channels,
      sequence_number: media.sequence_number,
      timestamp: media.timestamp,
      payload: media.payload,
      received_at: System.monotonic_time(:millisecond)
    }
  end

  defp normalize_delivery(:ok), do: :ok
  defp normalize_delivery(:drop), do: :ok
  defp normalize_delivery(:unavailable), do: {:error, :media_unavailable}

  defp transfer_control_command(state, attempt_id, action) do
    ParticipantTransferControl.new(
      tenant_id: state.binding.tenant_id,
      actor_id: state.actor_id,
      room_id: state.binding.room_id,
      incarnation_id: state.binding.incarnation_id,
      participant_id: state.binding.participant_id,
      connection_id: state.connection_id,
      attempt_id: attempt_id,
      action: action,
      deadline: DateTime.add(DateTime.utc_now(), 5, :second)
    )
  end

  defp transfer_control_outcome(action, state) do
    cond do
      MapSet.member?(state.reported_transfer_controls, action) ->
        {:ok, state}

      match?(
        %ConnectionAttachment{admission: :transfer_preparation},
        state.attachment
      ) ->
        submit_transfer_control(action, state)

      true ->
        {:error, :transfer_not_pending}
    end
  end

  defp submit_transfer_control(action, state) do
    with {:ok, command} <-
           transfer_control_command(state, state.attachment.transfer_attempt_id, action),
         :ok <- state.engine.participant_transfer_control(command) do
      reported = MapSet.put(state.reported_transfer_controls, action)
      {:ok, %{state | reported_transfer_controls: reported}}
    end
  end

  defp routing_options(state) do
    [
      child_supervisor: state.child_supervisor,
      connection_id: state.connection_id,
      engine: state.engine,
      identity: state.identity,
      media_pipelines: state.media_pipelines,
      socket_owner: state.socket_owner,
      stream_id: state.stream_id
    ]
  end

  defp safe_call(server, message) do
    GenServer.call(server, message, @call_timeout)
  catch
    :exit, _reason -> {:error, :media_session_not_found}
  end

  defp via(connection_id) do
    {:via, Registry, {Vxpipe.Gateway.Media.Registry, {:telephony_media_session, connection_id}}}
  end
end
