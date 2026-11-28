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
    :decisions_attempt
  ]

  @spec new([Vxpipe.Calls.CallFact.t()], VariableSnapshotHistory.t()) :: t()
  def new(facts, %VariableSnapshotHistory{} = variable_snapshots) when is_list(facts) do
    %__MODULE__{
      facts: facts,
      timeline: CallTimeline.project(facts, variable_snapshots.snapshots),
      transcript: Enum.filter(facts, &transcript_fact?/1),
      tool_history: Enum.filter(facts, &(&1.kind in @tool_kinds)),
      decisions: Enum.filter(facts, &(&1.kind in @decisions_kinds)),
      variable_snapshots: variable_snapshots,
      archive_status: ArchiveStatus.from_facts(facts)
    }
  end

  defp transcript_fact?(%{kind: kind, payload: payload, participant_id: id}) do
    MessagePayload.project(kind, payload, id) != nil
  end

  defp transcript_fact?(_fact), do: false
end
