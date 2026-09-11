defmodule Vxpipe.Gateway.Telephony.MediaSession do
  @moduledoc false

  use GenServer

  alias Vxpipe.CallEngine.Media.AudioFrame
  alias Vxpipe.CallEngine.Telephony.{Event, MediaPacket}

  alias Vxpipe.Gateway.Telephony.{
    IncomingAudio,
    MediaBinding,
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

  defp safe_call(server, message) do
    GenServer.call(server, message, @call_timeout)
  catch
    :exit, _reason -> {:error, :media_session_not_found}
  end

  defp via(connection_id) do
    {:via, Registry, {Vxpipe.Gateway.Media.Registry, {:telephony_media_session, connection_id}}}
  end
end
