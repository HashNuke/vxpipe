defmodule Vxpipe.CallEngine.MediaPolicy.SpeechToTextDemand do
  @moduledoc false

  alias Vxpipe.CallEngine.MediaPolicy.{Effective, Snapshot}

  @spec required?(Snapshot.t(), String.t()) :: boolean()
  def required?(%Snapshot{} = snapshot, source_participant_id)
      when is_binary(source_participant_id) do
    MapSet.member?(snapshot.present_participant_ids, source_participant_id) and
      (snapshot.effective.save_transcripts or live_recipient?(snapshot, source_participant_id))
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
