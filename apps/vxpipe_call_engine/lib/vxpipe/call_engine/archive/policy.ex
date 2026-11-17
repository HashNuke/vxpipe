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
    drop_transcript_fields(payload)
  end

  def filter_payload(_kind, payload, _source_policy), do: payload

  @text_fields ~w(content text message summary conversation_summary cue raw_response raw_content decision dialogue)

  defp drop_transcript_fields(value) when is_map(value) do
    value
    |> Enum.reject(fn {key, _value} -> text_field?(key) end)
    |> Map.new(fn {key, nested} -> {key, drop_transcript_fields(nested)} end)
  end

  defp drop_transcript_fields(value) when is_list(value),
    do: Enum.map(value, &drop_transcript_fields/1)

  defp drop_transcript_fields(value), do: value
  defp text_field?(key) when is_atom(key), do: Atom.to_string(key) in @text_fields
  defp text_field?(key), do: key in @text_fields
end
