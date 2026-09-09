defmodule Vxpipe.CallEngine.Archive.Policy do
  @moduledoc false

  @transcript_kinds [
    :accepted_input,
    :participant_transcription_final,
    :agent_output_generated,
    :agent_output_delivery_started,
    :agent_output_delivery_progressed,
    :agent_output_delivered
  ]

  @spec filter_payload(atom(), map(), map()) :: map()
  def filter_payload(kind, payload, %{"save_transcripts" => false})
      when kind in @transcript_kinds and is_map(payload) do
    Map.drop(payload, ["content", "text", :content, :text])
  end

  def filter_payload(_kind, payload, _source_policy), do: payload
end
