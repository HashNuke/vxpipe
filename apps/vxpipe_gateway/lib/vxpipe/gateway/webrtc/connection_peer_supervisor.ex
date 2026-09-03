defmodule Vxpipe.Gateway.WebRTC.ConnectionPeerSupervisor do
  @moduledoc false

  use DynamicSupervisor

  alias ExWebRTC.PeerConnection

  def start_link(options) do
    connection_id = Keyword.fetch!(options, :connection_id)
    DynamicSupervisor.start_link(__MODULE__, :ok, name: via(connection_id))
  end

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :connection_id)},
      start: {__MODULE__, :start_link, [options]},
      type: :supervisor
    }
  end

  @impl true
  def init(:ok), do: DynamicSupervisor.init(strategy: :one_for_one)

  def start_peer(connection_id, controlling_process, ice_servers) do
    child_spec = %{
      id: PeerConnection,
      start:
        {PeerConnection, :start_link,
         [
           [ice_servers: ice_servers, controlling_process: controlling_process],
           [name: peer_via(connection_id)]
         ]},
      restart: :temporary
    }

    DynamicSupervisor.start_child(via(connection_id), child_spec)
  end

  defp via(connection_id) do
    {:via, Registry, {Vxpipe.Gateway.WebRTC.Registry, {:peer_supervisor, connection_id}}}
  end

  defp peer_via(connection_id) do
    {:via, Registry, {Vxpipe.Gateway.WebRTC.Registry, {:peer_connection, connection_id}}}
  end
end
