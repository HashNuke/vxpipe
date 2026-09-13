defmodule Vxpipe.Gateway.Telephony.MediaSessionSetup do
  @moduledoc false

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.Command.AttachConnection
  alias Vxpipe.CallEngine.ConnectionAttachment
  alias Vxpipe.Gateway.Media.AudioOutput

  alias Vxpipe.Gateway.Telephony.{
    MediaBinding,
    MediaChildrenSupervisor,
    MediaPipelineSet,
    MediaRouting
  }

  @command_timeout_seconds 5

  @spec run(keyword()) :: {:ok, map()} | {:error, term()}
  def run(options) do
    actor_id = Keyword.fetch!(options, :actor_id)
    binding = Keyword.fetch!(options, :binding)
    connection_id = Keyword.fetch!(options, :connection_id)
    socket_owner = Keyword.fetch!(options, :socket_owner)
    stream_id = Keyword.fetch!(options, :stream_id)
    %MediaPipelineSet{} = media_pipelines = Keyword.fetch!(options, :media_pipelines)
    engine = Keyword.get(options, :engine, CallEngine)
    child_supervisor = Keyword.get(options, :child_supervisor, MediaChildrenSupervisor)
    identity = identity(binding)

    with :ok <- valid_runtime(actor_id, binding, socket_owner, stream_id),
         {:ok, output} <-
           start_output(
             child_supervisor,
             connection_id,
             socket_owner,
             stream_id,
             identity,
             options
           ),
         {:ok, command} <- attach_command(actor_id, binding),
         {:ok, %ConnectionAttachment{} = attachment} <-
           engine.attach_connection(command, output),
         {:ok, routing} <- MediaRouting.start(attachment, routing_options(options, identity)) do
      {:ok,
       %{
         actor_id: actor_id,
         attachment: attachment,
         attach_command: command,
         audio_output: output,
         child_supervisor: child_supervisor,
         engine: engine,
         identity: identity,
         media_pipelines: media_pipelines,
         room_audio_egress: routing.room_audio_egress,
         room_audio_ingress: routing.room_audio_ingress
       }}
    else
      {:error, reason} -> {:error, reason}
      _invalid -> {:error, :media_attachment_failed}
    end
  end

  defp start_output(
         child_supervisor,
         connection_id,
         socket_owner,
         stream_id,
         identity,
         options
       ) do
    output_options =
      identity ++
        [
          connection_id: connection_id,
          owner: self(),
          maximum_frames: Keyword.get(options, :maximum_audio_frames, 500),
          pipeline: Keyword.fetch!(options, :media_pipelines).direct_output,
          playback_clearer: Keyword.fetch!(options, :media_pipelines).playback_clearer,
          pipeline_supervisor: child_supervisor,
          pipeline_options: [socket_owner: socket_owner, stream_id: stream_id]
        ]

    with {:ok, output} <-
           child_supervisor.start_child(connection_id, {AudioOutput, output_options}),
         :ok <- AudioOutput.start_pipeline(output),
         :ok <- AudioOutput.await_ready(output) do
      {:ok, output}
    end
  end

  defp attach_command(actor_id, %MediaBinding{} = binding) do
    AttachConnection.new(
      tenant_id: binding.tenant_id,
      actor_id: actor_id,
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

  defp routing_options(options, identity) do
    [
      child_supervisor: Keyword.get(options, :child_supervisor, MediaChildrenSupervisor),
      connection_id: Keyword.fetch!(options, :connection_id),
      engine: Keyword.get(options, :engine, CallEngine),
      identity: identity,
      media_pipelines: Keyword.fetch!(options, :media_pipelines),
      socket_owner: Keyword.fetch!(options, :socket_owner),
      stream_id: Keyword.fetch!(options, :stream_id)
    ]
  end

  defp valid_runtime(actor_id, binding, socket_owner, stream_id) do
    if is_binary(actor_id) and byte_size(actor_id) > 0 and MediaBinding.valid?(binding) and
         is_pid(socket_owner) and is_binary(stream_id) and byte_size(stream_id) > 0 do
      :ok
    else
      {:error, :invalid_media_session}
    end
  end
end
