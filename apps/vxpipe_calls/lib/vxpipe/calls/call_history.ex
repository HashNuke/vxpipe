defmodule Vxpipe.Calls.CallHistory do
  @moduledoc "An authorized private projection of one call's archived history."

  alias Vxpipe.Calls.{ArchiveStatus, CallTimeline, VariableSnapshotHistory}
  alias Vxpipe.CallEngine.Archive.MessagePayload

  @derive {Inspect,
           except: [
             :facts,
             :timeline,
             :transcript,
             :tool_history,
             :decisions,
             :variable_snapshots,
             :archive_status
           ]}
  @enforce_keys [
    :facts,
    :timeline,
    :transcript,
    :tool_history,
    :decisions,
    :variable_snapshots,
    :archive_status
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          facts: [Vxpipe.Calls.CallFact.t()],
          timeline: [Vxpipe.Calls.CallTimelineEntry.t()],
          transcript: [Vxpipe.Calls.CallFact.t()],
          tool_history: [Vxpipe.Calls.CallFact.t()],
          decisions: [Vxpipe.Calls.CallFact.t()],
          variable_snapshots: VariableSnapshotHistory.t(),
          archive_status: ArchiveStatus.t()
        }

  @tool_kinds [
    :tool_call_started,
    :tool_call_completed,
    :tool_call_failed,
    :tool_call_cancelled
  ]
  @decisions_kinds [
    :decisions_evaluation,
    :decisions_question_result,
    :decisions_feedback_dispatched,
    :decisions_attempt
  ]

  @spec new([Vxpipe.Calls.CallFact.t()], VariableSnapshotHistory.t()) :: t()
  def new(facts, %VariableSnapshotHistory{} = variable_snapshots) when is_list(facts) do
    %__MODULE__{
      facts: facts,
      timeline: CallTimeline.project(facts, variable_snapshots.snapshots),
      transcript: Enum.filter(facts, &transcript_fact?/1),
      tool_history: Enum.filter(facts, &(&1.kind in @tool_kinds)),
      decisions: decisions(facts),
      variable_snapshots: variable_snapshots,
      archive_status: ArchiveStatus.from_facts(facts)
    }
  end

  @doc "Projects computed question results and their subsequent private dispatch receipts."
  @spec decisions([Vxpipe.Calls.CallFact.t()]) :: [Vxpipe.Calls.CallFact.t()]
  def decisions(facts) do
    facts = Enum.filter(facts, &(&1.kind in @decisions_kinds))

    delivered =
      for %{kind: :decisions_feedback_dispatched, payload: %{"question_ids" => ids}} = receipt <-
            facts,
          receipt.source_policy["save_transcripts"] == true,
          id <- ids,
          into: MapSet.new(),
          do: feedback_key(receipt, id)

    Enum.map(facts, fn
      %{
        kind: :decisions_question_result,
        payload: %{"outcome" => "failed", "question_id" => id} = payload
      } = question ->
        if question.source_policy["save_transcripts"] == true and
             is_nil(payload["content_unavailable"]) and
             MapSet.member?(delivered, feedback_key(question, id)) do
          %{question | payload: Map.put(payload, "feedback_dispatched", true)}
        else
          question
        end

      fact ->
        fact
    end)
  end

  defp feedback_key(fact, id) do
    {fact.activation_id, fact.participant_id, fact.source_participant_id,
     fact.payload["policy_revision"], fact.payload["policy_digest"],
     fact.payload["evaluation_id"], id}
  end

  defp transcript_fact?(%{kind: kind, payload: payload, participant_id: id}) do
    MessagePayload.project(kind, payload, id) != nil
  end

  defp transcript_fact?(_fact), do: false
end
