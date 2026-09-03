defmodule Vxpipe.Gateway.WebRTC.Connection do
  @moduledoc false

  use GenServer

  alias ExWebRTC.{DataChannel, PeerConnection, SessionDescription}
  alias Vxpipe.Gateway.RTVI.Codec
  alias Vxpipe.Gateway.WebRTC.ConnectionPeerSupervisor

  @call_timeout 10_000

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

    {:ok, peer_connection} =
      ConnectionPeerSupervisor.start_peer(
        connection_id,
        self(),
        Keyword.fetch!(options, :ice_servers)
      )

    {:ok,
     %{
       candidate_gathering_timeout_ms: Keyword.fetch!(options, :candidate_gathering_timeout_ms),
       channel_ref: nil,
       connection_id: connection_id,
       peer_connection: peer_connection,
       peer_monitor: Process.monitor(peer_connection),
       session: Keyword.fetch!(options, :session)
     }}
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

  def handle_info({:ex_webrtc, _peer_connection, _event}, state), do: {:noreply, state}

  defp call(connection_id, message) do
    case Registry.lookup(Vxpipe.Gateway.WebRTC.Registry, {:connection, connection_id}) do
      [{connection, _value}] -> GenServer.call(connection, message, @call_timeout)
      [] -> {:error, :connection_not_found}
    end
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
