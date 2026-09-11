defmodule Vxpipe.Gateway.WebRTC.ConnectionPeerSupervisor do
  @moduledoc false

  use DynamicSupervisor

  alias ExWebRTC.PeerConnection
  alias Vxpipe.CallEngine
  alias Vxpipe.Gateway.WebRTC.{AudioEgress, AudioPipeline, RoomAudioIngress}

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

  def start_audio_egress(connection_id, peer_connection, track_id, maximum_packets) do
    options = [
      connection_id: connection_id,
      peer_connection: peer_connection,
      track_id: track_id,
      maximum_packets: maximum_packets
    ]

    DynamicSupervisor.start_child(via(connection_id), {AudioEgress, options})
  end

  def start_audio_pipeline(connection_id, options) do
    pipeline_id = Keyword.fetch!(options, :pipeline_id)

    child_spec = %{
      id: {AudioPipeline, pipeline_id},
      start: {AudioPipeline, :start_link, [options]},
      restart: :temporary
    }

    DynamicSupervisor.start_child(via(connection_id), child_spec)
  end

  def stop_audio_pipeline(connection_id, pipeline) when is_pid(pipeline) do
    DynamicSupervisor.terminate_child(via(connection_id), pipeline)
  end

  def start_room_audio_ingress(connection_id, attachment, identity, options \\ []) do
    engine = Keyword.get(options, :engine, CallEngine)

    case engine.room_audio_configuration(attachment) do
      :disabled ->
        {:ok, nil}

      {:ok, configuration} ->
        ingress_options =
          identity ++
            [
              connection_id: connection_id,
              attachment: attachment,
              configuration: configuration,
              owner: self(),
              jitter_latency_ms: Keyword.get(options, :jitter_latency_ms, 200),
              engine: engine,
              pipeline: Keyword.get(options, :pipeline, AudioPipeline),
              pipeline_supervisor: Keyword.get(options, :pipeline_supervisor, __MODULE__),
              pipeline_options: Keyword.get(options, :pipeline_options, [])
            ]

        start_and_register_room_audio_ingress(
          connection_id,
          attachment,
          engine,
          ingress_options
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp start_and_register_room_audio_ingress(
         connection_id,
         attachment,
         engine,
         ingress_options
       ) do
    case DynamicSupervisor.start_child(via(connection_id), {RoomAudioIngress, ingress_options}) do
      {:ok, ingress} ->
        with :ok <- RoomAudioIngress.start_pipeline(ingress),
             {:ok, _snapshot} <- engine.register_room_audio_enforcer(attachment, ingress) do
          {:ok, ingress}
        else
          {:error, reason} ->
            _ = DynamicSupervisor.terminate_child(via(connection_id), ingress)
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp via(connection_id) do
    {:via, Registry, {Vxpipe.Gateway.WebRTC.Registry, {:peer_supervisor, connection_id}}}
  end

  defp peer_via(connection_id) do
    {:via, Registry, {Vxpipe.Gateway.WebRTC.Registry, {:peer_connection, connection_id}}}
  end
end
