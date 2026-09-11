defmodule Vxpipe.CallEngine.RoomIncarnationSupervisor.RecordingChildren do
  @moduledoc false

  alias Vxpipe.CallEngine.{ResolvedCallPlan, RoomMixer, RoomRecording}

  @spec prepare(keyword()) :: {keyword(), [Supervisor.child_spec()]}
  def prepare(options) do
    settings = Keyword.get(options, :recording, enabled: false)

    if Keyword.get(settings, :enabled, false) do
      enable(options, settings)
    else
      {options, []}
    end
  end

  defp enable(options, settings) do
    plan = Keyword.fetch!(options, :plan)
    incarnation_id = Keyword.fetch!(options, :incarnation_id)
    recording_token = make_ref()

    options =
      Keyword.update!(options, :room_mixer, fn mixer_options ->
        Keyword.put(mixer_options, :recording_token, recording_token)
      end)

    recording_options =
      settings
      |> Keyword.drop([:enabled])
      |> Keyword.merge(recording_options(plan, incarnation_id, recording_token))

    {options, [{RoomRecording, recording_options}]}
  end

  defp recording_options(%ResolvedCallPlan{} = plan, incarnation_id, recording_token) do
    [
      tenant_id: plan.tenant_id,
      call_id: plan.call_id,
      room_id: plan.room_id,
      incarnation_id: incarnation_id,
      mixer: RoomMixer.ref(incarnation_id),
      recording_token: recording_token
    ]
  end
end
