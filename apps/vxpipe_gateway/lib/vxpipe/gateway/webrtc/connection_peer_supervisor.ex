defmodule Vxpipe.Gateway.WebRTC.ConnectionPeerSupervisor do
  @moduledoc false

  use DynamicSupervisor

  alias ExWebRTC.PeerConnection
  alias Vxpipe.CallEngine
  alias Vxpipe.Gateway.Media.{RoomAudioEgress, RoomAudioIngress}

  alias Vxpipe.Gateway.WebRTC.{
    AudioEgress,
    AudioPipeline,
    RoomAudioOutputPipeline
  }

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
    pipeline_module = Keyword.get(options, :pipeline_module, AudioPipeline)

    child_spec = %{
      id: {pipeline_module, pipeline_id},
      start: {pipeline_module, :start_link, [Keyword.delete(options, :pipeline_module)]},
      restart: :temporary
    }

    connection_id
    |> via()
    |> DynamicSupervisor.start_child(child_spec)
    |> normalize_pipeline_start()
  end

  def stop_audio_pipeline(connection_id, pipeline) when is_pid(pipeline) do
    DynamicSupervisor.terminate_child(via(connection_id), pipeline)
  end

  def start_room_audio_output_pipeline(connection_id, options) do
    pipeline_id = Keyword.fetch!(options, :pipeline_id)
    pipeline_module = Keyword.get(options, :pipeline_module, RoomAudioOutputPipeline)

    child_spec = %{
      id: {pipeline_module, pipeline_id},
      start: {pipeline_module, :start_link, [Keyword.delete(options, :pipeline_module)]},
      restart: :temporary
    }

    connection_id
    |> via()
    |> DynamicSupervisor.start_child(child_spec)
    |> normalize_pipeline_start()
  end

  def stop_room_audio_output_pipeline(connection_id, pipeline) when is_pid(pipeline) do
    DynamicSupervisor.terminate_child(via(connection_id), pipeline)
  end

  def start_room_audio_ingress(connection_id, attachment, identity, options \\ []) do
    engine = Keyword.get(options, :engine, CallEngine)

    case engine.room_audio_configuration(attachment) do
      :disabled ->
        {:ok, nil}

      {:ok, configuration} ->
        pipeline_options =
          options
          |> Keyword.get(:pipeline_options, [])
          |> Keyword.put(:jitter_latency, Keyword.get(options, :jitter_latency_ms, 200))

        ingress_options =
          identity ++
            [
              connection_id: connection_id,
              attachment: attachment,
              configuration: configuration,
              owner: self(),
              engine: engine,
              pipeline: Keyword.get(options, :pipeline, AudioPipeline),
              pipeline_supervisor: Keyword.get(options, :pipeline_supervisor, __MODULE__),
              pipeline_options: pipeline_options
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

  def start_room_audio_egress(
        connection_id,
        attachment,
        identity,
        peer_connection,
        track_id,
        options \\ []
      ) do
    engine = Keyword.get(options, :engine, CallEngine)

    case engine.room_audio_output_configuration(attachment) do
      :disabled ->
        {:ok, nil}

      {:ok, %{mode: mode}} when mode in [:full_mix, :mix_minus] ->
        pipeline_options =
          options
          |> Keyword.get(:pipeline_options, [])
          |> Keyword.merge(peer_connection: peer_connection, track_id: track_id)

        egress_options =
          identity ++
            [
              connection_id: connection_id,
              attachment: attachment,
              owner: self(),
              engine: engine,
              pipeline: Keyword.get(options, :pipeline, RoomAudioOutputPipeline),
              pipeline_supervisor: Keyword.get(options, :pipeline_supervisor, __MODULE__),
              pipeline_options: pipeline_options
            ]

        start_and_register_room_audio_egress(
          connection_id,
          attachment,
          engine,
          egress_options
        )

      {:error, reason} ->
        {:error, reason}

      _invalid ->
        {:error, :invalid_room_audio_output_configuration}
    end
  end

  defp start_and_register_room_audio_egress(
         connection_id,
         attachment,
         engine,
         egress_options
       ) do
    case DynamicSupervisor.start_child(via(connection_id), {RoomAudioEgress, egress_options}) do
      {:ok, egress} ->
        with :ok <- RoomAudioEgress.activate(egress),
             {:ok, _snapshot} <- engine.register_room_audio_enforcer(attachment, egress) do
          {:ok, egress}
        else
          {:error, reason} ->
            _ = DynamicSupervisor.terminate_child(via(connection_id), egress)
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

  defp normalize_pipeline_start({:ok, supervisor, _pipeline}), do: {:ok, supervisor}
  defp normalize_pipeline_start(result), do: result
end
