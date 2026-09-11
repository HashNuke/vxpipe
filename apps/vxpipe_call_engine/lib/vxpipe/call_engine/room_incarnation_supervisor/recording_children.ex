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
    settings = Keyword.update(settings, :targets, [], &resolve_targets(&1, plan))

    options =
      Keyword.update!(options, :room_mixer, fn mixer_options ->
        mixer_options
        |> Keyword.put(:recording_token, recording_token)
        |> Keyword.put(
          :maximum_recording_egress_frames,
          Keyword.get(settings, :maximum_egress_frames, 100)
        )
      end)

    recording_options =
      settings
      |> Keyword.drop([:enabled, :maximum_egress_frames])
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

  defp resolve_targets(targets, plan) when is_list(targets) do
    Enum.map(targets, &resolve_target(&1, plan))
  end

  defp resolve_targets(invalid, _plan), do: invalid

  defp resolve_target(:individual_tracks, plan) do
    participant_ids =
      plan.participants
      |> Map.values()
      |> Enum.map(& &1.participant_id)
      |> Enum.sort()

    {:individual_tracks, participant_ids}
  end

  defp resolve_target({:individual_participants, references}, plan) when is_list(references) do
    case participant_ids(references, plan.participants) do
      {:ok, participant_ids} -> {:individual_tracks, participant_ids}
      :error -> :invalid_recording_target
    end
  end

  defp resolve_target(target, _plan), do: target

  defp participant_ids(references, participants) do
    Enum.reduce_while(references, {:ok, []}, fn reference, {:ok, participant_ids} ->
      case Map.fetch(participants, reference) do
        {:ok, participant} -> {:cont, {:ok, participant_ids ++ [participant.participant_id]}}
        :error -> {:halt, :error}
      end
    end)
  end
end
