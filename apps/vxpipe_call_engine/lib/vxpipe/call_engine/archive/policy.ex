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

  @decisions_kinds [
    :decisions_evaluation,
    :decisions_question_result,
    :decisions_feedback_dispatched,
    :decisions_attempt
  ]

  @spec filter_payload(atom(), map(), map()) :: map()
  def filter_payload(kind, payload, %{"save_transcripts" => false})
      when kind in @transcript_kinds and is_map(payload) do
    drop_transcript_fields(payload)
  end

  def filter_payload(kind, payload, %{"save_transcripts" => false})
      when kind in @decisions_kinds and is_map(payload) do
    filter_decisions_payload(kind, payload)
  end

  def filter_payload(kind, payload, %{"save_transcripts" => true})
      when kind in @decisions_kinds, do: payload

  def filter_payload(kind, payload, _unknown_policy)
      when kind in @decisions_kinds and is_map(payload) do
    kind
    |> filter_decisions_payload(payload)
    |> Map.put("content_unavailable", %{"reason" => "unknown"})
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

  @decisions_text_fields ~w(question response feedback messages evidence candidate draft
    evaluated_draft accepted_replacement rejected_input rejected_draft proposed_calls)

  # A denied interval strips decisions text and any smuggled transcript text
  # at every depth, in both string and atom key forms.
  @decisions_denied_fields @decisions_text_fields ++ @text_fields

  defp filter_decisions_payload(:decisions_feedback_dispatched, payload) do
    payload
    |> Map.take(["evaluation_id", "policy_revision", "policy_digest"])
    |> Map.put("content_unavailable", %{"reason" => "denied"})
  end

  defp filter_decisions_payload(:decisions_question_result, payload) do
    payload
    |> drop_denied_fields()
    |> Map.delete(:probability_yes)
    |> Map.delete(:inferred_answer)
    |> Map.delete(:feedback_origin)
    |> Map.delete(:feedback_dispatched)
    |> Map.delete(:content_unavailable)
    |> Map.put("probability_yes", nil)
    |> Map.put("inferred_answer", nil)
    |> Map.put("feedback_origin", nil)
    |> Map.put("feedback_dispatched", false)
    |> Map.put("content_unavailable", %{"reason" => "denied"})
  end

  defp filter_decisions_payload(kind, payload)
       when kind in [:decisions_evaluation, :decisions_attempt] do
    payload
    |> drop_denied_fields()
    |> Map.delete(:content_unavailable)
    |> Map.put("content_unavailable", %{"reason" => "denied"})
  end

  defp drop_denied_fields(value) when is_map(value) do
    value
    |> Enum.reject(fn {key, _value} -> denied_field?(key) end)
    |> Map.new(fn {key, nested} -> {key, drop_denied_fields(nested)} end)
  end

  defp drop_denied_fields(value) when is_list(value),
    do: Enum.map(value, &drop_denied_fields/1)

  defp drop_denied_fields(value), do: value
  defp denied_field?(key) when is_atom(key), do: Atom.to_string(key) in @decisions_denied_fields
  defp denied_field?(key), do: key in @decisions_denied_fields
end
