defmodule Vxpipe.Gateway.WebRTC.Connection do
  @moduledoc false

  use GenServer

  alias ExWebRTC.{DataChannel, PeerConnection, SessionDescription}
  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.Command.{AttachConnection, SendText}
  alias Vxpipe.CallEngine.Error
  alias Vxpipe.CallEngine.Event.TextOutput
  alias Vxpipe.Gateway.RTVI.Codec
  alias Vxpipe.Gateway.WebRTC.ConnectionPeerSupervisor

  @call_timeout 10_000
  @command_timeout_seconds 5

  def start_link(options) do
    connection_id = Keyword.fetch!(options, :connection_id)
    GenServer.start_link(__MODULE__, options, name: via(:connection, connection_id))
  end

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :connection_id)},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary
    }
  end

  def negotiate(connection_id, %SessionDescription{} = offer) do
    call(connection_id, {:negotiate, offer})
  end

  def add_ice_candidates(connection_id, candidates) when is_list(candidates) do
    call(connection_id, {:add_ice_candidates, candidates})
  end

  @impl true
  def init(options) do
    connection_id = Keyword.fetch!(options, :connection_id)
    session = Keyword.fetch!(options, :session)

    with {:ok, attach_command} <- attach_command(connection_id, session),
         {:ok, room_monitor} <- CallEngine.attach_connection(attach_command),
         {:ok, peer_connection} <-
           ConnectionPeerSupervisor.start_peer(
             connection_id,
             self(),
             Keyword.fetch!(options, :ice_servers)
           ) do
      {:ok,
       %{
         candidate_gathering_timeout_ms: Keyword.fetch!(options, :candidate_gathering_timeout_ms),
         channel_ref: nil,
         connection_id: connection_id,
         peer_connection: peer_connection,
         peer_monitor: Process.monitor(peer_connection),
         room_monitor: room_monitor,
         session: session
       }}
    else
      _error -> {:stop, :connection_attachment_failed}
    end
  end

  @impl true
  def handle_call({:negotiate, offer}, _from, state) do
    reply = negotiate_peer(state.peer_connection, offer, state.candidate_gathering_timeout_ms)
    {:reply, reply, state}
  end

  def handle_call({:add_ice_candidates, candidates}, _from, state) do
    result =
      Enum.reduce_while(candidates, :ok, fn candidate, :ok ->
        case PeerConnection.add_ice_candidate(state.peer_connection, candidate) do
          :ok -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    {:reply, result, state}
  end

  @impl true
  def handle_info({:ex_webrtc, peer_connection, {:data_channel, %DataChannel{} = channel}}, state)
      when peer_connection == state.peer_connection do
    state = if channel.label == "chat", do: %{state | channel_ref: channel.ref}, else: state
    {:noreply, state}
  end

  def handle_info(
        {:ex_webrtc, peer_connection, {:data, channel_ref, payload}},
        %{peer_connection: peer_connection, channel_ref: channel_ref} = state
      ) do
    case Codec.handle(payload) do
      {:reply, reply} -> :ok = PeerConnection.send_data(peer_connection, channel_ref, reply)
      {:command, {:send_text, input}} -> submit_text(input, state)
      :ignore -> :ok
    end

    {:noreply, state}
  end

  def handle_info(
        {:ex_webrtc, peer_connection, {:data_channel_state_change, channel_ref, :closed}},
        %{peer_connection: peer_connection, channel_ref: channel_ref} = state
      ) do
    {:stop, :shutdown, state}
  end

  def handle_info(
        {:ex_webrtc, peer_connection, {:connection_state_change, connection_state}},
        %{peer_connection: peer_connection} = state
      )
      when connection_state in [:closed, :failed] do
    {:stop, :shutdown, state}
  end

  def handle_info(
        {:DOWN, peer_monitor, :process, _pid, _reason},
        %{peer_monitor: peer_monitor} = state
      ) do
    {:stop, :shutdown, state}
  end

  def handle_info(
        {:DOWN, room_monitor, :process, _pid, _reason},
        %{room_monitor: room_monitor} = state
      ) do
    {:stop, :shutdown, state}
  end

  def handle_info(
        {:vxpipe_event, %TextOutput{connection_id: connection_id} = event},
        %{connection_id: connection_id} = state
      ) do
    with channel_ref when not is_nil(channel_ref) <- state.channel_ref,
         {:ok, message} <- Codec.encode_event(event) do
      :ok = PeerConnection.send_data(state.peer_connection, channel_ref, message)
    end

    {:noreply, state}
  end

  def handle_info({:vxpipe_connection_unavailable, _reason}, state) do
    {:stop, :shutdown, state}
  end

  def handle_info({:ex_webrtc, _peer_connection, _event}, state), do: {:noreply, state}

  defp call(connection_id, message) do
    case Registry.lookup(Vxpipe.Gateway.WebRTC.Registry, {:connection, connection_id}) do
      [{connection, _value}] -> GenServer.call(connection, message, @call_timeout)
      [] -> {:error, :connection_not_found}
    end
  end

  defp attach_command(connection_id, session) do
    AttachConnection.new(
      tenant_id: session.tenant_id,
      actor_id: session.actor_id,
      room_id: session.room_id,
      incarnation_id: session.incarnation_id,
      participant_id: session.participant_id,
      connection_id: connection_id,
      deadline: command_deadline()
    )
  end

  defp submit_text(input, state) do
    result =
      with {:ok, command} <-
             SendText.new(
               tenant_id: state.session.tenant_id,
               actor_id: state.session.actor_id,
               room_id: state.session.room_id,
               incarnation_id: state.session.incarnation_id,
               participant_id: state.session.participant_id,
               connection_id: state.connection_id,
               correlation_id: input.id,
               content: input.content,
               run_immediately: input.run_immediately,
               audio_response: input.audio_response,
               deadline: command_deadline()
             ),
           :ok <- CallEngine.send_text(command) do
        :ok
      end

    case result do
      :ok ->
        :ok

      {:error, %Error{}} ->
        reply = Codec.encode_error_response(input.id, "The text input could not be accepted.")
        :ok = PeerConnection.send_data(state.peer_connection, state.channel_ref, reply)
    end
  end

  defp command_deadline do
    DateTime.add(DateTime.utc_now(), @command_timeout_seconds, :second)
  end

  defp negotiate_peer(peer_connection, offer, gathering_timeout_ms) do
    with :ok <- PeerConnection.set_remote_description(peer_connection, offer),
         {:ok, answer} <- PeerConnection.create_answer(peer_connection),
         :ok <- PeerConnection.set_local_description(peer_connection, answer),
         :ok <- await_candidate_gathering(peer_connection, gathering_timeout_ms),
         %SessionDescription{} = local_description <-
           PeerConnection.get_local_description(peer_connection) do
      {:ok, local_description}
    end
  end

  defp await_candidate_gathering(peer_connection, timeout_ms) do
    receive do
      {:ex_webrtc, ^peer_connection, {:ice_gathering_state_change, :complete}} -> :ok
    after
      timeout_ms -> :ok
    end
  end

  defp via(:connection, connection_id) do
    {:via, Registry, {Vxpipe.Gateway.WebRTC.Registry, {:connection, connection_id}}}
  end
end
