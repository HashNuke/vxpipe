defmodule Vxpipe.Gateway.Telephony.MediaSessionSetup do
  @moduledoc false

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.Command.AttachConnection
  alias Vxpipe.CallEngine.ConnectionAttachment
  alias Vxpipe.Calls.TelephonyAdmissionClaim
  alias Vxpipe.Gateway.Media.{AudioOutput, RoomAudioEgress, RoomAudioIngress}

  alias Vxpipe.Gateway.Telephony.{
    MediaBinding,
    MediaChildrenSupervisor,
    MediaPipelineSet
  }

  @command_timeout_seconds 5

  @spec run(keyword()) :: {:ok, map()} | {:error, term()}
  def run(options) do
    claim = Keyword.fetch!(options, :claim)
    binding = Keyword.fetch!(options, :binding)
    connection_id = Keyword.fetch!(options, :connection_id)
    socket_owner = Keyword.fetch!(options, :socket_owner)
    stream_id = Keyword.fetch!(options, :stream_id)
    %MediaPipelineSet{} = media_pipelines = Keyword.fetch!(options, :media_pipelines)
    engine = Keyword.get(options, :engine, CallEngine)
    child_supervisor = Keyword.get(options, :child_supervisor, MediaChildrenSupervisor)
    identity = identity(binding)

    with :ok <- valid_runtime(claim, binding, socket_owner, stream_id),
         {:ok, output} <-
           start_output(child_supervisor, connection_id, socket_owner, identity, options),
         {:ok, command} <- attach_command(claim, binding),
         {:ok, %ConnectionAttachment{} = attachment} <-
           engine.attach_connection(command, output),
         {:ok, ingress} <-
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
      {:ok,
       %{
         attachment: attachment,
         audio_output: output,
         child_supervisor: child_supervisor,
         engine: engine,
         room_audio_egress: egress,
         room_audio_ingress: ingress
       }}
    else
      {:error, reason} -> {:error, reason}
      _invalid -> {:error, :media_attachment_failed}
    end
  end

  defp start_output(child_supervisor, connection_id, socket_owner, identity, options) do
    output_options =
      identity ++
        [
          connection_id: connection_id,
          owner: self(),
          maximum_frames: Keyword.get(options, :maximum_audio_frames, 500),
          pipeline: Keyword.fetch!(options, :media_pipelines).direct_output,
          pipeline_supervisor: child_supervisor,
          pipeline_options: [socket_owner: socket_owner]
        ]

    with {:ok, output} <-
           child_supervisor.start_child(connection_id, {AudioOutput, output_options}),
         :ok <- AudioOutput.start_pipeline(output),
         :ok <- AudioOutput.await_ready(output) do
      {:ok, output}
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

  defp attach_command(%TelephonyAdmissionClaim{} = claim, %MediaBinding{} = binding) do
    AttachConnection.new(
      tenant_id: binding.tenant_id,
      actor_id: claim.call.plan.actor_id,
      room_id: binding.room_id,
      incarnation_id: binding.incarnation_id,
      participant_id: binding.participant_id,
      connection_id: binding.client_state_leg_id,
      deadline: DateTime.add(DateTime.utc_now(), @command_timeout_seconds, :second)
    )
  end

  defp identity(%MediaBinding{} = binding) do
    [
      tenant_id: binding.tenant_id,
      room_id: binding.room_id,
      incarnation_id: binding.incarnation_id,
      participant_id: binding.participant_id
    ]
  end

  defp valid_runtime(claim, binding, socket_owner, stream_id) do
    if match?(%TelephonyAdmissionClaim{}, claim) and MediaBinding.valid?(binding) and
         is_pid(socket_owner) and is_binary(stream_id) and byte_size(stream_id) > 0 do
      :ok
    else
      {:error, :invalid_media_session}
    end
  end
end
