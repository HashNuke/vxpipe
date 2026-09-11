defmodule Vxpipe.Gateway.Telephony.MediaRouting do
  @moduledoc false

  alias Vxpipe.CallEngine.ConnectionAttachment
  alias Vxpipe.Gateway.Media.{RoomAudioEgress, RoomAudioIngress}
  alias Vxpipe.Gateway.Telephony.MediaPipelineSet

  @spec start(ConnectionAttachment.t(), keyword()) ::
          {:ok, %{room_audio_egress: pid() | nil, room_audio_ingress: pid() | nil}}
          | {:error, term()}
  def start(%ConnectionAttachment{} = attachment, options) when is_list(options) do
    child_supervisor = Keyword.fetch!(options, :child_supervisor)
    connection_id = Keyword.fetch!(options, :connection_id)
    engine = Keyword.fetch!(options, :engine)
    identity = Keyword.fetch!(options, :identity)
    socket_owner = Keyword.fetch!(options, :socket_owner)
    stream_id = Keyword.fetch!(options, :stream_id)
    %MediaPipelineSet{} = media_pipelines = Keyword.fetch!(options, :media_pipelines)

    with {:ok, ingress} <-
           start_ingress(
             child_supervisor,
             connection_id,
             stream_id,
             attachment,
             identity,
             engine,
             media_pipelines.room_ingress
           ),
         {:ok, egress} <-
           start_egress(
             child_supervisor,
             connection_id,
             socket_owner,
             attachment,
             identity,
             engine,
             media_pipelines.room_egress
           ) do
      {:ok, %{room_audio_egress: egress, room_audio_ingress: ingress}}
    end
  end

  defp start_ingress(
         child_supervisor,
         connection_id,
         stream_id,
         attachment,
         identity,
         engine,
         pipeline
       ) do
    case engine.room_audio_configuration(attachment) do
      :disabled ->
        {:ok, nil}

      {:ok, configuration} ->
        options =
          identity ++
            [
              connection_id: connection_id,
              attachment: attachment,
              configuration: configuration,
              owner: self(),
              engine: engine,
              pipeline: pipeline,
              pipeline_supervisor: child_supervisor,
              pipeline_options: [track_id: stream_id]
            ]

        with {:ok, ingress} <-
               child_supervisor.start_child(connection_id, {RoomAudioIngress, options}),
             :ok <- RoomAudioIngress.start_pipeline(ingress),
             {:ok, _snapshot} <- engine.register_room_audio_enforcer(attachment, ingress),
             :ok <- RoomAudioIngress.await_ready(ingress) do
          {:ok, ingress}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp start_egress(
         child_supervisor,
         connection_id,
         socket_owner,
         attachment,
         identity,
         engine,
         pipeline
       ) do
    case engine.room_audio_output_configuration(attachment) do
      :disabled ->
        {:ok, nil}

      {:ok, %{mode: mode}} when mode in [:full_mix, :mix_minus] ->
        options =
          identity ++
            [
              connection_id: connection_id,
              attachment: attachment,
              owner: self(),
              engine: engine,
              pipeline: pipeline,
              pipeline_supervisor: child_supervisor,
              pipeline_options: [socket_owner: socket_owner]
            ]

        with {:ok, egress} <-
               child_supervisor.start_child(connection_id, {RoomAudioEgress, options}),
             :ok <- RoomAudioEgress.activate(egress),
             {:ok, _snapshot} <- engine.register_room_audio_enforcer(attachment, egress),
             :ok <- RoomAudioEgress.await_ready(egress) do
          {:ok, egress}
        end

      {:error, reason} ->
        {:error, reason}

      _invalid ->
        {:error, :invalid_room_audio_output_configuration}
    end
  end
end
