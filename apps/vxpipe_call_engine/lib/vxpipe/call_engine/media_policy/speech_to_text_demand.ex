defmodule Vxpipe.CallEngine.MediaPolicy.SpeechToTextDemand do
  @moduledoc false

  alias Vxpipe.CallEngine.MediaPolicy.{Effective, Snapshot}

  @spec required?(Snapshot.t(), String.t()) :: boolean()
  def required?(%Snapshot{} = snapshot, source_participant_id),
    do: required?(snapshot, source_participant_id, nil)

  @spec required?(Snapshot.t(), String.t(), String.t() | nil) :: boolean()
  def required?(%Snapshot{} = snapshot, source_participant_id, activity_agent_id)
      when is_binary(source_participant_id) do
    MapSet.member?(snapshot.present_participant_ids, source_participant_id) and
      (snapshot.effective.save_transcripts or live_recipient?(snapshot, source_participant_id) or
         activity_required?(snapshot, source_participant_id, activity_agent_id))
  end

  defp activity_required?(_snapshot, _source, nil), do: false

  defp activity_required?(snapshot, source, agent) when is_binary(agent) do
    {true, true, true, true} == activity_authority(snapshot, source, agent)
  end

  @spec activity_authority_changed?(
          Snapshot.t() | nil,
          Snapshot.t(),
          String.t(),
          String.t() | nil
        ) ::
          boolean()
  def activity_authority_changed?(_previous, _snapshot, _source, nil), do: false
  def activity_authority_changed?(nil, _snapshot, _source, _agent), do: true

  def activity_authority_changed?(previous, snapshot, source, agent) do
    activity_authority(previous, source, agent) != activity_authority(snapshot, source, agent) or
      source_audio_intervals(previous, source) != source_audio_intervals(snapshot, source)
  end

  defp source_audio_intervals(snapshot, source) do
    {
      Snapshot.interval(snapshot, :audio_input, source),
      Snapshot.interval(snapshot, :audio_output, source)
    }
  end

  defp activity_authority(snapshot, source, agent) do
    {
      MapSet.member?(snapshot.present_participant_ids, source),
      MapSet.member?(snapshot.present_participant_ids, agent),
      Effective.audio_route_permitted?(snapshot.effective, source, agent),
      Effective.audio_route_permitted?(snapshot.effective, agent, source)
    }
  end

  defp live_recipient?(snapshot, source_participant_id) do
    Enum.any?(snapshot.present_participant_ids, fn recipient_participant_id ->
      Effective.transcript_route_permitted?(
        snapshot.effective,
        source_participant_id,
        recipient_participant_id
      )
    end)
  end
end
